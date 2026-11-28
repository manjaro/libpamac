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

namespace Pamac {
	// who runs the operations: where their progress goes and how to cancel them.
	// Each operation of the runner resets the cancellable first, cancelling it
	// stops the wait for the lock and the alpm operation.
	// Not given as a Cancellable parameter to the async methods: Vala would give it
	// to their GTask, they would throw IOError.CANCELLED instead of returning false
	internal class AlpmClient : Object {
		public TransactionSink sink { get; private set; }
		public Cancellable cancellable { get; private set; }

		public AlpmClient (TransactionSink sink) {
			this.sink = sink;
			cancellable = new Cancellable ();
		}
	}

	// runs the alpm operations of the daemon and of the root mode:
	// in worker threads, one at a time with the lock held,
	// reporting their progress to a sink.
	// The async methods are called from context and resume in it
	internal class AlpmRunner : Object {
		public AlpmUtils alpm_utils { get; private set; }
		MainContext context;
		FileMonitor? lockfile_monitor;
		// held by the running operation, or while another package manager
		// holds the lock file (see hold_extern_lock).
		// A GMutex must be unlocked by the thread which locked it
		Mutex lockfile_mutex;
		// signaled when the lock is released or an operation waiting for it is cancelled
		Mutex lock_wait_mutex;
		Cond lock_wait_cond;
		// signaled when the external lock file is removed
		Mutex lockfile_cond_mutex;
		Cond lockfile_cond;

		public AlpmRunner (AlpmUtils alpm_utils, MainContext context) {
			this.alpm_utils = alpm_utils;
			this.context = context;
			lockfile_mutex = Mutex ();
			lock_wait_mutex = Mutex ();
			lock_wait_cond = Cond ();
			lockfile_cond_mutex = Mutex ();
			lockfile_cond = Cond ();
			if (alpm_utils.lockfile == null) {
				return;
			}
			if (alpm_utils.lockfile.query_exists ()) {
				start_extern_lock_thread ();
			}
			try {
				lockfile_monitor = alpm_utils.lockfile.monitor (FileMonitorFlags.NONE, null);
				lockfile_monitor.changed.connect (on_lockfile_changed);
			} catch (Error e) {
				warning (e.message);
			}
		}

		void start_extern_lock_thread () {
			try {
				new Thread<int>.try ("extern_lock", hold_extern_lock);
			} catch (Error e) {
				warning (e.message);
			}
		}

		// hold the lock while another package manager holds the lock file:
		// this thread locks and unlocks lockfile_mutex and only waits for the lock file removal
		int hold_extern_lock () {
			if (!lockfile_mutex.trylock ()) {
				// an operation holds the lock: the lock file is its own
				return 0;
			}
			lockfile_cond_mutex.lock ();
			while (alpm_utils.lockfile.query_exists ()) {
				// woken up by on_lockfile_changed when the lock file is deleted,
				// check again every second in case the event is missed
				lockfile_cond.wait_until (lockfile_cond_mutex, get_monotonic_time () + TimeSpan.SECOND);
			}
			lockfile_cond_mutex.unlock ();
			release_lock ();
			return 0;
		}

		void on_lockfile_changed (File src, File? dest, FileMonitorEvent event_type) {
			if (event_type == FileMonitorEvent.CREATED) {
				start_extern_lock_thread ();
			} else if (event_type == FileMonitorEvent.DELETED) {
				lockfile_cond_mutex.lock ();
				lockfile_cond.broadcast ();
				lockfile_cond_mutex.unlock ();
			}
		}

		void wake_lock_waiters () {
			lock_wait_mutex.lock ();
			lock_wait_cond.broadcast ();
			lock_wait_mutex.unlock ();
		}

		// to call from the thread which got the lock
		void release_lock () {
			lockfile_mutex.unlock ();
			wake_lock_waiters ();
		}

		// to call from a worker thread:
		// returns false if cancelled or not acquired after 5 min
		bool wait_for_lock (TransactionSink sink, Cancellable cancellable, bool quiet) {
			if (lockfile_mutex.trylock ()) {
				return true;
			}
			sink.start_waiting ();
			if (!quiet) {
				sink.emit_action (_("Waiting for another package manager to quit") + "...");
			}
			// called at once if already cancelled
			ulong handler_id = cancellable.connect (wake_lock_waiters);
			bool success = false;
			int64 deadline = get_monotonic_time () + 5 * TimeSpan.MINUTE;
			lock_wait_mutex.lock ();
			while (!cancellable.is_cancelled ()) {
				if (lockfile_mutex.trylock ()) {
					success = true;
					break;
				}
				int64 now = get_monotonic_time ();
				if (now >= deadline) {
					if (!quiet) {
						sink.emit_action ("%s: %s.".printf (_("Transaction cancelled"), _("Timeout expired")));
					}
					break;
				}
				// woken up when the lock is released or the operation is cancelled,
				// check again every second anyway
				int64 end_time = now + TimeSpan.SECOND;
				lock_wait_cond.wait_until (lock_wait_mutex, end_time < deadline ? end_time : deadline);
			}
			lock_wait_mutex.unlock ();
			// not while holding lock_wait_mutex: it waits for a running wake_lock_waiters
			cancellable.disconnect (handler_id);
			sink.stop_waiting ();
			return success;
		}

		// run func in a worker thread, the coroutine is resumed in context
		async bool run_thread (string name, owned BoolFunc func) throws Error {
			return yield run_in_thread (name, context, (owned) func);
		}

