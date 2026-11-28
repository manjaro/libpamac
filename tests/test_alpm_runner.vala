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

// AlpmRunner and AlpmUtils on a pacman installation in a temporary directory,
// without root: the root, databases and cache of the test belong to the user.
// The repository is served slowly over HTTP so the downloads can be cancelled.
// The tests run in order, each one starts from the state left by the previous ones
namespace Pamac {
	AlpmTestEnv env;
	AlpmRunner runner;
	RecordingSink sink_a;
	RecordingSink sink_b;
	// two clients, as two processes using the daemon
	AlpmClient client_a;
	AlpmClient client_b;
	string big_package_url;

	TransactionRequest install_request (string[] names) {
		var request = new TransactionRequest ();
		request.to_install = names;
		return request;
	}

	async void refresh_and_install () throws Error {
		assert_operation (yield runner.trans_refresh (client_a, false, false), sink_a, "refresh");
		assert (sink_a.has ("action", "Synchronizing package databases"));
		assert_operation (yield runner.trans_run (client_a, install_request ({"testsmall", "testbig"})), sink_a, "install");
		assert (env.root_file_exists ("opt/test/testsmall.bin"));
		assert (env.root_file_exists ("opt/test/testbig.bin"));
	}

	void test_refresh_and_install () {
		run_async_test ((cb) => refresh_and_install.begin (cb), (res) => refresh_and_install.end (res));
	}

	async void set_pkgreason () throws Error {
		assert (yield runner.set_pkgreason (client_a, "testsmall", Alpm.Package.Reason.DEPEND));
		var handle = env.get_handle ();
		assert (handle.localdb.get_pkg ("testsmall").reason == Alpm.Package.Reason.DEPEND);
		assert (handle.localdb.get_pkg ("testbig").reason == Alpm.Package.Reason.EXPLICIT);
	}

	void test_set_pkgreason () {
		run_async_test ((cb) => set_pkgreason.begin (cb), (res) => set_pkgreason.end (res));
	}

	// the summary gives the reason and the old size of each package, and the totals
	void test_transaction_summary () {
		var alpm_utils = env.create_alpm_utils ();
		var to_install = new GenericSet<string?> (str_hash, str_equal);
		to_install.add ("testapp");
		var to_remove = new GenericSet<string?> (str_hash, str_equal);
		to_remove.add ("testsmall");
		var empty = new GenericSet<string?> (str_hash, str_equal);
		var summary = new TransactionSummary ();
		GenericArray<string> unresolvables;
		assert (alpm_utils.trans_check_prepare (new NullSink (), new Cancellable (), false, false, false, 0,
												to_install, to_remove, empty, empty, empty, empty, empty,
												ref summary, out unresolvables));
		assert (summary.to_install.length == 2);
		assert (summary.to_remove.length == 1);
		foreach (unowned Package pkg in summary.to_install) {
			assert (pkg.source == PackageSource.REPO);
			SummaryItem? item = summary.get_item (pkg);
			assert (item != null);
			assert (item.old_installed_size == 0);
			if (pkg.name == "testapp") {
				assert (item.reason == SummaryReason.REQUESTED);
				assert (item.related == null);
			} else {
				assert (pkg.name == "testother");
				assert (item.reason == SummaryReason.DEPENDENCY);
				assert (item.related == "testapp");
			}
		}
		SummaryItem? removed = summary.get_item (summary.to_remove[0]);
		assert (removed.reason == SummaryReason.REQUESTED);
		assert (removed.old_installed_size == 4 * 1024);
		// two packages of 4 KiB installed, one of 4 KiB removed
		assert (summary.installed_size_delta == 4 * 1024);
		// not in the cache
		assert (summary.download_size > 0);
		assert (!summary.requires_reboot);
	}

	void test_package_needs_reboot () {
		assert (AlpmJob.pkg_needs_reboot ("linux"));
		assert (AlpmJob.pkg_needs_reboot ("linux612-nvidia"));
		assert (AlpmJob.pkg_needs_reboot ("intel-ucode"));
		assert (!AlpmJob.pkg_needs_reboot ("linux-headers"));
		assert (!AlpmJob.pkg_needs_reboot ("testapp"));
	}

	// only regular files directly in a cache dir are removed
	async void clean_cache () throws Error {
		string in_cache = Path.build_filename (env.cache_dir, "old-1.0-1-any.pkg.tar");
		string outside = Path.build_filename (env.path, "outside-1.0-1-any.pkg.tar");
		string dir_in_cache = Path.build_filename (env.cache_dir, "dir.pkg.tar");
		FileUtils.set_contents (in_cache, "");
		FileUtils.set_contents (outside, "");
		DirUtils.create (dir_in_cache, 0755);
		bool success = yield runner.clean_cache (client_a, {in_cache, outside, dir_in_cache, "relative.pkg.tar"});
		assert (!success);
		assert (!FileUtils.test (in_cache, FileTest.EXISTS));
		assert (FileUtils.test (outside, FileTest.EXISTS));
		assert (FileUtils.test (dir_in_cache, FileTest.IS_DIR));
		DirUtils.remove (dir_in_cache);
	}

