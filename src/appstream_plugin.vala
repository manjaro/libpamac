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
	const string SWCATALOG_DIR = "/usr/share/swcatalog";
	const uint PREFERRED_ICON_SIZE = 64;

	internal class AppLinked : App {
		// common
		AppStream.Component _as_app;
		// Package
		unowned string? _name;
		string? _id;
		unowned string? _pkgname;
		unowned string? _desc;
		string? _long_desc;
		bool _long_desc_loaded;
		unowned string _repo;
		unowned string _origin;
		unowned string? _launchable;
		string? _icon;
		GenericArray<string> _screenshots;

		// Package
		public override string? name {
			get {
				if (_name == null) {
					_name = _as_app.get_name ();
				}
				return _name;
			}
		}
		public override string? id {
			get {
				if (_id == null && pkgname != null) {
					_id = "%s/%s".printf (pkgname, _as_app.get_id ());
				}
				return _id;
			}
		}
		public override string? pkgname {
			get {
				if (_pkgname == null) {
					_pkgname = _as_app.get_pkgname ();
				}
				return _pkgname;
			}
		}
		public override string? desc {
			get {
				if (_desc == null) {
					_desc = _as_app.get_summary ();
				}
				return _desc;
			}
		}
		public override string? long_desc {
			get {
				if (!_long_desc_loaded) {
					// only try once, even if the conversion fails
					_long_desc_loaded = true;
					unowned string? description = _as_app.get_description ();
					if (description != null) {
						try {
							_long_desc = AppStream.markup_convert (description, AppStream.MarkupKind.MARKDOWN);
						} catch (Error e) {
							warning (e.message);
						}
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
				if (_launchable == null) {
					unowned AppStream.Launchable? as_launchable = _as_app.get_launchable (AppStream.LaunchableKind.DESKTOP_ID);
					if (as_launchable != null) {
						unowned GenericArray<string> entries = as_launchable.get_entries ();
						if (entries.length > 0) {
							_launchable = entries[0];
						}
					}
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null) {
					unowned AppStream.Icon? best_icon = null;
					unowned GenericArray<AppStream.Icon> as_icons = _as_app.get_icons ();
					foreach (unowned AppStream.Icon as_icon in as_icons) {
						// cached icons with a scale factor are stored in another directory
						if (as_icon.get_kind () != AppStream.IconKind.CACHED || as_icon.get_scale () > 1) {
							continue;
						}
						if (best_icon == null || is_better_icon_size (as_icon.get_height (), best_icon.get_height ())) {
							best_icon = as_icon;
						}
					}
					if (best_icon != null) {
						uint size = best_icon.get_height ();
						_icon = "%s/icons/%s/%ux%u/%s".printf (SWCATALOG_DIR, _origin, size, size, best_icon.get_name ());
					}
				}
				return _icon;
			}
		}
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					unowned GenericArray<AppStream.Screenshot> as_screenshots = _as_app.get_screenshots_all ();
					foreach (unowned AppStream.Screenshot as_screenshot in as_screenshots) {
						unowned string? url = get_screenshot_url (as_screenshot);
						if (url != null) {
							_screenshots.add (url);
						}
					}
				}
				return _screenshots;
			}
		}

		internal AppLinked (AppStream.Component as_app, string repo, string origin) {
			_as_app = as_app;
			_repo = repo;
			_origin = origin;
		}

		public uint search_matches_all (string[] search_tokens) {
			return _as_app.search_matches_all (search_tokens);
		}

		// prefer the exact size, then the smallest bigger one, then the biggest smaller one
		static bool is_better_icon_size (uint size, uint best_size) {
			if (best_size == PREFERRED_ICON_SIZE) {
				return false;
			}
			if (size >= PREFERRED_ICON_SIZE) {
				return best_size < PREFERRED_ICON_SIZE || size < best_size;
			}
			return best_size < PREFERRED_ICON_SIZE && size > best_size;
		}

		// one image per screenshot: the source one if available
		static unowned string? get_screenshot_url (AppStream.Screenshot as_screenshot) {
			unowned string? url = null;
			unowned GenericArray<AppStream.Image> as_images = as_screenshot.get_images ();
			foreach (unowned AppStream.Image as_image in as_images) {
				unowned string? image_url = as_image.get_url ();
				if (image_url == null) {
					continue;
				}
				if (as_image.get_kind () == AppStream.ImageKind.SOURCE) {
					return image_url;
				}
				if (url == null) {
					url = image_url;
				}
			}
			return url;
		}
	}

	internal class Appstream: Object, AppstreamPlugin {
		const string[] CATEGORIES = {
			"Photo & Video",
			"Music & Audio",
			"Productivity",
			"Communication & News",
			"Education & Science",
			"Games",
			"Utilities",
			"Development"
		};
		const string[] FEATURED_PKGNAMES = {
			"firefox",
			"vlc",
			"gimp",
			"shotwell",
			"inkscape",
			"blender",
			"libreoffice-still",
			"telegram-desktop",
			"cura",
			"arduino",
			"retroarch",
			"virtualbox"
		};

		GenericArray<HashTable<unowned string, App>> stores_table;
		HashTable<string, GenericArray<unowned App>> pkgname_apps_cache;
		HashTable<string, HashTable<unowned string, unowned App>> categories_cache;
		GenericArray<string> repos_names;
		// catalogs origins, referenced by apps
		GenericArray<string> origins;
		// not loaded, only used to build search tokens
		AppStream.Pool search_pool;

		public Appstream () {
			Object ();
		}

		construct {
			repos_names = new GenericArray<string> ();
			origins = new GenericArray<string> ();
			stores_table = new GenericArray<HashTable<unowned string, App>> ();
			categories_cache = new HashTable<string, HashTable<unowned string, unowned App>> (str_hash, str_equal);
			pkgname_apps_cache = new HashTable<string, GenericArray<unowned App>> (str_hash, str_equal);
			search_pool = new AppStream.Pool ();
		}

		void load (GenericArray<string> repos_names) {
			// clear caches holding unowned apps before the apps themselves
			categories_cache.remove_all ();
			pkgname_apps_cache.remove_all ();
			stores_table.remove_range (0, stores_table.length);
			origins.remove_range (0, origins.length);
			this.repos_names = repos_names;
			// populate caches
			foreach (unowned string category in CATEGORIES) {
				categories_cache.insert (category, new HashTable<unowned string, unowned App> (str_hash, str_equal));
			}
			foreach (unowned string repo in repos_names) {
				File appstream_file = File.new_for_path ("%s/xml/%s.xml.gz".printf (SWCATALOG_DIR, repo));
				var mdata = new AppStream.Metadata ();
				mdata.set_format_style (AppStream.FormatStyle.CATALOG);
				try {
					mdata.parse_file (appstream_file, AppStream.FormatKind.XML);
				} catch (IOError.NOT_FOUND e) {
					continue;
				} catch (Error e) {
					warning (e.message);
					continue;
				}
				unowned string? origin = mdata.get_origin ();
				if (origin == null || origin == "") {
					origins.add ("archlinux-arch-%s".printf (repo));
				} else {
					origins.add (origin);
				}
				unowned string repo_origin = origins[origins.length - 1];
				var desktop_apps = new HashTable<unowned string, App> (str_hash, str_equal);
				unowned GenericArray<AppStream.Component> apps = mdata.get_components ().as_array ();
				foreach (unowned AppStream.Component app in apps) {
					if (app.get_kind () != AppStream.ComponentKind.DESKTOP_APP) {
						continue;
					}
					unowned string? pkgname = app.get_pkgname ();
					if (pkgname == null) {
						continue;
					}
					var new_app = new AppLinked (app, repo, repo_origin);
					unowned string id = new_app.id;
					if (desktop_apps.contains (id)) {
						// don't add duplicate app
						continue;
					}
					// add to app cache
					desktop_apps.insert (id, new_app);
					// add pkgnames
					unowned GenericArray<unowned App>? pkgname_apps = pkgname_apps_cache.lookup (pkgname);
					if (pkgname_apps == null) {
						var new_pkgname_apps = new GenericArray<unowned App> ();
						pkgname_apps = new_pkgname_apps;
						pkgname_apps_cache.insert (pkgname, (owned) new_pkgname_apps);
					}
					pkgname_apps.add (new_app);
					// add categories
					unowned GenericArray<string> app_categories = app.get_categories ();
					foreach (unowned string cat in app_categories) {
						unowned string? main_category = get_main_category (cat);
						if (main_category != null) {
							categories_cache.lookup (main_category).insert (id, new_app);
						}
					}
				}
				stores_table.add (desktop_apps);
			}
		}

		// map freedesktop categories to pamac ones
		static unowned string? get_main_category (string cat) {
			switch (cat) {
				case "Photography":
				case "ImageProcessing":
				case "Graphics":
				case "Video":
				case "VectorGraphics":
				case "2DGraphics":
				case "3DGraphics":
					return "Photo & Video";
				case "Audio":
				case "Music":
				case "Midi":
				case "Mixer":
				case "Multimedia":
					return "Music & Audio";
				case "WebBrowser":
				case "Email":
				case "Office":
				case "Calculator":
				case "Calendar":
				case "Clock":
				case "ContactManagement":
				case "Dictionary":
				case "Documentation":
				case "Finance":
				case "FlowChart":
				case "Presentation":
				case "Productivity":
				case "Spreadsheet":
				case "WordProcessor":
				case "Publishing":
					return "Productivity";
				case "Network":
				case "Chat":
				case "News":
				case "Feed":
				case "Communication":
				case "InstantMessaging":
				case "IRCClient":
				case "Telephony":
				case "VideoConference":
					return "Communication & News";
				case "Education":
				case "Science":
				case "Astronomy":
				case "Chemistry":
				case "ComputerScience":
				case "Electricity":
				case "Electronics":
				case "Physics":
				case "Engineering":
				case "Geography":
				case "Geoscience":
				case "Languages":
				case "Literature":
				case "Maps":
				case "Math":
				case "NumericalAnalysis":
					return "Education & Science";
				case "Games":
				case "Game":
				case "ActionGame":
				case "ArcadeGame":
				case "BlocksGame":
				case "BoardGame":
				case "LogicGame":
				case "StrategyGame":
				case "RolePlaying":
				case "AdventureGame":
				case "CardGame":
				case "KidsGame":
				case "Emulator":
					return "Games";
				case "Utility":
				case "Monitor":
				case "Accessibility":
				case "Archiving":
				case "Compression":
				case "ConsoleOnly":
				case "Core":
				case "DesktopSettings":
				case "DiscBurning":
				case "Settings":
				case "FileManager":
				case "Filesystem":
				case "FileTools":
				case "PackageManager":
				case "FileTransfer":
				case "HardwareSettings":
					return "Utilities";
				case "Development":
				case "IDE":
				case "Building":
				case "Construction":
				case "Database":
				case "DataVisualization":
				case "Debugger":
				case "GUIDesigner":
				case "Java":
				case "WebDevelopment":
					return "Development";
				default:
					return null;
			}
		}

		public unowned GenericArray<HashTable<unowned string, App>> get_apps () {
			return stores_table;
		}

		public GenericArray<unowned App> search (string[] search_tokens) {
			var result = new GenericArray<unowned App> ();
			// ignore empty tokens (e.g. from consecutive spaces)
			string[] tokens = {};
			foreach (unowned string token in search_tokens) {
				if (token != "") {
					tokens += token.down ();
				}
			}
			if (tokens.length == 0) {
				return result;
			}
			// apps are indexed with stemmed words in the current locale
			// (e.g. "disk" for "Disks"), search terms have to be processed the same way
			string[] stemmed_tokens = search_pool.build_search_tokens (string.joinv (" ", tokens));
			if (stemmed_tokens.length == 0) {
				// e.g. only stop words: keep the given tokens
				stemmed_tokens = tokens;
			}
			foreach (unowned HashTable<unowned string, App> apps in stores_table) {
				var iter = HashTableIter<unowned string, App> (apps);
				unowned string id;
				unowned App app;
				while (iter.next (out id, out app)) {
					unowned AppLinked applinked = (AppLinked) app;
					if (applinked.search_matches_all (stemmed_tokens) > 0 || id_matches_all (id, tokens)) {
						result.add (app);
					}
				}
			}
			return result;
		}

		static bool id_matches_all (string id, string[] tokens) {
			string id_down = id.down ();
			foreach (unowned string token in tokens) {
				if (!(token in id_down)) {
					return false;
				}
			}
			return true;
		}

		public GenericArray<unowned App> get_pkgname_apps (string pkgname) {
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
					foreach (unowned string name in FEATURED_PKGNAMES) {
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
