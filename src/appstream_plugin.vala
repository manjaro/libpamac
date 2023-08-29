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

namespace Pamac {
	internal class AppLinked : App {
		// common
		AppStream.Component? _as_app;
		// Package
		unowned string? _name;
		unowned string? _id;
		unowned string? _pkgname;
		unowned string? _desc;
		string? _long_desc;
		unowned string _repo;
		unowned string? _launchable;
		string? _icon;
		GenericArray<string> _screenshots;

		// Package
		public override string? name {
			get {
				if (_name == null && _as_app != null) {
					_name = _as_app.get_name ();
				}
				return _name;
			}
		}
		public override string? id {
			get {
				if (_id == null && _as_app != null) {
					_id = _as_app.get_id ();
				}
				return _id;
			}
		}
		public override string? pkgname {
			get {
				if (_pkgname == null && _as_app != null) {
					_pkgname = _as_app.get_pkgname ();
				}
				return _pkgname;
			}
		}
		public override string? desc {
			get {
				if (_desc == null && _as_app != null) {
					_desc = _as_app.get_summary ();
				}
				return _desc;
			}
		}
		public override string? long_desc {
			get {
				if (_long_desc == null && _as_app != null) {
					try {
						_long_desc = AppStream.markup_convert_simple (_as_app.get_description ());
					} catch (Error e) {
						warning (e.message);
					}
				}
				return _long_desc;
			}
		}
		public override string? repo {
			get {
				return _repo;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && _as_app != null) {
					unowned AppStream.Launchable? as_launchable = _as_app.get_launchable (AppStream.LaunchableKind.DESKTOP_ID);
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
				if (_icon == null && _as_app != null && _repo != null) {
					unowned GenericArray<AppStream.Icon> as_icons = _as_app.get_icons ();
					foreach (unowned AppStream.Icon as_icon in as_icons) {
						if (as_icon.get_kind () == AppStream.IconKind.CACHED) {
							if (as_icon.get_height () == 64) {
								_icon = "/usr/share/swcatalog/icons/archlinux-arch-%s/64x64/%s".printf (_repo, as_icon.get_name ());
								break;
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
					if (_as_app != null) {
						unowned GenericArray<AppStream.Screenshot> as_screenshots = _as_app.get_screenshots ();
						foreach (unowned AppStream.Screenshot as_screenshot in as_screenshots) {
							unowned GenericArray<AppStream.Image> as_images = as_screenshot.get_images ();
							foreach (unowned AppStream.Image as_image in as_images) {
								unowned string? url = as_image.get_url ();
								if (url != null) {
									_screenshots.add (url);
								}
							}
						}
					}
				}
				return _screenshots;
			}
		}

		internal AppLinked (AppStream.Component? as_app, string? repo) {
			_as_app = as_app;
			_repo = repo;
		}

		public uint search_matches_all (string [] search_tokens) {
			return _as_app.search_matches_all (search_tokens);
		}
	}

	internal class Appstream: Object, AppstreamPlugin {
		GenericArray<HashTable<unowned string, App>> stores_table;
		HashTable<string, GenericArray<unowned App>> pkgname_apps_cache;
		HashTable<string, HashTable<unowned string, unowned App>> categories_cache;
		GenericArray<string> repos_names;

		public Appstream () {
			Object ();
		}

		construct {
			repos_names = new GenericArray<string> ();
			stores_table = new GenericArray<HashTable<unowned string, App>> ();
			categories_cache = new HashTable<string, HashTable<unowned string, unowned App>> (str_hash, str_equal);
			pkgname_apps_cache = new HashTable<string, GenericArray<unowned App>> (str_hash, str_equal);
		}

		void load (GenericArray<string> repos_names) {
			this.repos_names = repos_names;
			// populate caches
			categories_cache.insert ("Photo & Video", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Music & Audio", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Productivity", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Communication & News", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Education & Science", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Games", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Utilities", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			categories_cache.insert ("Development", new HashTable<unowned string, unowned App> (str_hash, str_equal));
			foreach (unowned string repo in repos_names) {
				try {
					File appstream_file = File.new_for_path ("/usr/share/swcatalog/xml/%s.xml.gz".printf (repo));
					if (appstream_file.query_exists ()) {
						var mdata = new AppStream.Metadata ();
						mdata.set_format_style (AppStream.FormatStyle.COLLECTION);
						mdata.parse_file (appstream_file, AppStream.FormatKind.XML);
						var desktop_apps = new HashTable<unowned string, App> (str_hash, str_equal);
						unowned GenericArray<AppStream.Component> apps = mdata.get_components ();
						foreach (unowned AppStream.Component app in apps) {
							if (app.get_kind () == AppStream.ComponentKind.DESKTOP_APP) {
								// add pkgnames
								unowned string? pkgname = app.get_pkgname ();
								if (pkgname == null) {
									continue;
								}
								GenericArray<unowned App>? pkgname_apps = pkgname_apps_cache.lookup (pkgname);
								if (pkgname_apps == null) {
									pkgname_apps = new GenericArray<unowned App> ();
									pkgname_apps_cache.insert (pkgname, pkgname_apps);
								}
								var new_app = new AppLinked (app, repo);
								pkgname_apps.add (new_app);
								// add to app cache
								unowned string id = new_app.id;
								desktop_apps.insert (id, new_app);
								// add categories
								unowned GenericArray<string> app_categories = app.get_categories ();
								foreach (unowned string cat in app_categories) {
									switch (cat) {
										case "Photography":
										case "Graphics":
										case "Video":
											categories_cache.lookup ("Photo & Video").insert (id, new_app);
											break;
										case "Audio":
										case "Music":
											categories_cache.lookup ("Music & Audio").insert (id, new_app);
											break;
										case "WebBrowser":
										case "Email":
										case "Office":
											categories_cache.lookup ("Productivity").insert (id, new_app);
											break;
										case "Network":
											categories_cache.lookup ("Communication & News").insert (id, new_app);
											break;
										case "Education":
										case "Science":
											categories_cache.lookup ("Education & Science").insert (id, new_app);
											break;
										case "Games":
											categories_cache.lookup ("Games").insert (id, new_app);
											break;
										case "Utility":
											categories_cache.lookup ("Utilities").insert (id, new_app);
											break;
										case "Development":
											categories_cache.lookup ("Development").insert (id, new_app);
											break;
									}
								}
							}
						}
						stores_table.add (desktop_apps);
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public unowned GenericArray<HashTable<unowned string, App>> get_apps () {
			return stores_table;
		}

		public GenericArray<unowned App> search (string[] search_tokens) {
			var result = new GenericArray<unowned App> ();
			foreach (unowned HashTable<unowned string, App> apps in stores_table) {
				var iter = HashTableIter<unowned string, App> (apps);
				unowned string repo;
				unowned App app;
				while (iter.next (out repo, out app)) {
					unowned AppLinked applinked = app as AppLinked;
					uint match_score = applinked.search_matches_all (search_tokens);
					if (match_score > 0 || search_tokens[0] in app.id) {
						result.add (app);
					}
				}
			}
			return result;
		}

		public GenericArray<unowned  App> get_pkgname_apps (string pkgname) {
			GenericArray<unowned App>? apps = pkgname_apps_cache.lookup (pkgname);
			if (apps == null) {
				apps = new GenericArray<unowned App> ();
			}
			return apps;
		}

		public HashTable<unowned string, unowned App> get_category_apps (string category) {
			HashTable<unowned string, unowned App>? apps_table = categories_cache.lookup (category);
			if (apps_table == null) {
				apps_table = new HashTable<unowned string, unowned App> (str_hash, str_equal);
				if (category == "Featured") {
					var names = new GenericArray<string> ();
					names.add ("firefox");
					names.add ("vlc");
					names.add ("gimp");
					names.add ("shotwell");
					names.add ("inkscape");
					names.add ("blender");
					names.add ("libreoffice-still");
					names.add ("telegram-desktop");
					names.add ("cura");
					names.add ("arduino");
					names.add ("retroarch");
					names.add ("virtualbox");
					foreach (unowned string name in names) {
						unowned GenericArray<unowned App>? apps = pkgname_apps_cache.lookup (name);
						if (apps == null) {
							continue;
						}
						foreach (unowned App app in apps) {
							apps_table.insert (app.id, app);
						}
					}
					categories_cache.insert (category, apps_table);
				}
			}
			return apps_table;
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.Appstream);
}
