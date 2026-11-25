/*
 *  pamac-vala
 *
 *  Copyright (C) 2020-2023 Guillaume Benoit <guillaume@manjaro.org>
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
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {
	public class UpdatesChecker : Object {
		MainLoop loop;
		Config config;
		uint check_lock_timeout_id;
		GLib.File _lock;
		FileMonitor lock_monitor;
		uint16 _updates_nb;
		string[] _updates_list;
		public uint16 updates_nb { get { return _updates_nb; } }
		public string[] updates_list { get { return _updates_list; } }
		public uint64 refresh_period { get { return config.refresh_period; } }
		public bool no_update_hide_icon { get { return config.no_update_hide_icon; } }

		public signal void updates_available (uint16 updates_nb);

		public UpdatesChecker () {
			Object ();
		}

		construct {
			loop = new MainLoop ();
			config = new Config ("/etc/pamac.conf");
			string lock_str = Path.build_filename (config.db_path, "db.lck");
			_lock = GLib.File.new_for_path (lock_str);
			try {
				lock_monitor = _lock.monitor_file (FileMonitorFlags.NONE);
				lock_monitor.changed.connect (on_lock_changed);
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void check_updates () {
			lock_monitor.changed.disconnect (on_lock_changed);
			config.reload ();
			if (config.refresh_period != 0) {
				// get updates
				string[] cmds = {"pamac-checkupdates"};
				message ("check updates");
				try {
					var process = new Subprocess.newv (cmds, SubprocessFlags.STDOUT_PIPE);
					// read the output while the process runs: waiting for its end
					// first blocks it as soon as the pipe buffer is full
					process.communicate_utf8_async.begin (null, null, (obj, res) => {
						_updates_nb = 0;
						_updates_list = {};
						try {
							string? output;
							process.communicate_utf8_async.end (res, out output, null);
							// status 100 means updates are available
							if (process.get_if_exited () && process.get_exit_status () == 100 && output != null) {
								// count lines
								foreach (unowned string line in output.split ("\n")) {
									if (line.length > 0) {
										_updates_nb++;
										_updates_list += line;
									}
								}
							}
						} catch (Error e) {
							warning (e.message);
						}
						loop.quit ();
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
				updates_available (_updates_nb);
			}
			lock_monitor.changed.connect (on_lock_changed);
		}

		void on_lock_changed (File src, File? dest, FileMonitorEvent event_type) {
			if (event_type == FileMonitorEvent.CREATED) {
				if (check_lock_timeout_id != 0) {
					Source.remove (check_lock_timeout_id);
				}
			}
			if (event_type == FileMonitorEvent.DELETED) {
				if (check_lock_timeout_id != 0) {
					Source.remove (check_lock_timeout_id);
				}
				check_lock_timeout_id = Timeout.add (5000, () => {
					check_updates ();
					check_lock_timeout_id = 0;
					return false;
				});
			}
		}
	}
}
