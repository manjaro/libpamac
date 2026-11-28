/*
 *  pamac-vala
 *
 *  Copyright (C) 2023-2026 Guillaume Benoit <guillaume@manjaro.org>
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

namespace Pamac {
	internal delegate bool BoolFunc ();

	// run func in a new thread without blocking the main loop of context,
	// the coroutine is resumed in context when func returns.
	// func must not call Thread.exit: wrap it with run_exitable if it can.
	// Throws an error if the thread can not be created
	internal async bool run_in_thread (string name, MainContext context, owned BoolFunc func) throws Error {
		bool result = false;
		SourceFunc callback = run_in_thread.callback;
		new Thread<int>.try (name, () => {
			result = func ();
			var idle = new IdleSource ();
			idle.set_callback ((owned) callback);
			idle.attach (context);
			return 0;
		});
		yield;
		return result;
	}

	// run func in a nested thread and wait for it: the nested thread is exited
	// when a download is cancelled (see cb_download), the calling one is not.
	// Returns false if the thread can not be created, is exited or func fails
	internal bool run_exitable (string name, BoolFunc func) {
		bool result = false;
		try {
			var thread = new Thread<int>.try (name, () => {
				result = func ();
				return 0;
			});
			// -1 when the thread was exited
			if (thread.join () == -1) {
				return false;
			}
		} catch (Error e) {
			warning (e.message);
			return false;
		}
		return result;
	}

	// the value of OfficialRepos in pamac.conf, the repositories of Arch Linux and Manjaro if null
	internal GenericSet<string?> parse_official_repos (string? value) {
		var repos = new GenericSet<string?> (str_hash, str_equal);
		string names = value ?? "core extra multilib core-testing extra-testing multilib-testing";
		foreach (unowned string name in names.split (" ")) {
			if (name != "") {
				repos.add (name);
			}
		}
		return repos;
	}

	// the package needs a restart to be used
	public bool package_needs_reboot (string name) {
		// kernels and their modules or firmwares: "linux", "linux-lts", "linux612-nvidia", "linux-firmware"…
		if (/^linux[0-9]*(?:-.+)?$/.match (name)) {
			// headers and docs are not loaded
			return !name.has_suffix ("-headers") && !name.has_suffix ("-docs");
		}
		const string[] PREFIXES = {"nvidia-", "lib32-nvidia-", "systemd", "xf86-", "xorg-"};
		foreach (unowned string prefix in PREFIXES) {
			if (name.has_prefix (prefix)) {
				return true;
			}
		}
		return "mesa" in name || "wayland" in name || name == "cryptsetup" || name.has_suffix ("-ucode");
	}

	// parse a line printed by pamac-checkupdates --details:
	// source ("repo", "aur" or "flatpak"), name, installed version (empty for a replacer),
	// version and download size separated by tabs
	internal bool parse_update_details (string line, out string source, out string name, out string? installed_version,
										out string version, out uint64 download_size) {
		source = "";
		name = "";
		installed_version = null;
		version = "";
		download_size = 0;
		string[] fields = line.split ("\t");
		if (fields.length != 5 || fields[1] == "") {
			return false;
		}
		source = fields[0];
		name = fields[1];
		installed_version = fields[2] == "" ? null : fields[2];
		version = fields[3];
		return uint64.try_parse (fields[4], out download_size);
	}
}
