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
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {
	internal class FlatpakPackageLinked : FlatpakPackage {
		// common
		Flatpak.InstalledRef? installed_ref;
		Flatpak.RemoteRef? remote_ref;
		AppStream.Component? as_app;
		Flatpak.Installation installation;
		// Package
		string _name;
		string _id;
		unowned string? _version;
		unowned string? _installed_version;
		unowned string? _app_name;
		string? _long_desc;
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
			internal set { _version = value; }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { _installed_version = value; }
		}
		public override string? repo {
			get {
//~ 				return as_app.get_origin ();
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
				if (_app_name == null) {
					if (as_app != null) {
						_app_name = as_app.get_name ();
					}
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
				if (_long_desc == null) {
					if (as_app != null) {
						try {
							_long_desc = AppStream.markup_convert_simple (as_app.get_description ());
						} catch (Error e) {
							warning (e.message);
						}
					}
				}
				return _long_desc;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && as_app != null) {
					unowned AppStream.Launchable? as_launchable = as_app.get_launchable (AppStream.LaunchableKind.DESKTOP_ID);
					if (as_launchable != null) {
						unowned GenericArray<string> entries = as_launchable.get_entries ();
						foreach (unowned string entry in entries) {
							_launchable = entry;
							// get first one in the list
							break;
						}
					}
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null && as_app != null) {
					unowned GenericArray<AppStream.Icon> icons = as_app.get_icons ();
					foreach (unowned AppStream.Icon as_icon in icons) {
						if (as_icon.get_kind () == AppStream.IconKind.CACHED) {
							if (as_icon.get_height () == 64) {
								try {
									GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
									foreach (unowned Flatpak.Remote remote in remotes) {
										if (remote.get_disabled ()) {
											continue;
										}
										if (remote.get_name () == repo) {
											File appstream_dir = remote.get_appstream_dir (null);
											_icon = Path.build_filename (appstream_dir.get_path (), "icons", "64x64", as_icon.get_name ());
											break;
										}
									}
								} catch (Error e) {
									warning (e.message);
								}
							}
						}
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
						unowned GenericArray<AppStream.Screenshot> as_screenshots = as_app.get_screenshots ();
						foreach (unowned AppStream.Screenshot as_screenshot in as_screenshots) {
							// get a url with small image 
							unowned AppStream.Image as_image = as_screenshot.get_image (500, 300);
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

		internal FlatpakPackageLinked (Flatpak.InstalledRef? installed_ref, Flatpak.RemoteRef? remote_ref, AppStream.Component? as_app, Flatpak.Installation installation, bool is_update = false) {
			this.installed_ref = installed_ref;
			this.remote_ref = remote_ref;
			this.as_app = as_app;
			this.installation = installation;
			if (this.installed_ref != null) {
				_id = "%s/%s".printf (installed_ref.get_origin (), installed_ref.format_ref ());
				_name = installed_ref.name;
				_installed_version = installed_ref.appdata_version;
				if (_installed_version == null) {
					// use commits
					_installed_version = installed_ref.commit;
				}
				if (is_update && this.as_app != null) {
					unowned GenericArray<AppStream.Release> as_releases = as_app.get_releases ();
					foreach (unowned AppStream.Release as_release in as_releases) {
						if (as_release.get_kind () == AppStream.ReleaseKind.STABLE) {
							_version = as_release.get_version ();
							break;
						}
					}
				} else {
					_version = _installed_version;
				}
			} else if (this.remote_ref != null) {
				_id = "%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ());
				_name = remote_ref.get_name ();
				if (this.as_app != null) {
					unowned GenericArray<AppStream.Release> as_releases = as_app.get_releases ();
					foreach (unowned AppStream.Release as_release in as_releases) {
						if (as_release.get_kind () == AppStream.ReleaseKind.STABLE) {
							_version = as_release.get_version ();
							break;
						}
					}
				}
			}
		}
	}

	internal class FlatPak: Object, FlatpakPlugin {
		string sender;
		Flatpak.Installation installation;
		GenericArray<HashTable<unowned string, AppStream.Component>> stores_table;
		HashTable<string, Flatpak.RemoteRef> remote_refs_table;
		HashTable<string, FlatpakPackageLinked> pkgs_cache;
		HashTable<string, HashTable<unowned string, AppStream.Component>> categories_cache;
		Cancellable cancellable;

		public uint64 refresh_period { get; set; }

		public FlatPak (uint64 refresh_period) {
			Object (refresh_period: refresh_period);
		}

		construct {
			cancellable = new Cancellable ();
			stores_table = new GenericArray<HashTable<unowned string, AppStream.Component>> ();
			remote_refs_table = new HashTable<string, Flatpak.RemoteRef> (str_hash, str_equal);
			pkgs_cache = new HashTable<string, FlatpakPackageLinked> (str_hash, str_equal);
			categories_cache = new HashTable<string, HashTable<unowned string, AppStream.Component>> (str_hash, str_equal);
			try {
				installation = new Flatpak.Installation.system ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void load_appstream_data () {
			// init appstream
			try {
				// populate caches
				categories_cache.insert ("Photo & Video", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Music & Audio", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Productivity", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Communication & News", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Education & Science", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Games", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Utilities", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				categories_cache.insert ("Development", new HashTable<unowned string, AppStream.Component> (str_hash, str_equal));
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				foreach (unowned Flatpak.Remote remote in remotes) {
					if (remote.get_disabled ()) {
						continue;
					}
					// refresh appstream data
					refresh_remote_appstream_data (remote);
					// get appstream data dir
					File appstream_dir = remote.get_appstream_dir (null);
					File appstream_file = appstream_dir.get_child ("appstream.xml");
					if (appstream_file.query_exists ()) {
						unowned string remote_name = remote.get_name ();
						var mdata = new AppStream.Metadata ();
						mdata.set_format_style (AppStream.FormatStyle.COLLECTION);
						mdata.parse_file (appstream_file, AppStream.FormatKind.XML);
						var desktop_apps = new HashTable<unowned string, AppStream.Component> (str_hash, str_equal);
						unowned GenericArray<AppStream.Component> apps = mdata.get_components ();
						foreach (unowned AppStream.Component app in apps) {
							if (app.get_kind () == AppStream.ComponentKind.DESKTOP_APP) {
								unowned AppStream.Bundle? bundle = app.get_bundle (AppStream.BundleKind.FLATPAK);
								if (bundle == null) {
									continue;
								}
								string id = "%s/%s".printf (remote_name, bundle.get_id ());
								// change origin to remote name
								app.set_origin (remote_name);
								// add to app cache
								desktop_apps.insert (id, app);
								// add categories
								unowned GenericArray<string> app_categories = app.get_categories ();
								foreach (unowned string cat in app_categories) {
									switch (cat) {
										case "Photography":
										case "Graphics":
										case "Video":
											categories_cache.lookup ("Photo & Video").insert (id, app);
											break;
										case "Audio":
										case "Music":
											categories_cache.lookup ("Music & Audio").insert (id, app);
											break;
										case "WebBrowser":
										case "Email":
										case "Office":
											categories_cache.lookup ("Productivity").insert (id, app);
											break;
										case "Network":
											categories_cache.lookup ("Communication & News").insert (id, app);
											break;
										case "Education":
										case "Science":
											categories_cache.lookup ("Education & Science").insert (id, app);
											break;
										case "Games":
											categories_cache.lookup ("Games").insert (id, app);
											break;
										case "Utility":
											categories_cache.lookup ("Utilities").insert (id, app);
											break;
										case "Development":
											categories_cache.lookup ("Development").insert (id, app);
											break;
									}
								}
							}
						}
						stores_table.add (desktop_apps);
					}
					// get remote flatpaks
					GenericArray<unowned Flatpak.RemoteRef> remote_refs = installation.list_remote_refs_sync_full (remote.get_name(), Flatpak.QueryFlags.ONLY_CACHED);
					foreach (unowned Flatpak.RemoteRef remote_ref in remote_refs) {
						if (remote_ref.get_kind () == Flatpak.RefKind.APP) {
							remote_refs_table.insert ("%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ()), remote_ref);
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		int64 get_file_age (File file) {
			try {
				FileInfo info = file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
				DateTime last_modifed = info.get_modification_date_time ();
				var now = new DateTime.now_utc ();
				TimeSpan elapsed_time = now.difference (last_modifed);
				return elapsed_time;
			} catch (Error e) {
				warning (e.message);
				return int64.MAX;
			}
		}

		bool refresh_remote_appstream_data (Flatpak.Remote remote) {
			bool modified = false;
			int64 elapsed_time = get_file_age (remote.get_appstream_timestamp (null));
			if (elapsed_time < TimeSpan.HOUR) {
				return modified;
			}
			int64 elapsed_hours = elapsed_time / TimeSpan.HOUR;
			if (elapsed_hours > refresh_period) {
				unowned string remote_name = remote.get_name ();
				message ("refreshing %s appstream data", remote_name);
				try {
					installation.update_appstream_sync (remote_name, null, null);
					modified = true;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return modified;
		}

		public bool refresh_appstream_data () {
			bool modified = false;
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				foreach (unowned Flatpak.Remote remote in remotes) {
					if (remote.get_disabled ()) {
						continue;
					}
					bool remote_modified = refresh_remote_appstream_data (remote);
					if (remote_modified) {
						modified = true;
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return modified;
		}

		AppStream.Component? get_installed_ref_matching_app (Flatpak.InstalledRef installed_ref) {
			unowned AppStream.Component? matching_app = null;
			string id = "%s/%s".printf (installed_ref.get_origin (), installed_ref.format_ref ());
			lock (stores_table) {
				foreach (unowned HashTable<unowned string, AppStream.Component> apps in stores_table) {
					matching_app = apps.lookup (id);
					if (matching_app != null) {
						return matching_app;
					}
				}
			}
			return matching_app;
		}

		unowned AppStream.Component? get_remote_ref_matching_app (Flatpak.RemoteRef remote_ref) {
			unowned AppStream.Component? matching_app = null;
			string id = "%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ());
			lock (stores_table) {
				foreach (unowned HashTable<unowned string, AppStream.Component> apps in stores_table) {
					matching_app = apps.lookup (id);
					if (matching_app != null) {
						return matching_app;
					}
				}
			}
			return matching_app;
		}

		public void get_remotes_names (ref GenericArray<unowned string> remotes_names) {
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				foreach (unowned Flatpak.Remote remote in remotes) {
					if (remote.get_disabled ()) {
						continue;
					}
					remotes_names.add (remote.get_name ());
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void get_installed_flatpaks (ref GenericArray<unowned FlatpakPackage> pkgs) {
			try {
				lock (pkgs_cache)  {
					GenericArray<unowned Flatpak.InstalledRef> installed_apps = installation.list_installed_refs_by_kind (Flatpak.RefKind.APP);
					foreach (unowned Flatpak.InstalledRef installed_ref in installed_apps) {
						string id = "%s/%s".printf (installed_ref.get_origin () ,installed_ref.format_ref ());
						FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
						if (pkg == null) {
							AppStream.Component? app = get_installed_ref_matching_app (installed_ref);
							pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
							pkgs_cache.insert ((owned) id, pkg);
						}
						pkgs.add (pkg);
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public bool is_installed_flatpak (string id) {
			string[] splitted = id.split ("/", 4);
			//unowned string kind = splitted[0];
			unowned string name = splitted[1];
			unowned string arch = splitted[2];
			unowned string branch = splitted[3];
			try {
				Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
				if (installed_ref != null) {
					return true;
				}
			} catch (Error e) {
				if (e is Flatpak.Error.NOT_INSTALLED) {
					return false;
				}
				warning (e.message);
			}
			return false;
		}

		public unowned FlatpakPackage? get_flatpak_by_app_id (string app_id) {
			unowned FlatpakPackage? pkg = null;
			string other_app_id;
			if (app_id.has_suffix (".desktop")) {
				other_app_id = app_id.replace (".desktop", "");
			} else {
				other_app_id = app_id + ".desktop";
			}
			lock (stores_table) {
				foreach (unowned HashTable<unowned string, AppStream.Component> apps in stores_table) {
					var iter = HashTableIter<unowned string, AppStream.Component> (apps);
					unowned AppStream.Component app;
					while (iter.next (null, out app)) {
						unowned string current_app_id = app.id;
						if (current_app_id == app_id || current_app_id == other_app_id) {
							pkg = get_flatpak_from_app (app);
							return pkg;
						}
					}
				}
			}
			return pkg;
		}

		unowned FlatpakPackageLinked? get_flatpak_from_app (AppStream.Component app) {
			unowned FlatpakPackageLinked? pkg = null;
			unowned AppStream.Bundle bundle = app.get_bundle (AppStream.BundleKind.FLATPAK);
			unowned string bundle_id = bundle.get_id ();
			unowned string remote = app.get_origin ();
			string id = "%s/%s".printf (remote, bundle_id);
			lock (pkgs_cache) {
				// try  cache
				pkg = pkgs_cache.lookup (id);
				if (pkg == null) {
					// try installed
					string[] splitted = bundle_id.split ("/", 4);
					//unowned string kind = splitted[0];
					unowned string name = splitted[1];
					unowned string arch = splitted[2];
					unowned string branch = splitted[3];
					FlatpakPackageLinked? new_pkg = null;
					try {
						Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
						new_pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
						pkgs_cache.insert (id, new_pkg);
					} catch (Error e) {
						if (e is Flatpak.Error.NOT_INSTALLED) {
							// try remotes
							Flatpak.RemoteRef? remote_ref = remote_refs_table.lookup (id);
							if (remote_ref == null) {
								try {
									// app origin was set to remote name in load_appstream_data ()
									remote_ref = installation.fetch_remote_ref_sync (remote, Flatpak.RefKind.APP, name, arch, branch);
									remote_refs_table.insert (id, remote_ref);
								} catch (Error e) {
									warning (e.message);
								}
							}
							print ("bef %s %s\n", id, remote);
							new_pkg = new FlatpakPackageLinked (null, remote_ref, app, installation);
							print ("aft %s %s\n", new_pkg.id, new_pkg.repo);
							pkgs_cache.insert (id, new_pkg);
						} else {
							warning (e.message);
						}
					}
					pkg = new_pkg;
				}
			}
			return pkg;
		}

		public unowned FlatpakPackage? get_flatpak (string id) {
			unowned FlatpakPackageLinked? pkg = null;
			lock (pkgs_cache)  {
				pkg = pkgs_cache.lookup (id);
				if (pkg != null) {
					return pkg;
				}
				string[] splitted = id.split ("/", 5);
				unowned string remote = splitted[0];
				//unowned string kind = splitted[1];
				unowned string name = splitted[2];
				unowned string arch = splitted[3];
				unowned string branch = splitted[4];
				FlatpakPackageLinked? new_pkg = null;
				try {
					Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
					AppStream.Component? app = get_installed_ref_matching_app (installed_ref);
					new_pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
					pkgs_cache.insert (id, new_pkg);
				} catch (Error e) {
					if (e is Flatpak.Error.NOT_INSTALLED) {
						// try remotes
						Flatpak.RemoteRef? remote_ref = remote_refs_table.lookup (id);
						if (remote_ref == null) {
							try {
								remote_ref = installation.fetch_remote_ref_sync_full (remote, Flatpak.RefKind.APP, name, arch, branch, Flatpak.QueryFlags.ONLY_CACHED);
								remote_refs_table.insert (id, remote_ref);
								AppStream.Component? app = get_remote_ref_matching_app (remote_ref);
								new_pkg = new FlatpakPackageLinked (null, remote_ref, app, installation);
								pkgs_cache.insert (id, new_pkg);
							} catch (Error e) {
								if (!(e is Flatpak.Error.REF_NOT_FOUND)) {
									warning (e.message);
								}
							}
						}
					} else {
						warning (e.message);
					}
				}
				pkg = new_pkg;
			}
			return pkg;
		}

		public void search_flatpaks (string search_string, ref GenericArray<unowned FlatpakPackage> pkgs) {
			lock (stores_table) {
				foreach (unowned HashTable<unowned string, AppStream.Component> apps in stores_table) {
					var iter = HashTableIter<unowned string, AppStream.Component> (apps);
					unowned AppStream.Component app;
					while (iter.next (null, out app)) {
						string[] search_tokens = search_string.split (" ");
						uint match_score = app.search_matches_all (search_tokens);
						if (match_score > 0 || search_string in app.get_id  ()) {
							unowned FlatpakPackage? pkg = get_flatpak_from_app (app);
							if (pkg != null) {
								pkgs.add (pkg);
							}
						}
					}
				}
			}
		}

		public void search_uninstalled_flatpaks_sync (string[] search_terms, ref GenericArray<unowned FlatpakPackage> pkgs) {
			lock (stores_table) {
				foreach (unowned HashTable<unowned string, AppStream.Component> apps in stores_table) {
					var iter = HashTableIter<unowned string, AppStream.Component> (apps);
					unowned AppStream.Component app;
					while (iter.next (null, out app)) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							unowned FlatpakPackage? pkg = get_flatpak_from_app (app);
							if (pkg != null && pkg.installed_version == null) {
								pkgs.add (pkg);
							}
						}
					}
				}
			}
		}

		public void get_category_flatpaks (string category, ref GenericArray<unowned FlatpakPackage> pkgs) {
			switch (category) {
				case "Featured":
					var names = new GenericSet<string?> (str_hash, str_equal);
					names.add ("com.spotify.Client");
					names.add ("com.valvesoftware.Steam.desktop");
					names.add ("com.discordapp.Discord.desktop");
					names.add ("com.skype.Client.desktop");
					names.add ("com.mojang.Minecraft");
					names.add ("com.slack.Slack.desktop");
					foreach (unowned string id in names) {
						unowned FlatpakPackage? pkg = get_flatpak_by_app_id (id);
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
					break;
				case "Photo & Video":
				case "Music & Audio":
				case "Productivity":
				case "Communication & News":
				case "Education & Science":
				case "Games":
				case "Utilities":
				case "Development":
					unowned HashTable<unowned string, AppStream.Component> category_table = categories_cache.lookup (category);
					var iter = HashTableIter<unowned string, AppStream.Component> (category_table);
					unowned string id;
					unowned AppStream.Component app;
					while (iter.next (out id, out app)) {
						unowned FlatpakPackage? pkg = get_flatpak_from_app (app);
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
					break;
				default:
					break;
			}
		}

		public void get_flatpak_updates (ref GenericArray<FlatpakPackage> pkgs) {
			try {
				lock (pkgs_cache)  {
					GenericArray<unowned Flatpak.InstalledRef> update_apps = installation.list_installed_refs_for_update ();
					foreach (unowned Flatpak.InstalledRef installed_ref in update_apps) {
						if (installed_ref.kind == Flatpak.RefKind.APP) {
							string id = "%s/%s".printf (installed_ref.get_origin (), installed_ref.name);
							FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
							if (pkg == null) {
								AppStream.Component? app = get_installed_ref_matching_app (installed_ref);
								pkg = new FlatpakPackageLinked (installed_ref, null, app, installation, true);
								pkgs_cache.insert ((owned) id, pkg);
							}
							pkgs.add (pkg);
						}
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
			print ("choose a provider for %s\n", runtime_ref);
			return 0;
		}

		void on_new_operation (Flatpak.TransactionOperation operation, Flatpak.TransactionProgress progress) {
			string? action = null;
			switch (operation.get_operation_type ()) {
				case Flatpak.TransactionOperationType.INSTALL:
					action =  dgettext (null, "Installing %s").printf (operation.get_ref ());
					break;
				case Flatpak.TransactionOperationType.UNINSTALL:
					action =  dgettext (null, "Removing %s").printf (operation.get_ref ());
					break;
				case Flatpak.TransactionOperationType.UPDATE:
					action =  dgettext (null, "Upgrading %s").printf (operation.get_ref ());
					break;
				default:
					break;
			}
			if (action != null) {
				do_emit_action_progress (action, progress.get_status (), 0);
			}
			progress.changed.connect (() => {
				if (progress.get_is_estimating ()) {
					return;
				}
				switch (operation.get_operation_type ()) {
					case Flatpak.TransactionOperationType.INSTALL:
						action =  dgettext (null, "Installing %s").printf (operation.get_ref ());
						break;
					case Flatpak.TransactionOperationType.UNINSTALL:
						action =  dgettext (null, "Removing %s").printf (operation.get_ref ());
						break;
					case Flatpak.TransactionOperationType.UPDATE:
						action =  dgettext (null, "Upgrading %s").printf (operation.get_ref ());
						break;
					default:
						break;
				}
				if (action != null) {
					if (progress.get_progress () == 100) {
						do_emit_script_output (progress.get_status ());
						do_emit_action_progress (action, "", 1);
					} else {
						do_emit_action_progress (action, progress.get_status (), (double) progress.get_progress () / 100);
					}
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

		bool do_get_authorization () {
			return get_authorization (sender);
		}

		public bool trans_run (string sender, string[] to_install, string[] to_remove, string[] to_upgrade) {
			this.sender = sender;
			cancellable.reset ();
			if (!do_get_authorization ()) {
				return false;
			}
			try {
				var transaction = new Flatpak.Transaction.for_installation (installation, cancellable);
				foreach (unowned string id in to_install) {
					string[] splitted = id.split ("/", 2);
					string remote = splitted[0];
					string name = splitted[1];
					transaction.add_install (remote, name, null);
				}
				foreach (unowned string id in to_remove) {
					string name = id.split ("/", 2)[1];
					transaction.add_uninstall (name);
				}
				foreach (unowned string id in to_upgrade) {
					string name = id.split ("/", 2)[1];
					transaction.add_update (name, null, null);
				}
				if (to_upgrade.length > 0) {
					// add runtime updates
					GenericArray<unowned Flatpak.InstalledRef> update_apps = installation.list_installed_refs_for_update ();
					foreach (unowned Flatpak.InstalledRef installed_ref in update_apps) {
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
			lock (pkgs_cache)  {
				pkgs_cache.remove_all ();
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.FlatPak);
}
