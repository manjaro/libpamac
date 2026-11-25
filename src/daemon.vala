/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2023 Guillaume Benoit <guillaume@manjaro.org>
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

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.Daemon system_daemon;
MainLoop loop;

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.daemon")]
	public class Daemon: Object {
		Config config;
		AlpmUtils alpm_utils;
		int running_threads;
		FileMonitor lockfile_monitor;
		// signaled when the external lock file is removed
		Cond lockfile_cond;
		Mutex lockfile_cond_mutex;
		Mutex lockfile_mutex;
		Cond answer_cond;
		Mutex answer_mutex;
		Mutex authorization_mutex;
		GenericSet<string> authorized_senders;
		HashTable<string, HashTable<string, string>> pending_environments;
		// uid of the user who started the current download of updates
		int64 download_updates_uid;
		HashTable<string, Cancellable> cancellables_table;
		SnapPlugin snap_plugin;
		FlatpakPlugin flatpak_plugin;

		public signal void emit_action (string sender, string action);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_download_progress (string sender, string action, string status, double progress);
		public signal void emit_hook_progress (string sender, string action, string details, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_warning (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);
		public signal void important_details_outpout (string sender, bool must_show);
		public signal void start_downloading (string sender);
		public signal void stop_downloading (string sender);
		public signal void set_pkgreason_finished (string sender, bool success);
		public signal void start_waiting (string sender);
		public signal void stop_waiting (string sender);
		public signal void trans_refresh_finished (string sender, bool success);
		public signal void trans_refresh_files_finished (string sender, bool success);
		public signal void trans_refresh_aur_finished (string sender, bool success);
		public signal void trans_run_finished (string sender, bool success);
		public signal void download_updates_finished (string sender, bool success);
		public signal void download_pkgs_finished (string sender, string[] dload_paths);
		public signal void get_authorization_finished (string sender, bool authorized);
		public signal void write_alpm_config_finished (string sender);
		public signal void write_pamac_config_finished (string sender);
		public signal void generate_mirrors_list_data (string sender, string line);
		public signal void generate_mirrors_list_finished (string sender);
		public signal void clean_cache_finished (string sender, bool success);
		public signal void clean_build_files_finished (string sender, bool success);
		public signal void snap_trans_run_finished (string sender, bool success);
		public signal void snap_switch_channel_finished (string sender, bool success);
		public signal void flatpak_trans_run_finished (string sender, bool success);
		// broadcast to every client, unlike the signals above which are sent
		// only to the client they are meant for (see direct_signals_filter):
		// it carries no information about who ran the transaction, so other
		// processes like the gnome-shell extension can refresh their state
		public signal void transaction_finished ();

		public Daemon () {
			config = new Config ("/etc/pamac.conf");
			string user_agent = get_user_agent ();
			alpm_utils = new AlpmUtils (config);
			// set HTTP_USER_AGENT needed when downloading using libalpm
			Environment.set_variable ("HTTP_USER_AGENT", user_agent, true);
			lockfile_cond = Cond ();
			lockfile_cond_mutex = Mutex ();
			lockfile_mutex = Mutex ();
			if (alpm_utils.lockfile.query_exists ()) {
				try {
					new Thread<int>.try ("set_extern_lock", set_extern_lock);
				} catch (Error e) {
					warning (e.message);
				}
			}
			try {
				lockfile_monitor = alpm_utils.lockfile.monitor (FileMonitorFlags.NONE, null);
				lockfile_monitor.changed.connect (check_extern_lock);
			} catch (Error e) {
				warning (e.message);
			}
			running_threads = 0;
			answer_cond = Cond ();
			answer_mutex = Mutex ();
			authorization_mutex = Mutex ();
			authorized_senders = new GenericSet<string> (str_hash, str_equal);
			pending_environments = new HashTable<string, HashTable<string, string>> (str_hash, str_equal);
			download_updates_uid = -1;
			cancellables_table = new HashTable<string, Cancellable> (str_hash, str_equal);
			trans_run_finished.connect (() => {
				transaction_finished ();
			});
			snap_trans_run_finished.connect (() => {
				transaction_finished ();
			});
			flatpak_trans_run_finished.connect (() => {
				transaction_finished ();
			});
			// forget the clients which left the bus
			try {
				Bus.get_sync (BusType.SYSTEM).signal_subscribe ("org.freedesktop.DBus",
															"org.freedesktop.DBus",
															"NameOwnerChanged",
															"/org/freedesktop/DBus",
															null,
															DBusSignalFlags.NONE,
															on_name_owner_changed);
			} catch (Error e) {
				warning (e.message);
			}
			alpm_utils.emit_action.connect ((sender, action) => {
				emit_action (sender, action);
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				emit_action_progress (sender, action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				emit_hook_progress (sender, action, details, status, progress);
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				emit_download_progress (sender, action, status, progress);
			});
			alpm_utils.start_downloading.connect ((sender) => {
				start_downloading (sender);
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				stop_downloading (sender);
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				emit_script_output (sender, message);
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				emit_warning (sender, message);
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				string[] details_copy = details.data;
				emit_error (sender, message, details_copy);
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				important_details_outpout (sender, must_show);
			});
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
				snap_plugin.emit_action_progress.connect ((sender, action, status, progress) => {
					emit_action_progress (sender, action, status, progress);
				});
				snap_plugin.emit_download_progress.connect ((sender, action, status, progress) => {
					emit_download_progress (sender, action, status, progress);
				});
				snap_plugin.emit_script_output.connect ((sender, message) => {
					emit_script_output (sender, message);
				});
				snap_plugin.emit_error.connect ((sender, message,  details) => {
					emit_error (sender, message, details);
				});
				snap_plugin.start_downloading.connect ((sender) => {
					start_downloading (sender);
				});
				snap_plugin.stop_downloading.connect ((sender) => {
					stop_downloading (sender);
				});
			}
			if (config.support_flatpak) {
				flatpak_plugin = config.get_flatpak_plugin ();
				flatpak_plugin.emit_action_progress.connect ((sender, action, status, progress) => {
					emit_action_progress (sender, action, status, progress);
				});
				flatpak_plugin.emit_script_output.connect ((sender, message) => {
					emit_script_output (sender, message);
				});
				flatpak_plugin.emit_error.connect ((sender, message,  details) => {
					emit_error (sender, message, details);
				});
			}
		}

		public void set_environment_variables (HashTable<string,string> variables, BusName sender) throws Error {
			// do not touch the daemon environment for an unauthorized caller:
			// keep the variables until this sender is successfully authorized
			string[] keys = {"http_proxy",
							"https_proxy",
							"ftp_proxy",
							"socks_proxy",
							"no_proxy"};
			var accepted = new HashTable<string, string> (str_hash, str_equal);
			foreach (unowned string key in keys) {
				unowned string val;
				if (variables.lookup_extended (key, null, out val)) {
					accepted.insert (key, val);
				}
			}
			authorization_mutex.lock ();
			if (accepted.length == 0) {
				pending_environments.remove (sender);
			} else {
				pending_environments.insert (sender, accepted);
			}
			authorization_mutex.unlock ();
		}

		void apply_pending_environment (string sender) {
			authorization_mutex.lock ();
			HashTable<string, string>? variables = pending_environments.lookup (sender);
			pending_environments.remove (sender);
			authorization_mutex.unlock ();
			if (variables == null) {
				return;
			}
			var iter = HashTableIter<string, string> (variables);
			unowned string key;
			unowned string val;
			while (iter.next (out key, out val)) {
				// avoid useless setenv calls, setenv is not thread-safe
				if (Environment.get_variable (key) != val) {
					Environment.set_variable (key, val, true);
				}
			}
		}

		void on_name_owner_changed (DBusConnection connection, string? sender_name, string object_path, string interface_name, string signal_name, Variant parameters) {
			unowned string name;
			unowned string old_owner;
			unowned string new_owner;
			parameters.get ("(&s&s&s)", out name, out old_owner, out new_owner);
			// a unique name is never reused once it has vanished
			if (new_owner != "" || !GLib.DBus.is_unique_name (name)) {
				return;
			}
			authorization_mutex.lock ();
			authorized_senders.remove (name);
			pending_environments.remove (name);
			authorization_mutex.unlock ();
			// running operations keep their own reference on the cancellable
			cancellables_table.remove (name);
		}

		public string get_sender (BusName sender) throws Error {
			return sender;
		}

		public string get_lockfile () throws Error {
			return alpm_utils.lockfile.get_path ();
		}

		// unix user id of a bus name, -1 if unknown
		int64 get_sender_uid (string sender) {
			try {
				var connection = Bus.get_sync (BusType.SYSTEM);
				Variant reply = connection.call_sync ("org.freedesktop.DBus",
													"/org/freedesktop/DBus",
													"org.freedesktop.DBus",
													"GetConnectionUnixUser",
													new Variant ("(s)", sender),
													new VariantType ("(u)"),
													DBusCallFlags.NONE,
													-1);
				uint32 uid;
				reply.get ("(u)", out uid);
				return uid;
			} catch (Error e) {
				warning (e.message);
			}
			return -1;
		}

		// an unauthenticated refresh may only interrupt a download of updates
		// started by the same user, otherwise it waits for the lock
		bool may_cancel_download_updates (string sender) {
			if (!alpm_utils.downloading_updates) {
				return false;
			}
			int64 uid = get_sender_uid (sender);
			return uid != -1 && uid == download_updates_uid;
		}

		int set_extern_lock () {
			// hold lockfile_mutex while another package manager holds the lock file
			// a GMutex must be unlocked by the thread which locked it:
			// this thread does both and only waits for the lock file removal
			if (!lockfile_mutex.trylock ()) {
				return 0;
			}
			lockfile_cond_mutex.lock ();
			while (alpm_utils.lockfile.query_exists ()) {
				// woken up by check_extern_lock when the lock file is deleted,
				// check again every second in case the event is missed
				lockfile_cond.wait_until (lockfile_cond_mutex, get_monotonic_time () + TimeSpan.SECOND);
			}
			lockfile_cond_mutex.unlock ();
			lockfile_mutex.unlock ();
			return 0;
		}

		void check_extern_lock (File src, File? dest, FileMonitorEvent event_type) {
			if (event_type == FileMonitorEvent.CREATED) {
				try {
					new Thread<int>.try ("check_extern_lock", set_extern_lock);
				} catch (Error e) {
					warning (e.message);
				}
			} else if (event_type == FileMonitorEvent.DELETED) {
				lockfile_cond_mutex.lock ();
				lockfile_cond.broadcast ();
				lockfile_cond_mutex.unlock ();
			}
		}

		async bool check_authorization (BusName sender) {
			// a pending authorization counts as running work: quit must not
			// stop the daemon while waiting for polkit
			AtomicInt.inc (ref running_threads);
			bool authorized = false;
			try {
				Polkit.Authority authority = yield Polkit.Authority.get_async ();
				Polkit.Subject subject = new Polkit.SystemBusName (sender);
				var result = yield authority.check_authorization (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION);
				authorized = result.get_is_authorized ();
				if (authorized) {
					apply_pending_environment (sender);
				} else {
					emit_error (sender, _("Authentication failed"), {});
				}
			} catch (Error e) {
				emit_error (sender, _("Authentication failed"), {e.message});
			}
			// released after the caller callback has started its worker thread
			Idle.add (() => {
				AtomicInt.dec_and_test (ref running_threads);
				return false;
			});
			return authorized;
		}

		public void start_get_authorization (BusName sender) throws Error {
			authorization_mutex.lock ();
			bool fast_authorized = authorized_senders.contains (sender);
			authorization_mutex.unlock ();
			if (fast_authorized) {
				Idle.add (() => {
					// the client may have sent new proxy settings since
					// it was authorized, apply them as check_authorization does
					apply_pending_environment (sender);
					get_authorization_finished (sender, true);
					return false;
				});
				return;
			}
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					authorization_mutex.lock ();
					authorized_senders.add (sender);
					authorization_mutex.unlock ();
				}
				get_authorization_finished (sender, authorized);
			});
		}

		public void remove_authorization (BusName sender) throws Error {
			authorization_mutex.lock ();
			authorized_senders.remove (sender);
			authorization_mutex.unlock ();
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("write_alpm_config", () => {
							lockfile_mutex.lock ();
							alpm_utils.alpm_config.write (new_alpm_conf);
							alpm_utils.alpm_config.reload ();
							lockfile_mutex.unlock ();
							write_alpm_config_finished (sender);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						write_alpm_config_finished (sender);
					}
				} else {
					write_alpm_config_finished (sender);
				}
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					config.write (new_pamac_conf);
					config.reload ();
					if (config.enable_snap) {
						try {
							Process.spawn_command_line_async ("systemctl enable --now snapd.service");
						} catch (SpawnError e) {
							warning (e.message);
						}
					}
					if (config.offline_upgrade) {
						try {
							Process.spawn_command_line_async ("systemctl enable pamac-offline-upgrade.service");
						} catch (SpawnError e) {
							warning (e.message);
						}
					} else {
						try {
							Process.spawn_command_line_async ("systemctl disable pamac-offline-upgrade.service");
						} catch (SpawnError e) {
							warning (e.message);
						}
					}
				}
				write_pamac_config_finished (sender);
			});
		}

		public void start_generate_mirrors_list (string country, BusName sender) throws Error {
			// the country must not be read as an option by pacman-mirrors
			if (country.length == 0 || country.has_prefix ("-")) {
				emit_error (sender, "Daemon Error", {"invalid country: %s".printf (country)});
				Idle.add (() => {
					generate_mirrors_list_finished (sender);
					return false;
				});
				return;
			}
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("generate_mirrors_list", () => {
							try {
								var process = new Subprocess.newv (
									{"pacman-mirrors", "--no-color", "--country=" + country},
									SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
								var dis = new DataInputStream (process.get_stdout_pipe ());
								string? line;
								while ((line = dis.read_line ()) != null) {
									generate_mirrors_list_data (sender, line);
								}
							} catch (Error e) {
								emit_error (sender, "Daemon Error", {e.message});
							}
							lockfile_mutex.lock ();
							alpm_utils.alpm_config.reload ();
							lockfile_mutex.unlock ();
							generate_mirrors_list_finished (sender);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						generate_mirrors_list_finished (sender);
					}
				} else {
					generate_mirrors_list_finished (sender);
				}
			});
		}

		public void start_clean_cache (string[] filenames, BusName sender) throws Error {
			string[] names = filenames;
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					alpm_utils.clean_cache (names);
				}
				clean_cache_finished (sender, authorized);
			});
		}

		public void start_clean_build_files (string aur_build_dir, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					alpm_utils.clean_build_files (aur_build_dir, get_sender_uid (sender));
				}
				clean_build_files_finished (sender, authorized);
			});
		}

		public void start_set_pkgreason (string pkgname, uint reason, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("set_pkgreason", () => {
							lockfile_mutex.lock ();
							bool success = alpm_utils.set_pkgreason (sender, pkgname, reason);
							lockfile_mutex.unlock ();
							set_pkgreason_finished (sender, success);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						set_pkgreason_finished (sender, false);
					}
				} else {
					set_pkgreason_finished (sender, false);
				}
			});
		}

		public void start_download_updates (BusName sender) throws Error {
			if (alpm_utils.downloading_updates) {
				// already downloading updates
				// always answer, the caller is waiting for the finished signal
				Idle.add (() => {
					download_updates_finished (sender, false);
					return false;
				});
				return;
			}
			try {
				if (!cancellables_table.contains (sender)) {
					cancellables_table.insert (sender, new Cancellable ());
				}
				var cancellable = cancellables_table.lookup (sender);
				download_updates_uid = get_sender_uid (sender);
				// counted from the main thread, before the thread starts
				AtomicInt.inc (ref running_threads);
				new Thread<int>.try ("download_updates", () => {
					bool success = wait_for_lock (sender, cancellable, true);
					if (success) {
						// nested thread to exit when cancelled
						try {
							var thread = new Thread<int>.try ("download_updates2", () => {
								success = alpm_utils.download_updates (sender);
								return 0;
							});
							thread.join ();
							// the download thread is exited when cancelled
							// or may return early: always reset the flag here
							alpm_utils.downloading_updates = false;
						} catch (Error e) {
							emit_error (sender, "Daemon Error", {e.message});
							success = false;
						}
						lockfile_mutex.unlock ();
					}
					download_updates_finished (sender, success);
					AtomicInt.dec_and_test (ref running_threads);
					return 0;
				});
			} catch (Error e) {
				emit_error (sender, "Daemon Error", {e.message});
				AtomicInt.dec_and_test (ref running_threads);
				download_updates_finished (sender, false);
			}
		}

		public void start_download_pkgs (string[] urls, BusName sender) throws Error {
			string[] urls_copy = urls;
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						if (!cancellables_table.contains (sender)) {
							cancellables_table.insert (sender, new Cancellable ());
						}
						var cancellable = cancellables_table.lookup (sender);
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("download_pkgs", () => {
							var dload_paths = new GenericArray<string> ();
							bool success = wait_for_lock (sender, cancellable, true);
							if (success) {
								// nested thread to exit when cancelled
								try {
									var thread = new Thread<int>.try ("download_pkgs2", () => {
										success = alpm_utils.download_pkgs (sender, urls_copy, ref dload_paths);
										return 0;
									});
									thread.join ();
								} catch (Error e) {
									emit_error (sender, "Daemon Error", {e.message});
									success = false;
								}
								lockfile_mutex.unlock ();
							}
							download_pkgs_finished (sender, dload_paths.data);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						download_pkgs_finished (sender, {});
					}
				} else {
					download_pkgs_finished (sender, {});
				}
			});
		}

		bool wait_for_lock (string sender, Cancellable cancellable, bool quiet = false) {
			bool waiting = false;
			bool success = false;
			cancellable.reset ();
			if (!lockfile_mutex.trylock ()) {
				waiting = true;
				start_waiting (sender);
				if (!quiet) {
					emit_action (sender, _("Waiting for another package manager to quit") + "...");
				}
				answer_mutex.lock ();
				int i = 0;
				while (!cancellable.is_cancelled ()) {
					// wait 200 ms for cancellation
					int64 end_time = get_monotonic_time () + 200 * TimeSpan.MILLISECOND;
					answer_cond.wait_until (answer_mutex, end_time);
					if (lockfile_mutex.trylock ()) {
						success = true;
						break;
					}
					i++;
					// wait 5 min max
					if (i == 1500) {
						cancellable.cancel ();
						if (!quiet) {
							emit_action (sender, "%s: %s.".printf (_("Transaction cancelled"), _("Timeout expired")));
						}
					}
				}
				answer_mutex.unlock ();
			} else {
				success = true;
			}
			if (waiting) {
				stop_waiting (sender);
			}
			return success;
		}

		public void start_trans_refresh (bool force, BusName sender) throws Error {
			// do not check authorization
			try {
				if (!cancellables_table.contains (sender)) {
					cancellables_table.insert (sender, new Cancellable ());
				}
				var cancellable = cancellables_table.lookup (sender);
				bool cancel_download = may_cancel_download_updates (sender);
				// counted from the main thread, before the thread starts
				AtomicInt.inc (ref running_threads);
				new Thread<int>.try ("trans_refresh", () => {
					if (cancel_download && alpm_utils.downloading_updates) {
						// cancel download updates
						alpm_utils.cancellable.cancel ();
					}
					bool success = wait_for_lock (sender, cancellable);
					if (success) {
						// nested thread to exit when cancelled
						try {
							var thread = new Thread<int>.try ("trans_refresh2", () => {
								success = alpm_utils.trans_refresh (sender, force);
								return 0;
							});
							int ret = thread.join ();
							if (ret == -1) {
								success = false;
							}
						} catch (Error e) {
							emit_error (sender, "Daemon Error", {e.message});
							success = false;
						}
						lockfile_mutex.unlock ();
					}
					trans_refresh_finished (sender, success);
					AtomicInt.dec_and_test (ref running_threads);
					return 0;
				});
			} catch (Error e) {
				emit_error (sender, "Daemon Error", {e.message});
				AtomicInt.dec_and_test (ref running_threads);
				trans_refresh_finished (sender, false);
			}
		}

		public void start_trans_refresh_files (bool force, BusName sender) throws Error {
			// do not check authorization
			try {
				if (!cancellables_table.contains (sender)) {
					cancellables_table.insert (sender, new Cancellable ());
				}
				var cancellable = cancellables_table.lookup (sender);
				bool cancel_download = may_cancel_download_updates (sender);
				// counted from the main thread, before the thread starts
				AtomicInt.inc (ref running_threads);
				new Thread<int>.try ("trans_refresh_files", () => {
					if (cancel_download && alpm_utils.downloading_updates) {
						// cancel download updates
						alpm_utils.cancellable.cancel ();
					}
					bool success = wait_for_lock (sender, cancellable);
					if (success) {
						// nested thread to exit when cancelled
						try {
							var thread = new Thread<int>.try ("trans_refresh_files2", () => {
								success = alpm_utils.trans_refresh_files (sender, force);
								return 0;
							});
							int ret = thread.join ();
							if (ret == -1) {
								success = false;
							}
						} catch (Error e) {
							emit_error (sender, "Daemon Error", {e.message});
							success = false;
						}
						lockfile_mutex.unlock ();
					}
					trans_refresh_files_finished (sender, success);
					AtomicInt.dec_and_test (ref running_threads);
					return 0;
				});
			} catch (Error e) {
				emit_error (sender, "Daemon Error", {e.message});
				AtomicInt.dec_and_test (ref running_threads);
				trans_refresh_files_finished (sender, false);
			}
		}

		public void start_trans_refresh_aur (bool force, BusName sender) throws Error {
			// do not check authorization
			try {
				if (!cancellables_table.contains (sender)) {
					cancellables_table.insert (sender, new Cancellable ());
				}
				var cancellable = cancellables_table.lookup (sender);
				bool cancel_download = may_cancel_download_updates (sender);
				// counted from the main thread, before the thread starts
				AtomicInt.inc (ref running_threads);
				new Thread<int>.try ("trans_refresh_aur", () => {
					if (cancel_download && alpm_utils.downloading_updates) {
						// cancel download updates
						alpm_utils.cancellable.cancel ();
					}
					bool success = wait_for_lock (sender, cancellable);
					if (success) {
						// nested thread to exit when cancelled
						try {
							var thread = new Thread<int>.try ("trans_refresh_aur2", () => {
								success = alpm_utils.trans_refresh_aur (sender, force);
								return 0;
							});
							int ret = thread.join ();
							if (ret == -1) {
								success = false;
							}
						} catch (Error e) {
							emit_error (sender, "Daemon Error", {e.message});
							success = false;
						}
						lockfile_mutex.unlock ();
					}
					trans_refresh_aur_finished (sender, success);
					AtomicInt.dec_and_test (ref running_threads);
					return 0;
				});
			} catch (Error e) {
				emit_error (sender, "Daemon Error", {e.message});
				AtomicInt.dec_and_test (ref running_threads);
				trans_refresh_aur_finished (sender, false);
			}
		}

		public void start_trans_run (bool sysupgrade,
									bool enable_downgrade,
									bool simple_install,
									bool keep_built_pkgs,
									int trans_flags,
									string[] to_install,
									string[] to_remove,
									string[] to_load_local,
									string[] to_load_remote,
									string[] to_install_as_dep,
									string[] ignorepkgs,
									string[] overwrite_files,
									BusName sender) throws Error {
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			string[] to_load_local_copy = to_load_local;
			string[] to_load_remote_copy = to_load_remote;
			string[] to_install_as_dep_copy = to_install_as_dep;
			string[] ignorepkgs_copy = ignorepkgs;
			string[] overwrite_files_copy = overwrite_files;
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						if (!cancellables_table.contains (sender)) {
							cancellables_table.insert (sender, new Cancellable ());
						}
						var cancellable = cancellables_table.lookup (sender);
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("trans_run", () => {
							if (alpm_utils.downloading_updates) {
								// cancel download updates
								alpm_utils.cancellable.cancel ();
							}
							bool success = wait_for_lock (sender, cancellable);
							if (success) {
								// nested thread to exit when download is cancelled
								try {
									var thread = new Thread<int>.try ("trans_run2", () => {
										success = alpm_utils.trans_run (sender,
															sysupgrade,
															enable_downgrade,
															simple_install,
															keep_built_pkgs,
															trans_flags,
															to_install_copy,
															to_remove_copy,
															to_load_local_copy,
															to_load_remote_copy,
															to_install_as_dep_copy,
															ignorepkgs_copy,
															overwrite_files_copy);
										return 0;
									});
									thread.join ();
								} catch (Error e) {
									emit_error (sender, "Daemon Error", {e.message});
									success = false;
								}
								lockfile_mutex.unlock ();
							}
							trans_run_finished (sender, success);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						trans_run_finished (sender, false);
					}
				} else {
					trans_run_finished (sender, false);
				}
			});
		}

		public void start_snap_trans_run (string[] to_install, string[] to_remove, BusName sender) throws Error {
			if (!config.enable_snap) {
				Idle.add (() => {
					snap_trans_run_finished (sender, false);
					return false;
				});
				return;
			}
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("snap_trans_run", () => {
							bool success = snap_plugin.trans_run (sender, to_install_copy, to_remove_copy);
							snap_trans_run_finished (sender, success);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						snap_trans_run_finished (sender, false);
					}
				} else {
					snap_trans_run_finished (sender, false);
				}
			});
		}

		public void start_snap_switch_channel (string snap_name, string snap_channel, BusName sender) throws Error {
			if (!config.enable_snap) {
				Idle.add (() => {
					snap_switch_channel_finished (sender, false);
					return false;
				});
				return;
			}
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("snap_switch_channel", () => {
							bool success = snap_plugin.switch_channel (sender, snap_name, snap_channel);
							snap_switch_channel_finished (sender, success);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						snap_switch_channel_finished (sender, false);
					}
				} else {
					snap_switch_channel_finished (sender, false);
				}
			});
		}

		public void start_flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade, BusName sender) throws Error {
			if (!config.enable_flatpak) {
				Idle.add (() => {
					flatpak_trans_run_finished (sender, false);
					return false;
				});
				return;
			}
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			string[] to_upgrade_copy = to_upgrade;
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						// counted from the main thread, before the thread starts
						AtomicInt.inc (ref running_threads);
						new Thread<int>.try ("flatpak_trans_run", () => {
							bool success = flatpak_plugin.trans_run (sender, to_install_copy, to_remove_copy, to_upgrade_copy);
							flatpak_trans_run_finished (sender, success);
							AtomicInt.dec_and_test (ref running_threads);
							return 0;
						});
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
						AtomicInt.dec_and_test (ref running_threads);
						flatpak_trans_run_finished (sender, false);
					}
				} else {
					flatpak_trans_run_finished (sender, false);
				}
			});
		}

		public void trans_cancel (BusName sender) throws Error {
			Cancellable? cancellable = cancellables_table.lookup (sender);
			if (cancellable != null) {
				answer_mutex.lock ();
				cancellable.cancel ();
				answer_cond.signal ();
				answer_mutex.unlock ();
			}
			if (config.enable_snap) {
				snap_plugin.trans_cancel (sender);
			}
			if (config.enable_flatpak) {
				flatpak_plugin.trans_cancel (sender);
			}
			alpm_utils.trans_cancel (sender);
		}

		[DBus (no_reply = true)]
		public void quit () throws Error {
			// do not quit if downloading updates
			if (alpm_utils.downloading_updates) {
				return;
			}
			if (AtomicInt.get (ref running_threads) == 0) {
				loop.quit ();
			}
		}
	}
}

