/*
 *  pamac-vala
 *
 *  Copyright (C) 2023 Guillaume Benoit <guillaume@manjaro.org>
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

string? get_os_id () {
	var file = GLib.File.new_for_path ("/etc/os-release");
	if (file.query_exists ()) {
		try {
			var dis = new DataInputStream (file.read ());
			string? line;
			// Read lines until end of file (null) is reached
			while ((line = dis.read_line ()) != null) {
				if (line.has_prefix ("ID=")) {
					return (owned) line.split ("ID=", 2)[1];
				}
			}
		} catch (Error e) {
			// silent error
		}
	}
	return null;
}

string get_user_agent () {
	string? id = get_os_id ();
	if (id == null) {
		return "Pamac/%s".printf (VERSION);
	} else {
		return "Pamac/%s_%s".printf (VERSION, id);
	}
}