		// to call from a worker thread: run func with the lock held, in a nested thread
		// which is exited when a download is cancelled (see cb_download).
		// Returns false if the lock is not acquired, the thread is exited or func fails
		bool run_locked (TransactionSink sink, Cancellable cancellable, bool quiet, BoolFunc func) {
			if (!wait_for_lock (sink, cancellable, quiet)) {
				return false;
			}
			bool success = run_exitable ("locked_work", func);
			release_lock ();
			return success;
		}

		async bool run_locked_thread (string name, AlpmClient client, bool quiet, owned BoolFunc func) throws Error {
			client.cancellable.reset ();
			return yield run_thread (name, () => {
				return run_locked (client.sink, client.cancellable, quiet, func);
			});
		}

		public async void write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws Error {
			yield run_thread ("write_alpm_config", () => {
				lockfile_mutex.lock ();
				alpm_utils.alpm_config.write (new_alpm_conf);
				alpm_utils.alpm_config.reload ();
				release_lock ();
				return true;
			});
		}

		public async void generate_mirrors_list (AlpmClient client, string country) throws Error {
			// the country must not be read as an option by pacman-mirrors
			if (country.length == 0 || country.has_prefix ("-")) {
				var details = new GenericArray<string> (1);
				details.add ("invalid country: %s".printf (country));
				client.sink.emit_error ("Daemon Error", details);
				return;
			}
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "--no-color", "--country=" + country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					client.sink.emit_script_output (line);
				}
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add (e.message);
				client.sink.emit_error ("Daemon Error", details);
			}
			yield run_thread ("reload_alpm_config", () => {
				lockfile_mutex.lock ();
				alpm_utils.alpm_config.reload ();
				release_lock ();
				return true;
			});
		}

		// the cleanings run with the lock held: they must not remove the files
		// used by a running transaction
		public async bool clean_cache (AlpmClient client, string[] filenames) throws Error {
			string[] names = filenames;
			return yield run_locked_thread ("clean_cache", client, true, () => {
				return alpm_utils.clean_cache (names);
			});
		}

		// caller_uid: see AlpmUtils.clean_build_files
		public async bool clean_build_files (AlpmClient client, string aur_build_dir, int64 caller_uid) throws Error {
			return yield run_locked_thread ("clean_build_files", client, true, () => {
				return alpm_utils.clean_build_files (aur_build_dir, caller_uid);
			});
		}

		public async bool set_pkgreason (AlpmClient client, string pkgname, uint reason) throws Error {
			return yield run_thread ("set_pkgreason", () => {
				lockfile_mutex.lock ();
				bool success = alpm_utils.set_pkgreason (client.sink, pkgname, reason);
				release_lock ();
				return success;
			});
		}

		// returns false if a download of updates is already requested
		public async bool download_updates (AlpmClient client) throws Error {
			// its own cancellable: cancel_download_updates must not cancel
			// the other operations of the same client
			var download_cancellable = new Cancellable ();
			if (!alpm_utils.request_download_updates (download_cancellable)) {
				return false;
			}
			client.cancellable.reset ();
			ulong handler_id = client.cancellable.connect (() => {
				download_cancellable.cancel ();
			});
			try {
				return yield run_thread ("download_updates", () => {
					return run_locked (client.sink, download_cancellable, true, () => {
						return alpm_utils.download_updates (client.sink, download_cancellable);
					});
				});
			} finally {
				client.cancellable.disconnect (handler_id);
				alpm_utils.end_download_updates ();
			}
		}

		public async string[] download_pkgs (AlpmClient client, string[] urls) throws Error {
			string[] urls_copy = urls;
			var dload_paths = new GenericArray<string> ();
			yield run_locked_thread ("download_pkgs", client, true, () => {
				return alpm_utils.download_pkgs (client.sink, client.cancellable, urls_copy, ref dload_paths);
			});
			return dload_paths.data;
		}

		// cancel_download: interrupt the download of updates instead of waiting for its end.
		// Returns false only if cancelled
		public async bool trans_refresh (AlpmClient client, bool force, bool cancel_download) throws Error {
			if (cancel_download) {
				alpm_utils.cancel_download_updates ();
			}
			return yield run_locked_thread ("trans_refresh", client, false, () => {
				return alpm_utils.trans_refresh (client.sink, client.cancellable, force);
			});
		}

		public async bool trans_refresh_files (AlpmClient client, bool force, bool cancel_download) throws Error {
			if (cancel_download) {
				alpm_utils.cancel_download_updates ();
			}
			return yield run_locked_thread ("trans_refresh_files", client, false, () => {
				return alpm_utils.trans_refresh_files (client.sink, client.cancellable, force);
			});
		}

		public async bool trans_refresh_aur (AlpmClient client, bool force, bool cancel_download) throws Error {
			if (cancel_download) {
				alpm_utils.cancel_download_updates ();
			}
			return yield run_locked_thread ("trans_refresh_aur", client, false, () => {
				return alpm_utils.trans_refresh_aur (client.sink, client.cancellable, force);
			});
		}

		public async bool trans_run (AlpmClient client, TransactionRequest request) throws Error {
			// also if it waits for the lock, else the transaction would wait for it
			alpm_utils.cancel_download_updates ();
			return yield run_locked_thread ("trans_run", client, false, () => {
				return alpm_utils.trans_run (client.sink, client.cancellable, request);
			});
		}
	}
}