// every signal of the daemon interface starts with the bus name of the client
// it is meant for: send it only to this client instead of broadcasting it,
// so other users can not follow the transactions of others.
// Signals without arguments (TransactionFinished) stay broadcast.
DBusMessage? direct_signals_filter (DBusConnection connection, owned DBusMessage message, bool incoming) {
	if (incoming
		|| message.get_message_type () != DBusMessageType.SIGNAL
		|| message.get_destination () != null
		|| message.get_interface () != "org.manjaro.pamac.daemon") {
		return message;
	}
	Variant? body = message.get_body ();
	if (body == null || body.n_children () == 0) {
		return message;
	}
	Variant first = body.get_child_value (0);
	if (!first.is_of_type (VariantType.STRING)) {
		return message;
	}
	unowned string recipient = first.get_string ();
	if (!GLib.DBus.is_unique_name (recipient)) {
		return message;
	}
	try {
		DBusMessage directed = message.copy ();
		directed.set_destination (recipient);
		return directed;
	} catch (Error e) {
		warning (e.message);
	}
	return message;
}

void on_bus_acquired (DBusConnection conn) {
	conn.add_filter (direct_signals_filter);
	system_daemon = new Pamac.Daemon ();
	try {
		conn.register_object ("/org/manjaro/pamac/daemon", system_daemon);
	}
	catch (IOError e) {
		warning ("Could not register service");
		loop.quit ();
	}
}

void main () {
	// i18n
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.textdomain (GETTEXT_PACKAGE);

	Bus.own_name (BusType.SYSTEM,
				"org.manjaro.pamac.daemon",
				BusNameOwnerFlags.NONE,
				on_bus_acquired,
				null,
				() => {
					warning ("Could not acquire name");
					loop.quit ();
				});

	loop = new MainLoop ();
	loop.run ();
}
