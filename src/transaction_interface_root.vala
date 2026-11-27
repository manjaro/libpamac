/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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

namespace Pamac {
	internal class TransactionInterfaceRoot: Object, TransactionInterface {
		unowned AlpmUtils alpm_utils;
		TransactionSink sink;
		Cancellable trans_cancellable;
		MainContext context;

		public TransactionInterfaceRoot (AlpmUtils alpm_utils, MainContext context, TransactionSink sink) {
			this.alpm_utils = alpm_utils;
			this.context = context;
			this.sink = sink;
			trans_cancellable = new Cancellable ();
		}

		public async bool get_authorization () {
			// we are root
			return true;
		}

		public void remove_authorization () {
			// we are root
		}

		public async void generate_mirrors_list (string country) {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "--country=" + country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					sink.emit_script_output (line);
				}
			} catch (Error e) {
				warning (e.message);
			}
			alpm_utils.alpm_config.reload ();
		}

		public async bool clean_cache (GenericArray<string> filenames) throws Error {
			string[] names = filenames.data;
			return yield run_in_thread ("clean_cache", context, () => {
				return alpm_utils.clean_cache (names);
			});
		}

		public async bool clean_build_files (string aur_build_dir) throws Error {
			return yield run_in_thread ("clean_build_files", context, () => {
				return alpm_utils.clean_build_files (aur_build_dir, Posix.geteuid ());
			});
		}

		public async bool set_pkgreason (string pkgname, uint reason) {
			return alpm_utils.set_pkgreason (sink, pkgname, reason);
		}

		public async bool download_updates () throws Error {
			if (!alpm_utils.request_download_updates ()) {
				// already downloading updates
				return false;
			}
			try {
				return yield run_in_thread ("download_updates", context, () => {
					return run_exitable ("download_updates", () => {
						return alpm_utils.download_updates (sink);
					});
				});
			} finally {
				// the download thread is exited when cancelled: always end it here
				alpm_utils.end_download_updates ();
			}
		}

		public async string[] download_pkgs (GenericArray<string> urls) throws Error {
			string[] urls_copy = urls.data;
			var dload_paths = new GenericArray<string> ();
			yield run_in_thread ("download_pkgs", context, () => {
				return run_exitable ("download_pkgs", () => {
					return alpm_utils.download_pkgs (sink, urls_copy, ref dload_paths);
				});
			});
			return dload_paths.data;
		}

		async void wait_ms (uint ms) {
			var timeout = new TimeoutSource (ms);
			timeout.set_callback (wait_ms.callback);
			timeout.attach (context);
			yield;
		}

		// cancel the download of updates and wait for its end:
		// it holds the alpm lock until its thread is exited
		async void cancel_download_updates () {
			if (!alpm_utils.cancel_download_updates ()) {
				return;
			}
			while (alpm_utils.is_download_updates_requested ()) {
				yield wait_ms (100);
			}
		}

		// returns false if cancelled or after 5 min
		async bool wait_for_lock () {
			trans_cancellable.reset ();
			if (!alpm_utils.lockfile.query_exists ()) {
				return true;
			}
			sink.start_waiting ();
			sink.emit_action (dgettext (null, "Waiting for another package manager to quit") + "...");
			bool success = false;
			int64 deadline = get_monotonic_time () + 5 * TimeSpan.MINUTE;
			while (!trans_cancellable.is_cancelled ()) {
				yield wait_ms (200);
				if (!alpm_utils.lockfile.query_exists ()) {
					success = true;
					break;
				}
				if (get_monotonic_time () >= deadline) {
					sink.emit_action ("%s: %s.".printf (dgettext (null, "Transaction cancelled"), dgettext (null, "Timeout expired")));
					break;
				}
			}
			sink.stop_waiting ();
			return success;
		}

		// run func in a thread when the lock is free,
		// returns false if cancelled, the download is cancelled or func fails
		async bool run_locked (string name, owned BoolFunc func) throws Error {
			yield cancel_download_updates ();
			if (!(yield wait_for_lock ())) {
				return false;
			}
			return yield run_in_thread (name, context, () => {
				return run_exitable (name, func);
			});
		}

		public async bool trans_refresh (bool force) throws Error {
			return yield run_locked ("trans_refresh", () => {
				return alpm_utils.trans_refresh (sink, force);
			});
		}

		public async bool trans_refresh_files (bool force) throws Error {
			return yield run_locked ("trans_refresh_files", () => {
				return alpm_utils.trans_refresh_files (sink, force);
			});
		}

		public async bool trans_refresh_aur (bool force) throws Error {
			return yield run_locked ("trans_refresh_aur", () => {
				return alpm_utils.trans_refresh_aur (sink, force);
			});
		}

		public async bool trans_run (TransactionRequest request) throws Error {
			return yield run_locked ("trans_run", () => {
				return alpm_utils.trans_run (sink, request);
			});
		}

		public async bool snap_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove) {
			// not implemented
			return false;
		}

		public async bool snap_switch_channel (string snap_name, string channel) {
			// not implemented
			return false;
		}

		public async bool flatpak_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove, GenericArray<string> to_upgrade) {
			// not implemented
			return false;
		}

		public void trans_cancel () {
			trans_cancellable.cancel ();
			alpm_utils.trans_cancel (sink);
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
