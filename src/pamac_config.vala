/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2026 Guillaume Benoit <guillaume@manjaro.org>
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
	public class Config: Object {
		HashTable<string, string> environment_variables_priv;
		Daemon system_daemon;
		bool _support_aur;
		bool _support_appstream;
		bool _support_snap;
		bool _support_flatpak;
		bool _enable_aur;
		bool _enable_appstream;
		bool _enable_snap;
		bool _enable_flatpak;
		bool _check_aur_updates;
		bool _check_aur_vcs_updates;
		bool _check_flatpak_updates;
		bool _download_updates;
		bool _offline_upgrade;

		public string conf_path { get; construct; }
		public bool recurse { get; set; }
		public bool keep_built_pkgs { get; set; }
		public bool enable_downgrade { get; set; }
		public bool simple_install { get; set; }
		public uint64 refresh_period { get; set; }
		public bool no_update_hide_icon { get; set; }
		public bool support_aur {
			get {
				return _support_aur;
			}
			private set {
				_support_aur = value;
				if (!_support_aur) {
					enable_aur = false;
				}
			}
		}
		public bool enable_aur {
			get {
				return _enable_aur;
			}
			set {
				_enable_aur = _support_aur && value;
				if (!_enable_aur) {
					check_aur_updates = false;
				}
			}
		}
		PluginLoader<AURPlugin> aur_plugin_loader;
		public bool support_appstream {
			get {
				return _support_appstream;
			}
			private set {
				_support_appstream = value;
				if (!_support_appstream) {
					enable_appstream = false;
				}
			}
		}
		public bool enable_appstream {
			get {
				return _enable_appstream;
			}
			set {
				_enable_appstream = _support_appstream && value;
			}
		}
		PluginLoader<AppstreamPlugin> appstream_plugin_loader;
		public bool support_snap {
			get {
				return _support_snap;
			}
			private set {
				_support_snap = value;
				if (!_support_snap) {
					enable_snap = false;
				}
			}
		}
		public bool enable_snap {
			get {
				return _enable_snap;
			}
			set {
				_enable_snap = _support_snap && value;
			}
		}
		PluginLoader<SnapPlugin> snap_plugin_loader;
		public bool support_flatpak {
			get {
				return _support_flatpak;
			}
			private set {
				_support_flatpak = value;
				if (!_support_flatpak) {
					enable_flatpak = false;
				}
			}
		}
		public bool enable_flatpak {
			get {
				return _enable_flatpak;
			}
			set {
				_enable_flatpak = _support_flatpak && value;
				if (!_enable_flatpak) {
					check_flatpak_updates = false;
				}
			}
		}
		public bool check_flatpak_updates {
			get {
				return _check_flatpak_updates;
			}
			set {
				_check_flatpak_updates = _enable_flatpak && value;
			}
		}
		PluginLoader<FlatpakPlugin> flatpak_plugin_loader;
		public string aur_build_dir { get; set; }
		// the repositories of the distribution, the others are added by the user
		public GenericSet<string?> official_repos { get; private set; }
		public bool check_aur_updates {
			get {
				return _check_aur_updates;
			}
			set {
				_check_aur_updates = _enable_aur && value;
				if (!_check_aur_updates) {
					check_aur_vcs_updates = false;
				}
			}
		}
		public bool check_aur_vcs_updates {
			get {
				return _check_aur_vcs_updates;
			}
			set {
				_check_aur_vcs_updates = _check_aur_updates && value;
			}
		}
		public bool download_updates {
			get {
				return _download_updates;
			}
			set {
				_download_updates = value;
				if (!_download_updates) {
					offline_upgrade = false;
				}
			}
		}
		public bool offline_upgrade {
			get {
				return _offline_upgrade;
			}
			set {
				_offline_upgrade = _download_updates && value;
			}
		}
		public uint64 max_parallel_downloads { get; set; }
		public uint64 clean_keep_num_pkgs { get;  set; }
		public bool clean_rm_only_uninstalled { get; set; }
		public HashTable<string, string> environment_variables { get {return environment_variables_priv;} }
		// Alpm Config
		public string db_path { get { return alpm_config.dbpath; } }
		public bool checkspace { get {return alpm_config.checkspace;}
								set {alpm_config.checkspace = value;} }
		public GenericSet<string?> ignorepkgs { get {return alpm_config.ignorepkgs;} }

		internal AlpmConfig alpm_config { get; private set; }

		public Config (string conf_path) {
			Object(conf_path: conf_path);
		}

		construct {
			//get environment variables
			environment_variables_priv = new HashTable<string, string> (str_hash, str_equal);
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			foreach (unowned string name in new string[] {"http_proxy", "https_proxy", "ftp_proxy", "socks_proxy", "no_proxy"}) {
				unowned string? variable = Environment.get_variable (name);
				if (variable != null) {
					environment_variables_priv.insert (name, variable);
				}
			}
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

		public void add_ignorepkg (string name) {
			alpm_config.ignorepkgs.add (name);
		}

		public void remove_ignorepkg (string name) {
			alpm_config.ignorepkgs.remove (name);
		}

		public void reload () {
			// alpm config
			alpm_config.reload ();
			// set default options, the boolean ones are set from the file below
			refresh_period = 6;
			enable_appstream = true;
			aur_build_dir = "/var/tmp";
			max_parallel_downloads = 1;
			clean_keep_num_pkgs = 3;
			var directives = parse_file (conf_path);
			official_repos = parse_official_repos (directives.lookup ("OfficialRepos"));
			// apply the options after the ones they depend on,
			// whatever their order in the file
			recurse = "RemoveUnrequiredDeps" in directives;
			enable_downgrade = "EnableDowngrade" in directives;
			simple_install = "SimpleInstall" in directives;
			clean_rm_only_uninstalled = "OnlyRmUninstalled" in directives;
			no_update_hide_icon = "NoUpdateHideIcon" in directives;
			keep_built_pkgs = "KeepBuiltPkgs" in directives;
			enable_aur = "EnableAUR" in directives;
			check_aur_updates = "CheckAURUpdates" in directives;
			check_aur_vcs_updates = "CheckAURVCSUpdates" in directives;
			enable_snap = "EnableSnap" in directives;
			enable_flatpak = "EnableFlatpak" in directives;
			check_flatpak_updates = "CheckFlatpakUpdates" in directives;
			download_updates = "DownloadUpdates" in directives;
			offline_upgrade = "OfflineUpgrade" in directives;
			unowned string? val = directives.lookup ("BuildDirectory");
			if (val != null && val != "") {
				aur_build_dir = val;
			}
			uint64 number;
			if (parse_number (directives, "RefreshPeriod", out number)) {
				// check updates at least once a week
				refresh_period = uint64.min (number, 168);
			}
			if (parse_number (directives, "KeepNumPackages", out number)) {
				clean_keep_num_pkgs = number;
			}
			if (parse_number (directives, "MaxParallelDownloads", out number)) {
				// libalpm needs at least one download
				max_parallel_downloads = number.clamp (1, 10);
			}
		}

		static bool parse_number (HashTable<string, string> directives, string key, out uint64 number) {
			number = 0;
			unowned string? val = directives.lookup (key);
			if (val == null) {
				return false;
			}
			if (!uint64.try_parse (val, out number)) {
				warning ("ignoring option %s: invalid value '%s'", key, val);
				return false;
			}
			return true;
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

		public void save () {
			if (system_daemon == null) {
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
					// the writes wait for the authorization
					disable_timeout (system_daemon);
				} catch (Error e) {
					warning ("save pamac config error: %s", e.message);
					return;
				}
			}
			// write pamac config
			var new_pamac_conf = new HashTable<string, Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RemoveUnrequiredDeps", new Variant.boolean (recurse));
			new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (refresh_period));
			new_pamac_conf.insert ("NoUpdateHideIcon", new Variant.boolean (no_update_hide_icon));
			new_pamac_conf.insert ("DownloadUpdates", new Variant.boolean (download_updates));
			new_pamac_conf.insert ("OfflineUpgrade", new Variant.boolean (offline_upgrade));
			new_pamac_conf.insert ("EnableDowngrade", new Variant.boolean (enable_downgrade));
			new_pamac_conf.insert ("SimpleInstall", new Variant.boolean (simple_install));
			new_pamac_conf.insert ("MaxParallelDownloads", new Variant.uint64 (max_parallel_downloads));
			new_pamac_conf.insert ("KeepNumPackages", new Variant.uint64 (clean_keep_num_pkgs));
			new_pamac_conf.insert ("OnlyRmUninstalled", new Variant.boolean (clean_rm_only_uninstalled));
			// the options of a missing plugin are forced to false:
			// do not overwrite the ones of the file
			if (support_aur) {
				new_pamac_conf.insert ("EnableAUR", new Variant.boolean (enable_aur));
				new_pamac_conf.insert ("KeepBuiltPkgs", new Variant.boolean (keep_built_pkgs));
				new_pamac_conf.insert ("CheckAURUpdates", new Variant.boolean (check_aur_updates));
				new_pamac_conf.insert ("CheckAURVCSUpdates", new Variant.boolean (check_aur_vcs_updates));
				new_pamac_conf.insert ("BuildDirectory", new Variant.string (aur_build_dir));
			}
			if (support_snap) {
				new_pamac_conf.insert ("EnableSnap", new Variant.boolean (enable_snap));
			}
			if (support_flatpak) {
				new_pamac_conf.insert ("EnableFlatpak", new Variant.boolean (enable_flatpak));
				new_pamac_conf.insert ("CheckFlatpakUpdates", new Variant.boolean (check_flatpak_updates));
			}
			system_daemon.write_pamac_config.begin (new_pamac_conf, (obj, res) => {
				try {
					system_daemon.write_pamac_config.end (res);
				} catch (Error e) {
					warning ("save pamac config error: %s", e.message);
				}
			});
			// write alpm config
			var new_alpm_conf = new HashTable<string, Variant> (str_hash, str_equal);
			new_alpm_conf.insert ("CheckSpace", new Variant.boolean (checkspace));
			var ignorepkgs_str = new StringBuilder ();
			foreach (unowned string name in ignorepkgs) {
				if (ignorepkgs_str.len > 0) {
					ignorepkgs_str.append (" ");
				}
				ignorepkgs_str.append (name);
			}
			new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkgs_str.str));
			system_daemon.write_alpm_config.begin (new_alpm_conf, (obj, res) => {
				try {
					system_daemon.write_alpm_config.end (res);
				} catch (Error e) {
					warning ("save alpm config error: %s", e.message);
				}
			});
		}
	}
}
