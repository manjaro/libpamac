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

namespace Pamac {
	public class Config: Object {
		public string conf_path { get; construct; }
		public uint64 refresh_period { get; set; }
		public bool support_aur { get; private set; }
		public GenericSet<string?> official_repos { get; private set; }
		public bool enable_aur { get; set; }
		PluginLoader<AURPlugin> aur_plugin_loader;
		public bool support_appstream { get; private set; }
		public bool enable_appstream { get; set; }
		PluginLoader<AppstreamPlugin> appstream_plugin_loader;
		public bool support_snap { get; private set; }
		public bool enable_snap { get; set; }
		PluginLoader<SnapPlugin> snap_plugin_loader;
		public bool support_flatpak { get; private set; }
		public bool enable_flatpak { get; set; }
		public bool check_flatpak_updates { get; set; }
		PluginLoader<FlatpakPlugin> flatpak_plugin_loader;
		public string aur_build_dir { get; set; }
		public bool check_aur_updates { get; set; }
		public bool check_aur_vcs_updates { get; set; }
		public bool offline_upgrade { get; set; }
		public uint64 max_parallel_downloads { get; set; }
		public uint64 clean_keep_num_pkgs { get;  set; }
		public bool clean_rm_only_uninstalled { get; set; }
		// Alpm Config
		public GenericSet<string?> ignorepkgs { get {return alpm_config.ignorepkgs;} }

		internal AlpmConfig alpm_config { get; private set; }

		public Config (string conf_path) {
			Object(conf_path: conf_path);
		}

		construct {
			//get environment variables
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			// load aur plugin
			support_aur = false;
			aur_plugin_loader = new PluginLoader<AURPlugin> ("pamac-aur");
			if (aur_plugin_loader.load ()) {
				support_aur = true;
			}
			// load appstream plugin
			support_appstream = false;
			appstream_plugin_loader = new PluginLoader<AppstreamPlugin> ("pamac-appstream");
			if (appstream_plugin_loader.load ()) {
				support_appstream = true;
			}
			// load snap plugin
			support_snap = false;
			snap_plugin_loader = new PluginLoader<SnapPlugin> ("pamac-snap");
			if (snap_plugin_loader.load ()) {
				support_snap = true;
			}
			// load flatpak plugin
			support_flatpak = false;
			flatpak_plugin_loader = new PluginLoader<FlatpakPlugin> ("pamac-flatpak");
			if (flatpak_plugin_loader.load ()) {
				support_flatpak = true;
			}
			reload ();
		}

		public void reload () {
			enable_appstream = support_appstream;
			aur_build_dir = "/var/tmp";
			max_parallel_downloads = 1;
			var directives = parse_file (conf_path);
			official_repos = parse_official_repos (directives.lookup ("OfficialRepos"));
			enable_snap = support_snap && "EnableSnap" in directives;
			enable_flatpak = support_flatpak && "EnableFlatpak" in directives;
			// offline upgrade needs the downloaded updates
			offline_upgrade = "DownloadUpdates" in directives && "OfflineUpgrade" in directives;
			unowned string? val = directives.lookup ("BuildDirectory");
			if (val != null && val != "") {
				aur_build_dir = val;
			}
			val = directives.lookup ("MaxParallelDownloads");
			if (val != null) {
				uint64 number;
				if (uint64.try_parse (val, out number)) {
					// libalpm needs at least one download
					max_parallel_downloads = number.clamp (1, 10);
				} else {
					warning ("ignoring option MaxParallelDownloads: invalid value '%s'", val);
				}
			}
		}

		internal AURPlugin? get_aur_plugin () {
			if (support_aur) {
				return aur_plugin_loader.get_plugin ();
			}
			return null;
		}

		internal AppstreamPlugin? get_appstream_plugin () {
			if (support_appstream) {
				return appstream_plugin_loader.get_plugin ();
			}
			return null;
		}

		internal SnapPlugin? get_snap_plugin () {
			if (support_snap) {
				return snap_plugin_loader.get_plugin ();
			}
			return null;
		}

		internal FlatpakPlugin? get_flatpak_plugin () {
			if (support_flatpak) {
				return flatpak_plugin_loader.get_plugin ();
			}
			return null;
		}

		// directives of the file: key -> value, "" for an option without value
		static HashTable<string, string> parse_file (string path) {
			var directives = new HashTable<string, string> (str_hash, str_equal);
			try {
				var dis = new DataInputStream (File.new_for_path (path).read ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					// split gives an empty array for an empty line
					if (line.length == 0) {
						continue;
					}
					// ignore whole line and end of line comments
					string[] splitted = line.split ("#", 2);
					line = splitted[0].strip ();
					if (line.length == 0) {
						continue;
					}
					splitted = line.split ("=", 2);
					string key = splitted[0].strip ();
					directives.insert (key, splitted.length == 2 ? splitted[1].strip () : "");
				}
			} catch (IOError.NOT_FOUND e) {
				warning ("File '%s' doesn't exist.", path);
			} catch (Error e) {
				warning ("%s: %s", path, e.message);
			}
			return directives;
		}

		// the options written by the clients, in the order to add them
		const string[] BOOLEAN_OPTIONS = {"RemoveUnrequiredDeps", "NoUpdateHideIcon", "EnableDowngrade",
										"SimpleInstall", "EnableAUR", "KeepBuiltPkgs", "CheckAURUpdates",
										"CheckAURVCSUpdates", "OnlyRmUninstalled", "DownloadUpdates",
										"OfflineUpgrade", "EnableSnap", "EnableFlatpak", "CheckFlatpakUpdates"};
		const string[] UINT64_OPTIONS = {"RefreshPeriod", "KeepNumPackages", "MaxParallelDownloads"};
		const string[] STRING_OPTIONS = {"BuildDirectory"};

		public void write (HashTable<string,Variant> received_conf) {
			var expected_types = new HashTable<string, VariantType> (str_hash, str_equal);
			foreach (unowned string key in BOOLEAN_OPTIONS) {
				expected_types.insert (key, VariantType.BOOLEAN);
			}
			foreach (unowned string key in UINT64_OPTIONS) {
				expected_types.insert (key, VariantType.UINT64);
			}
			foreach (unowned string key in STRING_OPTIONS) {
				expected_types.insert (key, VariantType.STRING);
			}
			var new_conf = validate_new_conf (received_conf, expected_types);
			unowned Variant? build_dir = new_conf.lookup ("BuildDirectory");
			if (build_dir != null && !Path.is_absolute (build_dir.get_string ())) {
				warning ("ignoring option BuildDirectory: not an absolute path");
				new_conf.remove ("BuildDirectory");
			}
			// the new lines of the directives to write
			var new_lines = new HashTable<string, string> (str_hash, str_equal);
			var keys = new GenericArray<string> ();
			foreach (unowned string key in BOOLEAN_OPTIONS) {
				unowned Variant? val = new_conf.lookup (key);
				if (val != null) {
					new_lines.insert (key, val.get_boolean () ? key : "#" + key);
				}
				keys.add (key);
			}
			foreach (unowned string key in UINT64_OPTIONS) {
				unowned Variant? val = new_conf.lookup (key);
				if (val != null) {
					new_lines.insert (key, "%s = %llu".printf (key, val.get_uint64 ()));
				}
				keys.add (key);
			}
			foreach (unowned string key in STRING_OPTIONS) {
				unowned Variant? val = new_conf.lookup (key);
				if (val != null) {
					new_lines.insert (key, "%s = %s".printf (key, val.get_string ()));
				}
				keys.add (key);
			}
			write_config_directives (conf_path, new_lines, keys.data, null);
		}
	}
}
