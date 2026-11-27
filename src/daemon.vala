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
		// operations in progress, quit waits for them
		int running_operations;
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
		// the sink of each client, to send it the progress of its operations
		HashTable<string, DaemonSink> sinks_table;
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
		public signal void start_waiting (string sender);
		public signal void stop_waiting (string sender);
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
			running_operations = 0;
			answer_cond = Cond ();
			answer_mutex = Mutex ();
			authorization_mutex = Mutex ();
			authorized_senders = new GenericSet<string> (str_hash, str_equal);
			pending_environments = new HashTable<string, HashTable<string, string>> (str_hash, str_equal);
			download_updates_uid = -1;
			cancellables_table = new HashTable<string, Cancellable> (str_hash, str_equal);
			sinks_table = new HashTable<string, DaemonSink> (str_hash, str_equal);
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
			// the plugins report the progress of their transactions to a DaemonSink
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
			}
			if (config.support_flatpak) {
				flatpak_plugin = config.get_flatpak_plugin ();
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
			// running operations keep their own reference on the cancellable and the sink
			cancellables_table.remove (name);
			sinks_table.remove (name);
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
			if (!alpm_utils.is_download_updates_requested ()) {
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

		// the methods doing some work are counted from their call to their reply,
		// including the wait for polkit, so quit does not stop the daemon meanwhile
		void hold () {
			AtomicInt.inc (ref running_operations);
		}

		void release () {
			AtomicInt.dec_and_test (ref running_operations);
		}

		async bool check_authorization (BusName sender) {
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
			return authorized;
		}

		public async bool get_authorization (BusName sender) throws Error {
			authorization_mutex.lock ();
			bool fast_authorized = authorized_senders.contains (sender);
			authorization_mutex.unlock ();
			if (fast_authorized) {
				// the client may have sent new proxy settings since
				// it was authorized, apply them as check_authorization does
				apply_pending_environment (sender);
				return true;
			}
			hold ();
			try {
				bool authorized = yield check_authorization (sender);
				if (authorized) {
					authorization_mutex.lock ();
					authorized_senders.add (sender);
					authorization_mutex.unlock ();
				}
				return authorized;
			} finally {
				release ();
			}
		}

		public void remove_authorization (BusName sender) throws Error {
			authorization_mutex.lock ();
			authorized_senders.remove (sender);
			authorization_mutex.unlock ();
		}

		DaemonSink get_sink (string sender) {
			DaemonSink? sink = sinks_table.lookup (sender);
			if (sink == null) {
				sink = new DaemonSink (this, sender);
				sinks_table.insert (sender, sink);
			}
			return sink;
		}

		Cancellable get_cancellable (string sender) {
			Cancellable? cancellable = cancellables_table.lookup (sender);
			if (cancellable == null) {
				cancellable = new Cancellable ();
				cancellables_table.insert (sender, cancellable);
			}
			return cancellable;
		}

		// run func in a worker thread, the coroutine is resumed in the main thread
		async bool run_thread (string name, owned BoolFunc func) throws Error {
			return yield run_in_thread (name, MainContext.default (), (owned) func);
		}

		// run func with the lock held, in a nested thread which is exited
		// when a download is cancelled (see cb_download).
		// To call from a worker thread.
		// Returns false if the lock is not acquired, the thread is exited or func fails
		bool run_locked (string sender, Cancellable cancellable, bool quiet, BoolFunc func) {
			if (!wait_for_lock (sender, cancellable, quiet)) {
				return false;
			}
			bool success = run_exitable ("locked_work", func);
			lockfile_mutex.unlock ();
			return success;
		}

		public async void write_alpm_config (HashTable<string,Variant> new_alpm_conf, BusName sender) throws Error {
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return;
				}
				yield run_thread ("write_alpm_config", () => {
					lockfile_mutex.lock ();
					alpm_utils.alpm_config.write (new_alpm_conf);
					alpm_utils.alpm_config.reload ();
					lockfile_mutex.unlock ();
					return true;
				});
			} finally {
				release ();
			}
		}

		// run a command without shell parsing and without waiting for it
		static void spawn_command_async (string[] argv) {
			try {
				Process.spawn_async (null, argv, null, SpawnFlags.SEARCH_PATH, null, null);
			} catch (SpawnError e) {
				warning (e.message);
			}
		}

		public async void write_pamac_config (HashTable<string,Variant> new_pamac_conf, BusName sender) throws Error {
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return;
				}
				bool old_enable_snap = config.enable_snap;
				bool old_offline_upgrade = config.offline_upgrade;
				config.write (new_pamac_conf);
				config.reload ();
				// only change the services when the options changed
				if (config.enable_snap && !old_enable_snap) {
					spawn_command_async ({"systemctl", "enable", "--now", "snapd.service"});
				}
				if (config.offline_upgrade != old_offline_upgrade) {
					spawn_command_async ({"systemctl", config.offline_upgrade ? "enable" : "disable", "pamac-offline-upgrade.service"});
				}
			} finally {
				release ();
			}
		}

		public async void generate_mirrors_list (string country, BusName sender) throws Error {
			// the country must not be read as an option by pacman-mirrors
			if (country.length == 0 || country.has_prefix ("-")) {
				emit_error (sender, "Daemon Error", {"invalid country: %s".printf (country)});
				return;
			}
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return;
				}
				yield run_thread ("generate_mirrors_list", () => {
					try {
						var process = new Subprocess.newv (
							{"pacman-mirrors", "--no-color", "--country=" + country},
							SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
						var dis = new DataInputStream (process.get_stdout_pipe ());
						string? line;
						while ((line = dis.read_line ()) != null) {
							emit_script_output (sender, line);
						}
					} catch (Error e) {
						emit_error (sender, "Daemon Error", {e.message});
					}
					lockfile_mutex.lock ();
					alpm_utils.alpm_config.reload ();
					lockfile_mutex.unlock ();
					return true;
				});
			} finally {
				release ();
			}
		}

		// the cleanings run with the lock held: they must not remove the files
		// used by a running transaction nor block the main loop
		public async bool clean_cache (string[] filenames, BusName sender) throws Error {
			string[] names = filenames;
			var cancellable = get_cancellable (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("clean_cache", () => {
					if (!wait_for_lock (sender, cancellable, true)) {
						return false;
					}
					bool success = alpm_utils.clean_cache (names);
					lockfile_mutex.unlock ();
					return success;
				});
			} finally {
				release ();
			}
		}

		public async bool clean_build_files (string aur_build_dir, BusName sender) throws Error {
			var cancellable = get_cancellable (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("clean_build_files", () => {
					if (!wait_for_lock (sender, cancellable, true)) {
						return false;
					}
					bool success = alpm_utils.clean_build_files (aur_build_dir, get_sender_uid (sender));
					lockfile_mutex.unlock ();
					return success;
				});
			} finally {
				release ();
			}
		}

		public async bool set_pkgreason (string pkgname, uint reason, BusName sender) throws Error {
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("set_pkgreason", () => {
					lockfile_mutex.lock ();
					bool success = alpm_utils.set_pkgreason (sink, pkgname, reason);
					lockfile_mutex.unlock ();
					return success;
				});
			} finally {
				release ();
			}
		}

		// does not check authorization
		public async bool download_updates (BusName sender) throws Error {
			// requested from the main thread: a second call can not start another download
			// while the first one waits for the lock
			if (!alpm_utils.request_download_updates ()) {
				// already downloading updates
				return false;
			}
			var cancellable = get_cancellable (sender);
			var sink = get_sink (sender);
			download_updates_uid = get_sender_uid (sender);
			hold ();
			try {
				return yield run_thread ("download_updates", () => {
					return run_locked (sender, cancellable, true, () => {
						return alpm_utils.download_updates (sink);
					});
				});
			} finally {
				// the download thread is exited when cancelled
				// or may return early: always end it here
				alpm_utils.end_download_updates ();
				release ();
			}
		}

		public async string[] download_pkgs (string[] urls, BusName sender) throws Error {
			string[] urls_copy = urls;
			var cancellable = get_cancellable (sender);
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return {};
				}
				var dload_paths = new GenericArray<string> ();
				yield run_thread ("download_pkgs", () => {
					return run_locked (sender, cancellable, true, () => {
						return alpm_utils.download_pkgs (sink, urls_copy, ref dload_paths);
					});
				});
				return dload_paths.data;
			} finally {
				release ();
			}
		}

		// to call from a worker thread
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
				// wait 5 min max: a deadline because answer_cond is also
				// broadcast by the cancellations of other clients
				int64 deadline = get_monotonic_time () + 5 * TimeSpan.MINUTE;
				while (!cancellable.is_cancelled ()) {
					// wait 200 ms for cancellation
					int64 end_time = get_monotonic_time () + 200 * TimeSpan.MILLISECOND;
					answer_cond.wait_until (answer_mutex, end_time);
					if (lockfile_mutex.trylock ()) {
						success = true;
						break;
					}
					if (get_monotonic_time () >= deadline) {
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

		// the refreshes do not check authorization
		async bool refresh (string sender, string name, owned BoolFunc func) throws Error {
			var cancellable = get_cancellable (sender);
			if (may_cancel_download_updates (sender)) {
				// also if it waits for the lock, else the refresh would wait for it
				alpm_utils.cancel_download_updates ();
			}
			hold ();
			try {
				return yield run_thread (name, () => {
					return run_locked (sender, cancellable, false, func);
				});
			} finally {
				release ();
			}
		}

		public async bool trans_refresh (bool force, BusName sender) throws Error {
			var sink = get_sink (sender);
			return yield refresh (sender, "trans_refresh", () => {
				return alpm_utils.trans_refresh (sink, force);
			});
		}

		public async bool trans_refresh_files (bool force, BusName sender) throws Error {
			var sink = get_sink (sender);
			return yield refresh (sender, "trans_refresh_files", () => {
				return alpm_utils.trans_refresh_files (sink, force);
			});
		}

		public async bool trans_refresh_aur (bool force, BusName sender) throws Error {
			var sink = get_sink (sender);
			return yield refresh (sender, "trans_refresh_aur", () => {
				return alpm_utils.trans_refresh_aur (sink, force);
			});
		}

		// request: see TransactionRequest
		public async bool trans_run (HashTable<string,Variant> request, BusName sender) throws Error {
			var trans_request = new TransactionRequest.from_dict (request);
			var cancellable = get_cancellable (sender);
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				// also if it waits for the lock, else the transaction would wait for it
				alpm_utils.cancel_download_updates ();
				return yield run_thread ("trans_run", () => {
					return run_locked (sender, cancellable, false, () => {
						return alpm_utils.trans_run (sink, trans_request);
					});
				});
			} finally {
				transaction_finished ();
				release ();
			}
		}

		public async bool snap_trans_run (string[] to_install, string[] to_remove, BusName sender) throws Error {
			if (!config.enable_snap) {
				return false;
			}
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("snap_trans_run", () => {
					return snap_plugin.trans_run (sink, to_install_copy, to_remove_copy);
				});
			} finally {
				transaction_finished ();
				release ();
			}
		}

		public async bool snap_switch_channel (string snap_name, string snap_channel, BusName sender) throws Error {
			if (!config.enable_snap) {
				return false;
			}
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("snap_switch_channel", () => {
					return snap_plugin.switch_channel (sink, snap_name, snap_channel);
				});
			} finally {
				release ();
			}
		}

		public async bool flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade, BusName sender) throws Error {
			if (!config.enable_flatpak) {
				return false;
			}
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			string[] to_upgrade_copy = to_upgrade;
			var sink = get_sink (sender);
			hold ();
			try {
				if (!(yield check_authorization (sender))) {
					return false;
				}
				return yield run_thread ("flatpak_trans_run", () => {
					return flatpak_plugin.trans_run (sink, to_install_copy, to_remove_copy, to_upgrade_copy);
				});
			} finally {
				transaction_finished ();
				release ();
			}
		}

		public void trans_cancel (BusName sender) throws Error {
			Cancellable? cancellable = cancellables_table.lookup (sender);
			if (cancellable != null) {
				answer_mutex.lock ();
				cancellable.cancel ();
				// every waiting thread shares answer_cond: wake them all
				answer_cond.broadcast ();
				answer_mutex.unlock ();
			}
			// no sink: this client never ran an operation
			DaemonSink? sink = sinks_table.lookup (sender);
			if (sink == null) {
				return;
			}
			if (config.enable_snap) {
				snap_plugin.trans_cancel (sink);
			}
			if (config.enable_flatpak) {
				flatpak_plugin.trans_cancel (sink);
			}
			alpm_utils.trans_cancel (sink);
		}

		[DBus (no_reply = true)]
		public void quit () throws Error {
			// do not quit if downloading updates
			if (alpm_utils.is_download_updates_requested ()) {
				return;
			}
			if (AtomicInt.get (ref running_operations) == 0) {
				loop.quit ();
			}
		}
	}

	// sends the progress to a client: the D-Bus signals are thread-safe
	// and sent only to this client (see direct_signals_filter)
	internal class DaemonSink : Object, TransactionSink {
		unowned Daemon daemon;
		string sender;

		public DaemonSink (Daemon daemon, string sender) {
			this.daemon = daemon;
			this.sender = sender;
		}

		public void emit_action (string action) {
			daemon.emit_action (sender, action);
		}

		public void emit_action_progress (string action, string status, double progress) {
			daemon.emit_action_progress (sender, action, status, progress);
		}

		public void emit_download_progress (string action, string status, double progress) {
			daemon.emit_download_progress (sender, action, status, progress);
		}

		public void emit_hook_progress (string action, string details, string status, double progress) {
			daemon.emit_hook_progress (sender, action, details, status, progress);
		}

		public void emit_script_output (string message) {
			daemon.emit_script_output (sender, message);
		}

		public void emit_warning (string message) {
			daemon.emit_warning (sender, message);
		}

		public void emit_error (string message, GenericArray<string> details) {
			daemon.emit_error (sender, message, details.data);
		}

		public void important_details_outpout (bool must_show) {
			daemon.important_details_outpout (sender, must_show);
		}

		public void start_downloading () {
			daemon.start_downloading (sender);
		}

		public void stop_downloading () {
			daemon.stop_downloading (sender);
		}

		public void start_waiting () {
			daemon.start_waiting (sender);
		}

		public void stop_waiting () {
			daemon.stop_waiting (sender);
		}

		public int choose_provider (string depend, GenericArray<string> providers) {
			// the providers are chosen by the client when preparing the transaction
			return 0;
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
