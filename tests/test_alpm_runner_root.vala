/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// AlpmRunner as root, on a pacman installation in a temporary directory:
// libalpm runs the install scriptlets and the hooks in a chroot of the test root,
// which needs root. The root gets a copy of bash to run them.
// The hooks of the system are never run: the test pacman.conf sets HookDir
namespace Pamac {
	AlpmTestEnv env;
	AlpmRunner runner;
	RecordingSink sink;
	AlpmClient client;

	const string INSTALL_SCRIPT = """
post_install () {
	echo "pamac test scriptlet: installed $1"
	echo done > /scriptlet-done
}

pre_remove () {
	echo "pamac test scriptlet: removing $1"
}
""";

	const string HOOK = """
[Trigger]
Operation = Install
Type = Package
Target = testhook

[Action]
Description = pamac test hook
When = PostTransaction
Exec = /bin/sh -c 'echo pamac test hook output; echo done > /hook-done'
""";

	async void install_with_scriptlet_and_hook () throws Error {
		bool refreshed = yield runner.trans_refresh (client, false, false);
		assert_operation (refreshed, sink, "refresh");
		var request = new TransactionRequest ();
		request.to_install = {"testhook"};
		bool installed = yield runner.trans_run (client, request);
		assert_operation (installed, sink, "install");
		assert (env.root_file_exists ("opt/test/testhook.bin"));
		// the scriptlet ran in the chroot, its output is sent to the sink
		assert (env.root_file_exists ("scriptlet-done"));
		assert (sink.has ("script_output", "pamac test scriptlet: installed 1.0-1"));
		// the hook too, with its progress
		assert (env.root_file_exists ("hook-done"));
		assert (sink.has ("script_output", "pamac test hook output"));
		assert (sink.has ("hook_progress", "pamac test hook"));
	}

	void test_install_with_scriptlet_and_hook () {
		run_async_test ((cb) => install_with_scriptlet_and_hook.begin (cb), (res) => install_with_scriptlet_and_hook.end (res));
	}

	async void remove_with_scriptlet () throws Error {
		var request = new TransactionRequest ();
		request.to_remove = {"testhook"};
		bool removed = yield runner.trans_run (client, request);
		assert_operation (removed, sink, "remove");
		assert (!env.root_file_exists ("opt/test/testhook.bin"));
		assert (sink.has ("script_output", "pamac test scriptlet: removing 1.0-1"));
	}

	void test_remove_with_scriptlet () {
		run_async_test ((cb) => remove_with_scriptlet.begin (cb), (res) => remove_with_scriptlet.end (res));
	}

	// copy bash and its libraries in the test root, as /bin/sh
	void install_shell () throws Error {
		AlpmTestEnv.run ({"sh", "-c", """
root="$1"
bash=$(command -v bash)
for file in "$bash" $(ldd "$bash" | grep -o '/[^ ]*'); do
	mkdir -p "$root$(dirname "$file")"
	cp -L "$file" "$root$file"
done
mkdir -p "$root/bin"
[ -e "$root/bin/sh" ] || ln -s "$bash" "$root/bin/sh"
""", "sh", env.root_dir});
	}

	void setup_env () throws Error {
		env = new AlpmTestEnv ();
		install_shell ();
		string pkg_path = env.add_package ("testhook", "1.0", 4, INSTALL_SCRIPT);
		env.repo_add ({pkg_path});
		FileUtils.set_contents (Path.build_filename (env.hooks_dir, "pamac-test.hook"), HOOK);
		// no download to cancel here: a local repository
		env.write_pacman_conf ("file://" + env.repo_dir);
		runner = new AlpmRunner (env.create_alpm_utils (), MainContext.default ());
		sink = new RecordingSink ("root");
		client = new AlpmClient (sink);
	}
}

int main (string[] args) {
	Pamac.init_tests (ref args);
	if (Posix.geteuid () != 0) {
		print ("skipped: needs root, see README.md\n");
		return Pamac.SKIP;
	}
	string? missing = Pamac.AlpmTestEnv.find_missing_program ({"bsdtar", "repo-add", "ldd", "bash"});
	if (missing != null) {
		print ("skipped: %s not found\n", missing);
		return Pamac.SKIP;
	}
	try {
		Pamac.setup_env ();
	} catch (Error e) {
		printerr ("failed to create the test environment: %s\n", e.message);
		return 1;
	}
	Test.add_func ("/alpm_runner_root/install_with_scriptlet_and_hook", Pamac.test_install_with_scriptlet_and_hook);
	Test.add_func ("/alpm_runner_root/remove_with_scriptlet", Pamac.test_remove_with_scriptlet);
	int status = Test.run ();
	Pamac.env.cleanup ();
	return status;
}