	void test_clean_cache () {
		run_async_test ((cb) => clean_cache.begin (cb), (res) => clean_cache.end (res));
	}

	// a build directory is only emptied for its owner
	async void clean_build_files () throws Error {
		string build_dir = Path.build_filename (env.path, "aur");
		string build_file = Path.build_filename (build_dir, "pkg", "PKGBUILD");
		string aur_db = Path.build_filename (build_dir, "packages-meta-ext-v1.json.gz");
		DirUtils.create_with_parents (Path.get_dirname (build_file), 0755);
		FileUtils.set_contents (build_file, "");
		FileUtils.set_contents (aur_db, "");
		int64 uid = Posix.geteuid ();
		assert (!(yield runner.clean_build_files (client_a, build_dir, uid + 1)));
		assert (FileUtils.test (build_file, FileTest.EXISTS));
		assert (!(yield runner.clean_build_files (client_a, "relative/dir", uid)));
		string link = Path.build_filename (env.path, "aur-link");
		FileUtils.symlink (build_dir, link);
		assert (!(yield runner.clean_build_files (client_a, link, uid)));
		assert (FileUtils.test (build_file, FileTest.EXISTS));
		assert (yield runner.clean_build_files (client_a, build_dir, uid));
		assert (!FileUtils.test (build_file, FileTest.EXISTS));
		// the AUR database is kept
		assert (FileUtils.test (aur_db, FileTest.EXISTS));
	}

	void test_clean_build_files () {
		run_async_test ((cb) => clean_build_files.begin (cb), (res) => clean_build_files.end (res));
	}

	// cancelling a download exits its thread in cb_download: the lock must be released
	async void cancel_download () throws Error {
		// testbig 2.0 is big enough to be cancelled while downloaded
		env.repo_add ({Path.build_filename (env.repo_dir, "testbig-2.0-1-any.pkg.tar")});
		assert (yield runner.trans_refresh (client_a, true, false));
		bool done = false;
		string[] paths = {"not returned"};
		runner.download_pkgs.begin (client_a, {big_package_url}, (obj, res) => {
			try {
				paths = runner.download_pkgs.end (res);
			} catch (Error e) {
				error (e.message);
			}
			done = true;
		});
		yield wait_ms (1500);
		assert (!done);
		uint cancelled_before = sink_a.count ("action", "Transaction cancelled");
		int64 start = get_monotonic_time ();
		client_a.cancellable.cancel ();
		assert (yield wait_for (() => done, 5000));
		Test.message ("download cancelled in %.2f s", seconds_since (start));
		assert (seconds_since (start) < 2);
		assert (paths.length == 0);
		assert (sink_a.count ("action", "Transaction cancelled") > cancelled_before);
		// the next operation gets the lock at once
		uint waits = sink_b.count ("start_waiting");
		assert (yield runner.trans_refresh (client_b, false, false));
		assert (sink_b.count ("start_waiting") == waits);
		env.remove_partial_downloads ();
	}

	void test_cancel_download () {
		run_async_test ((cb) => cancel_download.begin (cb), (res) => cancel_download.end (res));
	}

	// a transaction interrupts the download of updates instead of waiting for it
	async void transaction_cancels_download_of_updates () throws Error {
		bool done = false;
		bool downloaded = true;
		runner.download_updates.begin (client_a, (obj, res) => {
			try {
				downloaded = runner.download_updates.end (res);
			} catch (Error e) {
				error (e.message);
			}
			done = true;
		});
		yield wait_ms (1500);
		assert (!done);
		assert (runner.alpm_utils.is_download_updates_requested ());
		// one download of updates at a time
		assert (!(yield runner.download_updates (client_b)));
		int64 start = get_monotonic_time ();
		assert_operation (yield runner.trans_run (client_b, install_request ({"testother"})), sink_b, "install during the download of updates");
		Test.message ("transaction run in %.2f s", seconds_since (start));
		assert (seconds_since (start) < 4);
		assert (yield wait_for (() => done, 5000));
		assert (!downloaded);
		assert (!runner.alpm_utils.is_download_updates_requested ());
		assert (env.root_file_exists ("opt/test/testother.bin"));
		env.remove_partial_downloads ();
	}

	void test_transaction_cancels_download_of_updates () {
		run_async_test ((cb) => transaction_cancels_download_of_updates.begin (cb), (res) => transaction_cancels_download_of_updates.end (res));
	}

	// cancelling an operation waiting for the lock does not touch the one holding it
	async void cancel_wait_for_lock () throws Error {
		bool download_done = false;
		runner.download_pkgs.begin (client_a, {big_package_url}, (obj, res) => {
			try {
				runner.download_pkgs.end (res);
			} catch (Error e) {
				error (e.message);
			}
			download_done = true;
		});
		yield wait_ms (500);
		bool refresh_done = false;
		bool refreshed = true;
		uint waits = sink_b.count ("start_waiting");
		runner.trans_refresh.begin (client_b, false, false, (obj, res) => {
			try {
				refreshed = runner.trans_refresh.end (res);
			} catch (Error e) {
				error (e.message);
			}
			refresh_done = true;
		});
		yield wait_ms (1000);
		assert (!refresh_done);
		assert (sink_b.count ("start_waiting") > waits);
		int64 start = get_monotonic_time ();
		client_b.cancellable.cancel ();
		assert (yield wait_for (() => refresh_done, 2000));
		Test.message ("wait cancelled in %.3f s", seconds_since (start));
		assert (seconds_since (start) < 0.5);
		assert (!refreshed);
		assert (!download_done);
		client_a.cancellable.cancel ();
		assert (yield wait_for (() => download_done, 5000));
		env.remove_partial_downloads ();
	}

