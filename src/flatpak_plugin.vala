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
	internal class FlatpakPackageLinked : FlatpakPackage {
		// common
		Flatpak.InstalledRef? installed_ref;
		Flatpak.RemoteRef? remote_ref;
		AppStream.Component? as_app;
		string? appstream_dir;
		// Package
		string _name;
		string _id;
		unowned string _version;
		unowned string? _installed_version;
		unowned string? _app_name;
		string? _long_desc;
		bool _long_desc_loaded;
		unowned string? _launchable;
		string? _icon;
		GenericArray<string> _screenshots;

		// Package
		public override string name {
			get { return _name; }
			internal set { /* not used */ }
		}
		public override string id {
			get { return _id; }
			internal set { /* not used */ }
		}
		public override string version {
			get { return _version; }
			internal set { /* not used */ }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { /* not used */ }
		}
		public override string? repo {
			get {
				if (installed_ref != null) {
					return installed_ref.get_origin ();
				} else if (remote_ref != null) {
					return remote_ref.remote_name;
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? license {
			get {
				if (as_app != null) {
					return as_app.get_project_license ();
				}
				return null;
			}
		}
		public override string? url {
			get {
				if (as_app != null) {
					return as_app.get_url (AppStream.UrlKind.HOMEPAGE);
				}
				return null;
			}
		}
		public override uint64 installed_size {
			get {
				if (installed_ref != null) {
					return installed_ref.get_installed_size ();
				} else if (remote_ref != null) {
					return remote_ref.get_installed_size ();
				}
				return 0;
			}
		}
		public override uint64 download_size {
			get {
				if (remote_ref != null) {
					return remote_ref.download_size;
				}
				return 0;
			}
		}
		public override DateTime? install_date {
			get { return null; }
		}
		public override string? app_name {
			get {
				if (_app_name == null && as_app != null) {
					_app_name = as_app.get_name ();
				}
				return _app_name;
			}
		}
		public override string? app_id {
			get {
				if (as_app != null) {
					return as_app.get_id ();
				}
				return null;
			}
		}
		public override string? desc {
			get {
				if (as_app != null) {
					return as_app.get_summary ();
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? long_desc {
			get {
				if (!_long_desc_loaded && as_app != null) {
					// only try once, even if the conversion fails
					_long_desc_loaded = true;
					_long_desc = get_markdown_description (as_app);
				}
				return _long_desc;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && as_app != null) {
					_launchable = get_first_desktop_launchable (as_app);
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null && as_app != null && appstream_dir != null) {
					unowned AppStream.Icon? as_icon = get_best_cached_icon (as_app);
					if (as_icon != null) {
						uint size = as_icon.get_height ();
						_icon = Path.build_filename (appstream_dir, "icons", "%ux%u".printf (size, size), as_icon.get_name ());
					}
				}
				return _icon;
			}
		}
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					if (as_app != null) {
						unowned GenericArray<AppStream.Screenshot> as_screenshots = as_app.get_screenshots_all ();
						foreach (unowned AppStream.Screenshot as_screenshot in as_screenshots) {
							// get a url with small image,
							// a screenshot can have no image (e.g. a video)
							unowned AppStream.Image? as_image = as_screenshot.get_image (500, 300, 1);
							if (as_image == null) {
								continue;
							}
							unowned string? url = as_image.get_url ();
							if (url != null) {
								_screenshots.add (url);
							}
						}
					}
				}
				return _screenshots;
			}
		}

		internal FlatpakPackageLinked (Flatpak.InstalledRef? installed_ref, Flatpak.RemoteRef? remote_ref, AppStream.Component? as_app, string? appstream_dir, bool is_update = false) {
			this.installed_ref = installed_ref;
			this.remote_ref = remote_ref;
			this.as_app = as_app;
			this.appstream_dir = appstream_dir;
			if (installed_ref != null) {
				_id = "%s/%s".printf (installed_ref.get_origin (), installed_ref.format_ref ());
				_name = installed_ref.name;
				_installed_version = installed_ref.get_appdata_version ();
				if (_installed_version == null) {
					// use commits
					_installed_version = installed_ref.get_commit ();
				}
				if (is_update) {
					_version = get_stable_release_version ();
					if (_version == null) {
						_version = installed_ref.get_latest_commit ();
					}
				}
				if (_version == null) {
					_version = _installed_version;
				}
			} else if (remote_ref != null) {
				_id = "%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ());
				_name = remote_ref.get_name ();
				_version = get_stable_release_version ();
				if (_version == null) {
					_version = remote_ref.get_commit ();
				}
			}
		}

		unowned string? get_stable_release_version () {
			if (as_app == null) {
				return null;
			}
			unowned GenericArray<AppStream.Release> as_releases = as_app.get_releases_plain ().get_entries ();
			foreach (unowned AppStream.Release as_release in as_releases) {
				if (as_release.get_kind () == AppStream.ReleaseKind.STABLE) {
					return as_release.get_version ();
				}
			}
			return null;
		}
	}

	internal class FlatPak: Object, FlatpakPlugin {
		const string[] FEATURED_APP_IDS = {
			"com.spotify.Client",
			"com.valvesoftware.Steam",
			"com.discordapp.Discord",
			"com.mojang.Minecraft",
			"com.slack.Slack"
		};

		string sender;
		Flatpak.Installation? installation;
		Cancellable cancellable;
		// appstream data is loaded in background, see load_appstream_data ()
		Mutex load_mutex;
		Cond load_cond;
		bool loading;
		bool loaded;
		// avoid downloading appstream data twice at the same time
		Mutex refresh_mutex;
		// not loaded, only used to build search tokens
		AppStream.Pool search_pool;
		// all the following data is protected by lock (pkgs_cache)
		HashTable<string, FlatpakPackageLinked> pkgs_cache;
		// appstream data, replaced as a whole when reloaded
		// key: remote/kind/name/arch/branch
		HashTable<string, AppStream.Component> apps_table;
		// key: app id without .desktop suffix, value: apps_table key
		HashTable<string, string> app_ids_table;
		HashTable<string, HashTable<string, AppStream.Component>> categories_table;
		HashTable<string, Flatpak.RemoteRef> remote_refs_table;
		// refs not found in remotes caches, to not look for them again
		GenericSet<string> missing_refs;
		// key: remote name, value: appstream dir path
		HashTable<string, string> appstream_dirs;
		// returned unowned to callers so never removed
		GenericArray<string> remotes_names;

		public uint64 refresh_period { get; set; }

		public FlatPak (uint64 refresh_period) {
			Object (refresh_period: refresh_period);
		}

		construct {
			cancellable = new Cancellable ();
			search_pool = new AppStream.Pool ();
			pkgs_cache = new HashTable<string, FlatpakPackageLinked> (str_hash, str_equal);
			apps_table = new HashTable<string, AppStream.Component> (str_hash, str_equal);
			app_ids_table = new HashTable<string, string> (str_hash, str_equal);
			categories_table = new HashTable<string, HashTable<string, AppStream.Component>> (str_hash, str_equal);
			remote_refs_table = new HashTable<string, Flatpak.RemoteRef> (str_hash, str_equal);
			missing_refs = new GenericSet<string> (str_hash, str_equal);
			appstream_dirs = new HashTable<string, string> (str_hash, str_equal);
			remotes_names = new GenericArray<string> ();
			try {
				installation = new Flatpak.Installation.system ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		// do not slow down startup: parse appstream data in background,
		// then download it if needed and reload it
		public void load_appstream_data () {
			load_mutex.lock ();
			if (loading || loaded) {
				load_mutex.unlock ();
				return;
			}
			loading = true;
			load_mutex.unlock ();
			try {
				new Thread<int>.try ("load_flatpak_appstream_data", () => {
					reload_appstream_data ();
					set_loaded ();
					refresh_appstream_data ();
					return 0;
				});
			} catch (Error e) {
				warning (e.message);
				reload_appstream_data ();
				set_loaded ();
			}
		}

		void set_loaded () {
			load_mutex.lock ();
			loading = false;
			loaded = true;
			load_cond.broadcast ();
			load_mutex.unlock ();
		}

		// wait for the first load, if started, before using appstream data
		void wait_loaded () {
			load_mutex.lock ();
			while (loading) {
				load_cond.wait (load_mutex);
			}
			load_mutex.unlock ();
		}

		public bool refresh_appstream_data () {
			refresh_mutex.lock ();
			bool modified = refresh_appstream_files ();
			refresh_mutex.unlock ();
			if (modified) {
				reload_appstream_data ();
			}
			return modified;
		}

		GenericArray<unowned Flatpak.Remote> list_enabled_remotes () {
			var enabled_remotes = new GenericArray<unowned Flatpak.Remote> ();
			if (installation == null) {
				return enabled_remotes;
			}
			try {
				// keep remotes alive while returned
				enabled_remotes = installation.list_remotes ();
				for (uint i = enabled_remotes.length; i > 0; i--) {
					if (enabled_remotes[i - 1].get_disabled ()) {
						enabled_remotes.remove_index (i - 1);
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return enabled_remotes;
		}

		// download appstream data if older than refresh period, returns true if any was downloaded
		bool refresh_appstream_files () {
			bool modified = false;
			foreach (unowned Flatpak.Remote remote in list_enabled_remotes ()) {
				if (refresh_remote_appstream_data (remote)) {
					modified = true;
				}
			}
			return modified;
		}

		int64 get_file_age (File file) {
			try {
				FileInfo info = file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
				DateTime last_modifed = info.get_modification_date_time ();
				var now = new DateTime.now_utc ();
				TimeSpan elapsed_time = now.difference (last_modifed);
				return elapsed_time;
			} catch (IOError.NOT_FOUND e) {
				// never downloaded
				return int64.MAX;
			} catch (Error e) {
				warning (e.message);
				return int64.MAX;
			}
		}

		bool refresh_remote_appstream_data (Flatpak.Remote remote) {
			int64 elapsed_time = get_file_age (remote.get_appstream_timestamp (null));
			if (elapsed_time < TimeSpan.HOUR) {
				return false;
			}
			int64 elapsed_hours = elapsed_time / TimeSpan.HOUR;
			if (elapsed_hours <= refresh_period) {
				return false;
			}
			unowned string remote_name = remote.get_name ();
			message ("refreshing %s appstream data", remote_name);
			try {
				installation.update_appstream_sync (remote_name, null, null);
				return true;
			} catch (Error e) {
				warning (e.message);
				return false;
			}
		}

		// parse appstream data on disk and replace the data in memory
		void reload_appstream_data () {
			var apps = new HashTable<string, AppStream.Component> (str_hash, str_equal);
			var app_ids = new HashTable<string, string> (str_hash, str_equal);
			var categories = new HashTable<string, HashTable<string, AppStream.Component>> (str_hash, str_equal);
			foreach (unowned string category in MAIN_CATEGORIES) {
				categories.insert (category, new HashTable<string, AppStream.Component> (str_hash, str_equal));
			}
			var remote_refs = new HashTable<string, Flatpak.RemoteRef> (str_hash, str_equal);
			var dirs = new HashTable<string, string> (str_hash, str_equal);
			foreach (unowned Flatpak.Remote remote in list_enabled_remotes ()) {
				unowned string remote_name = remote.get_name ();
				File appstream_dir = remote.get_appstream_dir (null);
				dirs.insert (remote_name, appstream_dir.get_path ());
				// errors are handled per remote to load the other ones
				load_remote_apps (remote_name, appstream_dir, apps, app_ids, categories);
				load_remote_refs (remote_name, remote_refs);
			}
			lock (pkgs_cache) {
				apps_table = apps;
				app_ids_table = app_ids;
				categories_table = categories;
				remote_refs_table = remote_refs;
				appstream_dirs = dirs;
				missing_refs.remove_all ();
			}
		}

		void load_remote_apps (string remote_name,
								File appstream_dir,
								HashTable<string, AppStream.Component> apps,
								HashTable<string, string> app_ids,
								HashTable<string, HashTable<string, AppStream.Component>> categories) {
			var mdata = new AppStream.Metadata ();
			mdata.set_format_style (AppStream.FormatStyle.CATALOG);
			try {
				mdata.parse_file (appstream_dir.get_child ("appstream.xml"), AppStream.FormatKind.XML);
			} catch (IOError.NOT_FOUND e) {
				return;
			} catch (Error e) {
				warning ("%s: %s", remote_name, e.message);
				return;
			}
			unowned GenericArray<AppStream.Component> as_apps = mdata.get_components ().as_array ();
			foreach (unowned AppStream.Component as_app in as_apps) {
				if (as_app.get_kind () != AppStream.ComponentKind.DESKTOP_APP) {
					continue;
				}
				unowned AppStream.Bundle? bundle = as_app.get_bundle (AppStream.BundleKind.FLATPAK);
				if (bundle == null) {
					continue;
				}
				string id = "%s/%s".printf (remote_name, bundle.get_id ());
				apps.insert (id, as_app);
				// first remote wins
				string app_id = normalize_app_id (as_app.get_id ());
				if (!app_ids.contains (app_id)) {
					app_ids.insert ((owned) app_id, id);
				}
				unowned GenericArray<string> as_categories = as_app.get_categories ();
				foreach (unowned string cat in as_categories) {
					unowned string? main_category = get_main_category (cat);
					if (main_category != null) {
						categories.lookup (main_category).insert (id, as_app);
					}
				}
			}
		}

		void load_remote_refs (string remote_name, HashTable<string, Flatpak.RemoteRef> remote_refs) {
			try {
				GenericArray<unowned Flatpak.RemoteRef> refs = installation.list_remote_refs_sync_full (remote_name, Flatpak.QueryFlags.ONLY_CACHED);
				foreach (unowned Flatpak.RemoteRef remote_ref in refs) {
					if (remote_ref.get_kind () == Flatpak.RefKind.APP) {
						remote_refs.insert ("%s/%s".printf (remote_name, remote_ref.format_ref ()), remote_ref);
					}
				}
			} catch (Error e) {
				warning ("%s: %s", remote_name, e.message);
			}
		}

		static string normalize_app_id (string app_id) {
			if (app_id.has_suffix (".desktop")) {
				return app_id.substring (0, app_id.length - ".desktop".length);
			}
			return app_id;
		}

		public void get_remotes_names (ref GenericArray<unowned string> names) {
			GenericArray<unowned Flatpak.Remote> remotes = list_enabled_remotes ();
			lock (pkgs_cache) {
				foreach (unowned Flatpak.Remote remote in remotes) {
					unowned string remote_name = remote.get_name ();
					uint index;
					if (!remotes_names.find_with_equal_func (remote_name, str_equal, out index)) {
						remotes_names.add (remote_name);
						index = remotes_names.length - 1;
					}
					names.add (remotes_names[index]);
				}
			}
		}

		// lock (pkgs_cache) must be held
		Flatpak.RemoteRef? lookup_remote_ref (string id, string remote, string name, string arch, string branch) {
			Flatpak.RemoteRef? remote_ref = remote_refs_table.lookup (id);
			if (remote_ref != null || id in missing_refs) {
				return remote_ref;
			}
			try {
				// do not use network
				remote_ref = installation.fetch_remote_ref_sync_full (remote, Flatpak.RefKind.APP, name, arch, branch, Flatpak.QueryFlags.ONLY_CACHED);
				remote_refs_table.insert (id, remote_ref);
			} catch (Error e) {
				if (!(e is Flatpak.Error.REF_NOT_FOUND)) {
					warning (e.message);
				}
				missing_refs.add (id);
			}
			return remote_ref;
		}

		// lock (pkgs_cache) must be held
		unowned FlatpakPackageLinked? get_or_create_pkg (string id) {
			unowned FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
			if (pkg != null || installation == null) {
				return pkg;
			}
			string[] splitted = id.split ("/", 5);
			// expected id: remote/kind/name/arch/branch
			if (splitted.length != 5) {
				return null;
			}
			unowned string remote = splitted[0];
			unowned string name = splitted[2];
			unowned string arch = splitted[3];
			unowned string branch = splitted[4];
			FlatpakPackageLinked new_pkg;
			try {
				Flatpak.InstalledRef installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
				unowned string origin = installed_ref.get_origin ();
				// prefer appstream data from the remote it was installed from
				unowned AppStream.Component? as_app = apps_table.lookup ("%s/%s".printf (origin, installed_ref.format_ref ()));
				if (as_app == null) {
					as_app = apps_table.lookup (id);
				}
				new_pkg = new FlatpakPackageLinked (installed_ref, null, as_app, appstream_dirs.lookup (origin));
			} catch (Error e) {
				if (!(e is Flatpak.Error.NOT_INSTALLED)) {
					warning (e.message);
					return null;
				}
				Flatpak.RemoteRef? remote_ref = lookup_remote_ref (id, remote, name, arch, branch);
				if (remote_ref == null) {
					return null;
				}
				new_pkg = new FlatpakPackageLinked (null, remote_ref, apps_table.lookup (id), appstream_dirs.lookup (remote));
			}
			pkg = new_pkg;
			pkgs_cache.insert (id, (owned) new_pkg);
			return pkg;
		}

		public void get_installed_flatpaks (ref GenericArray<unowned FlatpakPackage> pkgs) {
			if (installation == null) {
				return;
			}
			wait_loaded ();
			try {
				GenericArray<unowned Flatpak.InstalledRef> installed_apps = installation.list_installed_refs_by_kind (Flatpak.RefKind.APP);
				lock (pkgs_cache) {
					foreach (unowned Flatpak.InstalledRef installed_ref in installed_apps) {
						unowned string origin = installed_ref.get_origin ();
						string id = "%s/%s".printf (origin, installed_ref.format_ref ());
						unowned FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
						if (pkg == null) {
							var new_pkg = new FlatpakPackageLinked (installed_ref, null, apps_table.lookup (id), appstream_dirs.lookup (origin));
							pkg = new_pkg;
							pkgs_cache.insert ((owned) id, (owned) new_pkg);
						}
						pkgs.add (pkg);
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public bool is_installed_flatpak (string id) {
			if (installation == null) {
				return false;
			}
			string[] splitted = id.split ("/", 5);
			// expected id: remote/kind/name/arch/branch
			if (splitted.length != 5) {
				return false;
			}
			unowned string name = splitted[2];
			unowned string arch = splitted[3];
			unowned string branch = splitted[4];
			try {
				installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
				return true;
			} catch (Error e) {
				if (!(e is Flatpak.Error.NOT_INSTALLED)) {
					warning (e.message);
				}
				return false;
			}
		}

		public unowned FlatpakPackage? get_flatpak_by_app_id (string app_id) {
			wait_loaded ();
			lock (pkgs_cache) {
				unowned string? id = app_ids_table.lookup (normalize_app_id (app_id));
				if (id == null) {
					return null;
				}
				return get_or_create_pkg (id);
			}
		}

		public unowned FlatpakPackage? get_flatpak (string id) {
			wait_loaded ();
			lock (pkgs_cache) {
				return get_or_create_pkg (id);
			}
		}

		public void search_flatpaks (string search_string, ref GenericArray<unowned FlatpakPackage> pkgs) {
			string[] tokens = get_search_tokens (search_string.split (" "));
			if (tokens.length == 0) {
				return;
			}
			string[] stemmed_tokens = get_stemmed_search_tokens (search_pool, tokens);
			wait_loaded ();
			lock (pkgs_cache) {
				var iter = HashTableIter<string, AppStream.Component> (apps_table);
				unowned string id;
				unowned AppStream.Component as_app;
				while (iter.next (out id, out as_app)) {
					if (as_app.search_matches_all (stemmed_tokens) > 0 || id_matches_all (as_app.get_id (), tokens)) {
						unowned FlatpakPackage? pkg = get_or_create_pkg (id);
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
				}
			}
		}

		public void get_category_flatpaks (string category, ref GenericArray<unowned FlatpakPackage> pkgs) {
			wait_loaded ();
			lock (pkgs_cache) {
				if (category == "Featured") {
					foreach (unowned string app_id in FEATURED_APP_IDS) {
						unowned string? id = app_ids_table.lookup (app_id);
						if (id == null) {
							continue;
						}
						unowned FlatpakPackage? pkg = get_or_create_pkg (id);
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
					return;
				}
				unowned HashTable<string, AppStream.Component>? category_apps = categories_table.lookup (category);
				if (category_apps == null) {
					return;
				}
				var iter = HashTableIter<string, AppStream.Component> (category_apps);
				unowned string id;
				while (iter.next (out id, null)) {
					unowned FlatpakPackage? pkg = get_or_create_pkg (id);
					if (pkg != null) {
						pkgs.add (pkg);
					}
				}
			}
		}

		public void get_flatpak_updates (ref GenericArray<FlatpakPackage> pkgs) {
			if (installation == null) {
				return;
			}
			try {
				// can use network, do not hold the lock
				GenericArray<unowned Flatpak.InstalledRef> update_refs = installation.list_installed_refs_for_update ();
				wait_loaded ();
				lock (pkgs_cache) {
					foreach (unowned Flatpak.InstalledRef installed_ref in update_refs) {
						if (installed_ref.kind != Flatpak.RefKind.APP && installed_ref.kind != Flatpak.RefKind.RUNTIME) {
							continue;
						}
						unowned string origin = installed_ref.get_origin ();
						string id = "%s/%s".printf (origin, installed_ref.format_ref ());
						// not cached: the version differs from the installed package one
						pkgs.add (new FlatpakPackageLinked (installed_ref, null, apps_table.lookup (id), appstream_dirs.lookup (origin), true));
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		bool on_add_new_remote (Flatpak.TransactionRemoteReason reason, string from_id, string remote_name, string url) {
			// additional applications
			if (reason == Flatpak.TransactionRemoteReason.GENERIC_REPO) {
				do_emit_script_output ("Configuring %s as new generic remote".printf (url));
				return true;
			}
			// runtime deps always make sense
			if (reason == Flatpak.TransactionRemoteReason.RUNTIME_DEPS) {
				do_emit_script_output ("Configuring %s as new remote for deps".printf (url));
				return true;
			}
			return false;
		}

		int on_choose_remote_for_ref (string for_ref, string runtime_ref, [CCode (array_length = false, array_null_terminated = true)] string[] remotes) {
			// use the first remote
			do_emit_script_output ("Using %s as provider for %s".printf (remotes[0], runtime_ref));
			return 0;
		}

		static string? get_operation_action (Flatpak.TransactionOperation operation) {
			switch (operation.get_operation_type ()) {
				case Flatpak.TransactionOperationType.INSTALL:
					return dgettext (null, "Installing %s").printf (operation.get_ref ());
				case Flatpak.TransactionOperationType.UNINSTALL:
					return dgettext (null, "Removing %s").printf (operation.get_ref ());
				case Flatpak.TransactionOperationType.UPDATE:
					return dgettext (null, "Upgrading %s").printf (operation.get_ref ());
				default:
					return null;
			}
		}

		void on_new_operation (Flatpak.TransactionOperation operation, Flatpak.TransactionProgress progress) {
			string? action = get_operation_action (operation);
			if (action == null) {
				return;
			}
			do_emit_action_progress (action, progress.get_status (), 0);
			progress.changed.connect (() => {
				if (progress.get_is_estimating ()) {
					return;
				}
				if (progress.get_progress () == 100) {
					do_emit_script_output (progress.get_status ());
					do_emit_action_progress (action, "", 1);
				} else {
					do_emit_action_progress (action, progress.get_status (), (double) progress.get_progress () / 100);
				}
			});
			progress.set_update_frequency (100);
		}

		bool on_operation_error (Flatpak.TransactionOperation operation, Error error, Flatpak.TransactionErrorDetails detail) {
			do_emit_script_output (error.message);
			return true;
		}

		void do_emit_action_progress (string action, string status, double progress) {
			emit_action_progress (sender, action, status, progress);
		}

		void do_emit_script_output (string message) {
			emit_script_output (sender, message);
		}

		void do_emit_error (string message, string[] details) {
			emit_error (sender, message, details);
		}

		static bool valid_ids (string[] ids) {
			foreach (unowned string id in ids) {
				string[] splitted = id.split ("/", 2);
				if (splitted.length != 2 || splitted[0].length == 0 || splitted[1].length == 0) {
					return false;
				}
			}
			return true;
		}

		public bool trans_run (string sender, string[] to_install, string[] to_remove, string[] to_upgrade) {
			this.sender = sender;
			cancellable.reset ();
			if (installation == null) {
				do_emit_error (dgettext (null, "Flatpak transaction failed"), {"no flatpak installation"});
				return false;
			}
			// ids received from the client must be remote/ref
			if (!valid_ids (to_install) || !valid_ids (to_remove) || !valid_ids (to_upgrade)) {
				do_emit_error (dgettext (null, "Flatpak transaction failed"), {"invalid flatpak id"});
				return false;
			}
			try {
				var transaction = new Flatpak.Transaction.for_installation (installation, cancellable);
				foreach (unowned string id in to_install) {
					string[] splitted = id.split ("/", 2);
					transaction.add_install (splitted[0], splitted[1], null);
				}
				foreach (unowned string id in to_remove) {
					transaction.add_uninstall (id.split ("/", 2)[1]);
				}
				foreach (unowned string id in to_upgrade) {
					transaction.add_update (id.split ("/", 2)[1], null, null);
				}
				if (to_upgrade.length > 0) {
					// add runtime updates
					GenericArray<unowned Flatpak.InstalledRef> update_refs = installation.list_installed_refs_for_update ();
					foreach (unowned Flatpak.InstalledRef installed_ref in update_refs) {
						if (installed_ref.kind == Flatpak.RefKind.RUNTIME) {
							transaction.add_update (installed_ref.format_ref (), null, null);
						}
					}
				}
				transaction.ready.connect (() => { return true; });
				transaction.add_new_remote.connect (on_add_new_remote);
				transaction.choose_remote_for_ref.connect (on_choose_remote_for_ref);
				transaction.new_operation.connect (on_new_operation);
				transaction.operation_error.connect (on_operation_error);
				bool success = transaction.run (cancellable);
				refresh ();
				return success;
			} catch (Error e) {
				do_emit_error (dgettext (null, "Flatpak transaction failed"), {e.message});
				return false;
			}
		}

		public void trans_cancel (string sender) {
			if (sender == this.sender) {
				cancellable.cancel ();
			}
		}

		public void refresh () {
			lock (pkgs_cache) {
				pkgs_cache.remove_all ();
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.FlatPak);
}
