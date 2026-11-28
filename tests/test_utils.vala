/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// unit tests of the thread helpers and of TransactionRequest
namespace Pamac {
	async void run_in_thread_keeps_main_loop () throws Error {
		int ticks = 0;
		uint source_id = Timeout.add (10, () => {
			ticks++;
			return Source.CONTINUE;
		});
		bool result = yield run_in_thread ("test", MainContext.default (), () => {
			Thread.usleep (300000);
			return true;
		});
		Source.remove (source_id);
		assert (result);
		// the main loop ran while the thread worked
		assert (ticks > 10);
	}

	void test_run_in_thread () {
		run_async_test ((cb) => run_in_thread_keeps_main_loop.begin (cb), (res) => run_in_thread_keeps_main_loop.end (res));
	}

	async void run_exitable_results () throws Error {
		// as cb_download does when a download is cancelled
		bool exited = yield run_in_thread ("test", MainContext.default (), () => {
			return run_exitable ("inner", () => {
				Thread.exit ((void*) (-1));
				return true;
			});
		});
		assert (!exited);
		bool finished = yield run_in_thread ("test", MainContext.default (), () => {
			return run_exitable ("inner", () => {
				return true;
			});
		});
		assert (finished);
		bool failed = yield run_in_thread ("test", MainContext.default (), () => {
			return run_exitable ("inner", () => {
				return false;
			});
		});
		assert (!failed);
	}

	void test_run_exitable () {
		run_async_test ((cb) => run_exitable_results.begin (cb), (res) => run_exitable_results.end (res));
	}

	void test_request_round_trip () {
		var request = new TransactionRequest ();
		request.sysupgrade = true;
		request.enable_downgrade = true;
		request.simple_install = true;
		request.keep_built_pkgs = true;
		request.trans_flags = 42;
		request.to_install = {"a", "b"};
		request.to_remove = {"c"};
		request.to_load_local = {"/tmp/d.pkg.tar"};
		request.to_load_remote = {"https://e"};
		request.to_install_as_dep = {"f"};
		request.ignorepkgs = {"g"};
		request.overwrite_files = {"/h"};
		// through D-Bus as a{sv}
		var builder = new VariantBuilder (new VariantType ("a{sv}"));
		request.to_dict ().foreach ((key, val) => {
			builder.add ("{sv}", key, val);
		});
		Variant variant = builder.end ();
		assert (variant.get_type_string () == "a{sv}");
		var dict = new HashTable<string, Variant> (str_hash, str_equal);
		var iter = variant.iterator ();
		string key;
		Variant val;
		while (iter.next ("{sv}", out key, out val)) {
			dict.insert (key, val);
		}
		var copy = new TransactionRequest.from_dict (dict);
		assert (copy.sysupgrade && copy.enable_downgrade && copy.simple_install && copy.keep_built_pkgs);
		assert (copy.trans_flags == 42);
		assert (string.joinv (",", copy.to_install) == "a,b");
		assert (string.joinv (",", copy.to_remove) == "c");
		assert (string.joinv (",", copy.to_load_local) == "/tmp/d.pkg.tar");
		assert (string.joinv (",", copy.to_load_remote) == "https://e");
		assert (string.joinv (",", copy.to_install_as_dep) == "f");
		assert (string.joinv (",", copy.ignorepkgs) == "g");
		assert (string.joinv (",", copy.overwrite_files) == "/h");
	}

	void test_request_defaults () {
		var request = new TransactionRequest.from_dict (new HashTable<string, Variant> (str_hash, str_equal));
		assert (!request.sysupgrade && !request.enable_downgrade && !request.simple_install && !request.keep_built_pkgs);
		assert (request.trans_flags == 0);
		assert (request.to_install.length == 0);
		assert (request.overwrite_files.length == 0);
	}

	// a client can send anything: wrong types and unknown keys are ignored
	void test_request_invalid_values () {
		var dict = new HashTable<string, Variant> (str_hash, str_equal);
		dict.insert ("sysupgrade", new Variant.string ("true"));
		dict.insert ("trans_flags", new Variant.uint64 (42));
		dict.insert ("to_install", new Variant.string ("a"));
		dict.insert ("to_remove", new Variant.strv ({"b"}));
		dict.insert ("unknown", new Variant.boolean (true));
		var request = new TransactionRequest.from_dict (dict);
		assert (!request.sysupgrade);
		assert (request.trans_flags == 0);
		assert (request.to_install.length == 0);
		assert (string.joinv (",", request.to_remove) == "b");
	}

	void test_package_needs_reboot () {
		assert (package_needs_reboot ("linux"));
		assert (package_needs_reboot ("linux612-nvidia"));
		assert (package_needs_reboot ("intel-ucode"));
		assert (!package_needs_reboot ("linux-headers"));
		assert (!package_needs_reboot ("firefox"));
	}

	void test_update_details () {
		string source;
		string name;
		string? installed_version;
		string version;
		uint64 download_size;
		assert (parse_update_details ("repo\tlinux\t6.12-1\t6.12-2\t123456789012", out source, out name, out installed_version, out version, out download_size));
		assert (source == "repo" && name == "linux" && installed_version == "6.12-1" && version == "6.12-2");
		assert (download_size == 123456789012);
		// a replacer has no installed version
		assert (parse_update_details ("repo\tnewpkg\t\t1.0-1\t0", out source, out name, out installed_version, out version, out download_size));
		assert (installed_version == null);
		assert (!parse_update_details ("linux  6.12-1 -> 6.12-2", out source, out name, out installed_version, out version, out download_size));
	}

	void test_parse_official_repos () {
		var defaults = parse_official_repos (null);
		assert ("core" in defaults);
		assert ("extra" in defaults);
		assert ("multilib" in defaults);
		assert (!("community" in defaults));
		var repos = parse_official_repos (" myrepo  other ");
		assert (repos.length == 2);
		assert ("myrepo" in repos);
		assert ("other" in repos);
	}

	void test_set_to_strv () {
		var set = new GenericSet<string?> (str_hash, str_equal);
		assert (set_to_strv (set).length == 0);
		set.add ("a");
		set.add ("b");
		string[] names = set_to_strv (set);
		assert (names.length == 2);
		assert ("a" in names && "b" in names);
	}
}

int main (string[] args) {
	Pamac.init_tests (ref args);
	Test.add_func ("/utils/run_in_thread", Pamac.test_run_in_thread);
	Test.add_func ("/utils/run_exitable", Pamac.test_run_exitable);
	Test.add_func ("/transaction_request/round_trip", Pamac.test_request_round_trip);
	Test.add_func ("/transaction_request/defaults", Pamac.test_request_defaults);
	Test.add_func ("/transaction_request/invalid_values", Pamac.test_request_invalid_values);
	Test.add_func ("/transaction_request/set_to_strv", Pamac.test_set_to_strv);
	Test.add_func ("/utils/parse_official_repos", Pamac.test_parse_official_repos);
	Test.add_func ("/utils/package_needs_reboot", Pamac.test_package_needs_reboot);
	Test.add_func ("/utils/update_details", Pamac.test_update_details);
	return Test.run ();
}