	void test_cancel_wait_for_lock () {
		run_async_test ((cb) => cancel_wait_for_lock.begin (cb), (res) => cancel_wait_for_lock.end (res));
	}

	// the lock file of another package manager is waited for
	async void external_lock_file () throws Error {
		var lockfile = File.new_for_path (env.lockfile_path);
		lockfile.create (FileCreateFlags.NONE).close ();
		// let the file monitor see it
		yield wait_ms (300);
		bool done = false;
		bool refreshed = false;
		uint waits = sink_b.count ("start_waiting");
		runner.trans_refresh.begin (client_b, false, false, (obj, res) => {
			try {
				refreshed = runner.trans_refresh.end (res);
			} catch (Error e) {
				error (e.message);
			}
			done = true;
		});
		yield wait_ms (1500);
		assert (!done);
		assert (sink_b.count ("start_waiting") > waits);
		assert (sink_b.has ("action", "Waiting for another package manager to quit"));
		int64 start = get_monotonic_time ();
		lockfile.delete ();
		assert (yield wait_for (() => done, 3000));
		Test.message ("lock acquired %.3f s after the removal of the lock file", seconds_since (start));
		assert (seconds_since (start) < 1.5);
		assert (refreshed);
	}

	void test_external_lock_file () {
		run_async_test ((cb) => external_lock_file.begin (cb), (res) => external_lock_file.end (res));
	}

	void setup_env () throws Error {
		env = new AlpmTestEnv ();
		env.add_package ("testsmall", "1.0", 4);
		env.add_package ("testbig", "1.0", 4);
		env.add_package ("testother", "1.0", 4);
		env.add_package ("testapp", "1.0", 4, null, {"testother"});
		// added to the repository by test_cancel_download
		env.add_package ("testbig", "2.0", 40960);
		env.repo_add ({Path.build_filename (env.repo_dir, "testsmall-1.0-1-any.pkg.tar"),
						Path.build_filename (env.repo_dir, "testbig-1.0-1-any.pkg.tar"),
						Path.build_filename (env.repo_dir, "testother-1.0-1-any.pkg.tar"),
						Path.build_filename (env.repo_dir, "testapp-1.0-1-any.pkg.tar")});
		string script = Path.build_filename (Environment.get_variable ("PAMAC_TEST_SRCDIR") ?? ".", "slow_server.py");
		string server_url = env.start_slow_server (script);
		big_package_url = server_url + "/testbig-2.0-1-any.pkg.tar";
		env.write_pacman_conf (server_url);
		runner = new AlpmRunner (env.create_alpm_utils (), MainContext.default ());
		sink_a = new RecordingSink ("A");
		sink_b = new RecordingSink ("B");
		client_a = new AlpmClient (sink_a);
		client_b = new AlpmClient (sink_b);
	}
}

int main (string[] args) {
	Pamac.init_tests (ref args);
	string? missing = Pamac.AlpmTestEnv.find_missing_program ({"bsdtar", "repo-add", "python3"});
	if (missing != null) {
		print ("skipped: %s not found\n", missing);
		return Pamac.SKIP;
	}
	if (Posix.geteuid () == 0) {
		// the root mode is tested by test-alpm-runner-root
		print ("skipped: run as root\n");
		return Pamac.SKIP;
	}
	try {
		Pamac.setup_env ();
	} catch (Error e) {
		printerr ("failed to create the test environment: %s\n", e.message);
		return 1;
	}
	Test.add_func ("/alpm_runner/refresh_and_install", Pamac.test_refresh_and_install);
	Test.add_func ("/alpm_runner/set_pkgreason", Pamac.test_set_pkgreason);
	Test.add_func ("/alpm_runner/transaction_summary", Pamac.test_transaction_summary);
	Test.add_func ("/alpm_runner/package_needs_reboot", Pamac.test_package_needs_reboot);
	Test.add_func ("/alpm_runner/clean_cache", Pamac.test_clean_cache);
	Test.add_func ("/alpm_runner/clean_build_files", Pamac.test_clean_build_files);
	Test.add_func ("/alpm_runner/cancel_download", Pamac.test_cancel_download);
	Test.add_func ("/alpm_runner/transaction_cancels_download_of_updates", Pamac.test_transaction_cancels_download_of_updates);
	Test.add_func ("/alpm_runner/cancel_wait_for_lock", Pamac.test_cancel_wait_for_lock);
	Test.add_func ("/alpm_runner/external_lock_file", Pamac.test_external_lock_file);
	int status = Test.run ();
	Pamac.env.cleanup ();
	return status;
}
