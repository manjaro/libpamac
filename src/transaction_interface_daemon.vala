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
	internal class TransactionInterfaceDaemon: Object, TransactionInterface {
		Config config;
		Daemon? system_daemon;
		string sender;

		public TransactionInterfaceDaemon (Config config) {
			this.config = config;
			sender = "";
			try {
				get_system_daemon ();
			} catch (Error e) {
				warning ("failed to connect to dbus daemon: %s", e.message);
			}
		}

		// each method of the daemon replies when its operation is finished,
		// with an error if the connection is lost meanwhile
		public async bool get_authorization () throws Error {
			return yield get_system_daemon ().get_authorization ();
		}

		public void remove_authorization () throws Error {
			get_system_daemon ().remove_authorization ();
		}

		public async void generate_mirrors_list (string country) throws Error {
			yield get_system_daemon ().generate_mirrors_list (country);
		}

		public async bool clean_cache (GenericArray<string> filenames) throws Error {
			return yield get_system_daemon ().clean_cache (filenames.data);
		}

		public async bool clean_build_files (string aur_build_dir) throws Error {
			return yield get_system_daemon ().clean_build_files (aur_build_dir);
		}

		public async bool set_pkgreason (string pkgname, uint reason) throws Error {
			return yield get_system_daemon ().set_pkgreason (pkgname, reason);
		}

		public async bool download_updates () throws Error {
			return yield get_system_daemon ().download_updates ();
		}

		public async string[] download_pkgs (GenericArray<string> urls) throws Error {
			return yield get_system_daemon ().download_pkgs (urls.data);
		}

		public async bool trans_refresh (bool force) throws Error {
			return yield get_system_daemon ().trans_refresh (force);
		}

		public async bool trans_refresh_files (bool force) throws Error {
			return yield get_system_daemon ().trans_refresh_files (force);
		}

		public async bool trans_refresh_aur (bool force) throws Error {
			return yield get_system_daemon ().trans_refresh_aur (force);
		}

		public async bool trans_run (TransactionRequest request) throws Error {
			return yield get_system_daemon ().trans_run (request.to_dict ());
		}

		public void trans_cancel () throws Error {
			get_system_daemon ().trans_cancel ();
		}

		public async bool snap_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove) throws Error {
			return yield get_system_daemon ().snap_trans_run (to_install.data, to_remove.data);
		}

		public async bool snap_switch_channel (string snap_name, string channel) throws Error {
			return yield get_system_daemon ().snap_switch_channel (snap_name, channel);
		}

		public async bool flatpak_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove, GenericArray<string> to_upgrade) throws Error {
			return yield get_system_daemon ().flatpak_trans_run (to_install.data, to_remove.data, to_upgrade.data);
		}

		public void quit_daemon () throws Error {
			get_system_daemon ().quit ();
		}

		void on_emit_action (string sender, string action) {
			if (sender == this.sender) {
				emit_action (action);
			}
		}

		void on_emit_action_progress (string sender, string action, string status, double progress) {
			if (sender == this.sender) {
				emit_action_progress (action, status, progress);
			}
		}

		void on_emit_download_progress (string sender, string action, string status, double progress) {
			if (sender == this.sender) {
				emit_download_progress (action, status, progress);
			}
		}

		void on_emit_hook_progress (string sender, string action, string details, string status, double progress) {
			if (sender == this.sender) {
				emit_hook_progress (action, details, status, progress);
			}
		}

		void on_emit_script_output (string sender, string message) {
			if (sender == this.sender) {
				emit_script_output (message);
			}
		}

		void on_emit_warning (string sender, string message) {
			if (sender == this.sender) {
				emit_warning (message);
			}
		}

		void on_emit_error (string sender, string message, string[] details) {
			if (sender == this.sender) {
				var details_array = new GenericArray<string> (details.length);
				foreach (unowned string detail in details) {
					details_array.add (detail);
				}
				emit_error (message, details_array);
			}
		}

		void on_important_details_outpout (string sender, bool must_show) {
			if (sender == this.sender) {
				important_details_outpout (must_show);
			}
		}

		void on_start_downloading (string sender) {
			if (sender == this.sender) {
				start_downloading ();
			}
		}

		void on_stop_downloading (string sender) {
			if (sender == this.sender) {
				stop_downloading ();
			}
		}

		void on_start_waiting (string sender) {
			if (sender == this.sender) {
				start_waiting ();
			}
		}

		void on_stop_waiting (string sender) {
			if (sender == this.sender) {
				stop_waiting ();
			}
		}

		void on_generate_mirrors_list_data (string sender, string line) {
			if (sender == this.sender) {
				generate_mirrors_list_data (line);
			}
		}

		Daemon get_system_daemon () throws Error {
			if (system_daemon != null) {
				return system_daemon;
			}
			DBusConnection connection = Bus.get_sync (BusType.SYSTEM);
			if (connection.is_closed ()) {
				// the shared connection stays closed once the bus dropped it,
				// so use a private one to reconnect
				connection = new DBusConnection.for_address_sync (BusType.SYSTEM.get_address_sync (),
																	DBusConnectionFlags.AUTHENTICATION_CLIENT |
																	DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
			}
			// by default GDBus raises SIGTERM when the bus closes the connection,
			// which silently kills the client while the daemon keeps running
			connection.exit_on_close = false;
			Daemon daemon = connection.get_proxy_sync ("org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
			disable_timeout (daemon);
			// Set environment variables
			daemon.set_environment_variables (config.environment_variables);
			string new_sender = daemon.get_sender ();
			system_daemon = daemon;
			sender = new_sender;
			connecting_dbus_signals ();
			connection.on_closed.connect (on_connection_closed);
			return daemon;
		}

		void on_connection_closed (DBusConnection connection, bool remote_peer_vanished, Error? error) {
			connection.on_closed.disconnect (on_connection_closed);
			system_daemon = null;
			sender = "";
			var details = new GenericArray<string> (2);
			details.add (_("The transaction may still be running in the background"));
			if (error != null) {
				details.add (error.message);
			}
			emit_error (_("Connection to the daemon was lost"), details);
			// the pending calls fail with IOError.CLOSED
			stop_downloading ();
			stop_waiting ();
		}

		void connecting_dbus_signals () {
			system_daemon.emit_action.connect (on_emit_action);
			system_daemon.emit_action_progress.connect (on_emit_action_progress);
			system_daemon.emit_download_progress.connect (on_emit_download_progress);
			system_daemon.emit_hook_progress.connect (on_emit_hook_progress);
			system_daemon.emit_script_output.connect (on_emit_script_output);
			system_daemon.emit_warning.connect (on_emit_warning);
			system_daemon.emit_error.connect (on_emit_error);
			system_daemon.important_details_outpout.connect (on_important_details_outpout);
			system_daemon.start_downloading.connect (on_start_downloading);
			system_daemon.stop_downloading.connect (on_stop_downloading);
			system_daemon.start_waiting.connect (on_start_waiting);
			system_daemon.stop_waiting.connect (on_stop_waiting);
			system_daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
		}
	}
}
