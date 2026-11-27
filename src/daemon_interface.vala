/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	// the long methods reply when they are finished:
	// use the proxy with no timeout (see disable_timeout)
	[DBus (name = "org.manjaro.pamac.daemon")]
	interface Daemon : Object {
		public abstract string get_sender () throws Error;
		public abstract string get_lockfile () throws Error;
		public abstract void set_environment_variables (HashTable<string,string> variables) throws Error;
		public abstract async bool get_authorization () throws Error;
		public abstract void remove_authorization () throws Error;
		public abstract async void write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws Error;
		public abstract async void write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws Error;
		public abstract async void generate_mirrors_list (string country) throws Error;
		public abstract async bool clean_cache (string[] filenames) throws Error;
		public abstract async bool clean_build_files (string aur_build_dir) throws Error;
		public abstract async bool set_pkgreason (string pkgname, uint reason) throws Error;
		public abstract async bool download_updates () throws Error;
		public abstract async string[] download_pkgs (string[] urls) throws Error;
		public abstract async bool trans_refresh (bool force) throws Error;
		public abstract async bool trans_refresh_files (bool force) throws Error;
		public abstract async bool trans_refresh_aur (bool force) throws Error;
		// request: see TransactionRequest
		public abstract async bool trans_run (HashTable<string,Variant> request) throws Error;
		public abstract async bool snap_trans_run (string[] to_install, string[] to_remove) throws Error;
		public abstract async bool snap_switch_channel (string snap_name, string channel) throws Error;
		public abstract async bool flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade) throws Error;
		public abstract void trans_cancel () throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		// progress signals, sent only to the client given as sender
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
	}

	// the methods of the daemon can last longer than the default D-Bus timeout
	internal void disable_timeout (Daemon daemon) {
		((DBusProxy) daemon).set_default_timeout (int.MAX);
	}
}
