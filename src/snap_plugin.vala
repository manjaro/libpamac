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
	internal class SnapPackageLinked : SnapPackage {
		/* Screenshots uploaded as "banner.png", "banner.jpg", "banner-icon.png" or "banner-icon.jpg"
		 * are not real screenshots. The server optionally adds a 7 character suffix onto it
		 * if it would collide with an existing name, e.g. "banner_MgEy4MI.png"
		 * See https://forum.snapcraft.io/t/improve-method-for-setting-featured-snap-banner-image-in-store/
		 */
		static Regex? banner_regex;

		// common
		Snapd.Snap snap;
		Snapd.Snap? store_snap;
		Snapd.Snap? installed_snap;
		// Package
		string _name;
		string _id;
		string? _app_id;
		string? _launchable;
		GenericArray<string> _screenshots;
		// Snap Package
		string? _channel;
		GenericArray<string> _channels;

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
			get { return snap.version; }
			internal set { /* not used */ }
		}
		public override string? installed_version {
			get {
				if (installed_snap != null) {
					return installed_snap.version;
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? repo {
			get { return dgettext (null, "Snap"); }
			internal set { /* not used */ }
		}
		public override string? url {
			get { return snap.contact; }
		}
		public override uint64 installed_size {
			get {
				if (installed_snap != null) {
					return installed_snap.installed_size;
				}
				return 0;
			}
		}
		public override uint64 download_size {
			get { return snap.download_size; }
		}
		public override DateTime? install_date {
			get {
				if (installed_snap != null) {
					return installed_snap.install_date;
				}
				return null;
			}
		}
		public override string? app_name { get { return snap.title; } }
		public override string? app_id { get { return _app_id; } }
		public override string? desc {
			get { return snap.summary; }
			internal set { /* not used */ }
		}
		public override string? long_desc { get { return snap.description; } }
		public override string? launchable { get { return _launchable; } }
		public override string? icon { get { return snap.icon; } }
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					if (store_snap != null) {
						unowned GenericArray<Snapd.Media> medias = store_snap.get_media ();
						foreach (unowned Snapd.Media media in medias) {
							if (media.type == "screenshot") {
								unowned string url = media.url;
								if (!is_banner (Path.get_basename (url))) {
									_screenshots.add (url);
								}
							}
						}
					}
				}
				return _screenshots;
			}
		}
		// Snap Package
		public override string? channel {
			get {
				if (_channel == null && snap.channel != null) {
					_channel = snap.channel.replace ("latest/", "");
				}
				return _channel;
			}
		}
		public override string? publisher { get { return snap.publisher_display_name; } }
		public override string? license { get { return snap.license; } }
		public override string? confined {
			get {
				if (snap.confinement == Snapd.Confinement.STRICT) {
					return dgettext (null, "Yes");
				} else {
					return dgettext (null, "No");
				}
			}
		}
		public override GenericArray<string> channels {
			get {
				if (_channels == null) {
					_channels = new GenericArray<string> ();
					if (store_snap != null) {
						unowned GenericArray<Snapd.Channel> channels = store_snap.get_channels ();
						foreach (unowned Snapd.Channel channel in channels) {
							_channels.add ("%s : %s".printf (channel.name.replace ("latest/", ""), channel.version));
						}
					}
				}
				return _channels;
			}
		}

		internal SnapPackageLinked (Snapd.Snap snap, Snapd.Snap? installed_snap, Snapd.Snap? store_snap) {
			this.snap = snap;
			this.store_snap = store_snap;
			this.installed_snap = installed_snap;
			_name = snap.name;
			_id = "Snap/%s".printf (snap.name);
			unowned Snapd.App? primary_app = Snap.get_primary_app (this.snap);
			if (primary_app != null) {
				unowned string? desktop_file = primary_app.desktop_file;
				if (desktop_file != null) {
					_launchable = Path.get_basename (desktop_file);
					_app_id = _launchable;
				}
			}
			if (_app_id == null) {
				_app_id = snap.name;
			}
		}

		// store data can be missing if the package was created without network
		internal void set_store_snap (Snapd.Snap store_snap) {
			if (this.store_snap == null) {
				this.store_snap = store_snap;
				// computed again with store data
				_screenshots = null;
				_channels = null;
			}
		}

		static bool is_banner (string filename) {
			// compiled once, at first use
			if (banner_regex == null) {
				try {
					banner_regex = new Regex ("^banner(?:-icon)?(?:_[a-zA-Z0-9]{7})?\\.(?:png|jpg)$", RegexCompileFlags.OPTIMIZE);
				} catch (Error e) {
					warning (e.message);
					return false;
				}
			}
			return banner_regex.match (filename);
		}
	}

	internal class Snap : Object, SnapPlugin {
		const string[] FEATURED_SNAPS = {
			"spotify",
			"signal-desktop",
			"discord"
		};
		// search as you type creates many cached results
		const uint MAX_CACHED_SEARCHES = 50;
		const int64 ICON_MAX_AGE = TimeSpan.DAY;

		// receives the progress of the current transaction:
		// read by trans_cancel from another thread
		TransactionSink _sink;
		Mutex sink_mutex;
		TransactionSink sink {
			owned get {
				sink_mutex.lock ();
				TransactionSink current = _sink;
				sink_mutex.unlock ();
				return current;
			}
			set {
				sink_mutex.lock ();
				_sink = value;
				sink_mutex.unlock ();
			}
		}
		Snapd.Client client;
		// caches are protected by their own lock, never held during a request
		HashTable<string, Snapd.Snap> store_snaps_cache;
		// snaps not found in the store, protected by lock (store_snaps_cache)
		GenericSet<string> missing_store_snaps;
		HashTable<string, GenericArray<unowned Snapd.Snap>> search_snaps_cache;
		HashTable<string, GenericArray<unowned Snapd.Snap>> category_snaps_cache;
		HashTable<unowned string, SnapPackageLinked> pkgs_cache;
		// download data
		Cancellable cancellable;
		Timer timer;
		bool downloading;
		// snaps whose download start and end were displayed
		GenericSet<string> started_downloads;
		GenericSet<string> finished_downloads;
		bool init_download;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		string main_action;
		string current_action;
		string current_details;
		double current_progress;
		string current_status;

		public Snap () {
			Object ();
		}

		construct {
			sink_mutex = Mutex ();
			_sink = new NullSink ();
			client = new Snapd.Client ();
			store_snaps_cache = new HashTable<string, Snapd.Snap> (str_hash, str_equal);
			missing_store_snaps = new GenericSet<string> (str_hash, str_equal);
			search_snaps_cache = new HashTable<string, GenericArray<unowned Snapd.Snap>> (str_hash, str_equal);
			category_snaps_cache = new HashTable<string, GenericArray<unowned Snapd.Snap>> (str_hash, str_equal);
			pkgs_cache = new HashTable<unowned string, SnapPackageLinked> (str_hash, str_equal);
			// download data
			cancellable = new Cancellable ();
			timer = new Timer ();
			downloading = false;
			started_downloads = new GenericSet<string> (str_hash, str_equal);
			finished_downloads = new GenericSet<string> (str_hash, str_equal);
		}

		internal static bool app_name_matches_snap_name (Snapd.Snap snap, Snapd.App app) {
			return strcmp (snap.name, app.name) == 0;
		}

		internal static unowned Snapd.App? get_primary_app (Snapd.Snap snap) {
			/* Pick the "main" app from the snap.  In order of
			 * preference, we want to pick:
			 *
			 *   1. the main app, provided it has a desktop file
			 *   2. the first app with a desktop file
			 *   3. the main app
			 *   4. the first app
			 *
			 * The "main app" is one whose name matches the snap name.
			 */
			unowned Snapd.App? primary_app = null;
			unowned GenericArray<Snapd.App> apps = snap.get_apps ();
			foreach (unowned Snapd.App app in apps) {
				if (primary_app == null ||
					(primary_app.desktop_file == null && app.desktop_file != null) ||
					(!app_name_matches_snap_name (snap, primary_app) && app_name_matches_snap_name (snap, app))) {
					primary_app = app;
				}
			}
			return primary_app;
		}

		// snap: the data to display, the installed one or the store one
		SnapPackageLinked initialize_snap (Snapd.Snap snap, Snapd.Snap? installed_snap, Snapd.Snap? store_snap) {
			lock (pkgs_cache) {
				SnapPackageLinked? pkg = pkgs_cache.lookup ("Snap/%s".printf (snap.name));
				if (pkg == null) {
					var new_pkg = new SnapPackageLinked (snap, installed_snap, store_snap);
					pkg = new_pkg;
					pkgs_cache.insert (pkg.id, (owned) new_pkg);
				}
				return pkg;
			}
		}

		// installed apps, in snapd order
		GenericArray<unowned Snapd.Snap> get_installed_app_snaps () {
			var app_snaps = new GenericArray<unowned Snapd.Snap> ();
			try {
				// keep snaps alive while returned
				app_snaps = client.get_snaps_sync (Snapd.GetSnapsFlags.NONE, null, null);
				for (uint i = app_snaps.length; i > 0; i--) {
					if (app_snaps[i - 1].snap_type != Snapd.SnapType.APP) {
						app_snaps.remove_index (i - 1);
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return app_snaps;
		}

		// installed apps by name, with only one request to snapd
		HashTable<string, Snapd.Snap> get_installed_snaps_table () {
			var installed_snaps = new HashTable<string, Snapd.Snap> (str_hash, str_equal);
			foreach (unowned Snapd.Snap snap in get_installed_app_snaps ()) {
				installed_snaps.insert (snap.name, snap);
			}
			return installed_snaps;
		}

		// add apps found in the store, each one only once
		void add_store_snaps (GenericArray<unowned Snapd.Snap> found,
							HashTable<string, Snapd.Snap> installed_snaps,
							GenericSet<string> added,
							GenericArray<SnapPackage> pkgs) {
			foreach (unowned Snapd.Snap snap in found) {
				if (snap.snap_type != Snapd.SnapType.APP || snap.name in added) {
					continue;
				}
				added.add (snap.name);
				pkgs.add (initialize_snap (snap, installed_snaps.lookup (snap.name), snap));
			}
		}

		public void search_snaps (string search_string, ref GenericArray<SnapPackage> pkgs) {
			GenericArray<unowned Snapd.Snap>? found;
			lock (search_snaps_cache) {
				found = search_snaps_cache.lookup (search_string);
			}
			if (found == null) {
				try {
					found = client.find_sync (Snapd.FindFlags.SCOPE_WIDE, search_string, null, null);
				} catch (Error e) {
					warning (e.message);
					return;
				}
				lock (search_snaps_cache) {
					if (search_snaps_cache.size () >= MAX_CACHED_SEARCHES) {
						search_snaps_cache.remove_all ();
					}
					search_snaps_cache.insert (search_string, found);
				}
			}
			add_store_snaps (found, get_installed_snaps_table (), new GenericSet<string> (str_hash, str_equal), pkgs);
		}

		public bool is_installed_snap (string name) {
			return get_local_snap (name) != null;
		}

		public SnapPackage? get_snap (string name) {
			Snapd.Snap? installed_snap = get_local_snap (name);
			Snapd.Snap? store_snap = get_store_snap (name);
			Snapd.Snap? snap = installed_snap ?? store_snap;
			if (snap == null) {
				return null;
			}
			SnapPackageLinked pkg = initialize_snap (snap, installed_snap, store_snap);
			if (store_snap != null) {
				pkg.set_store_snap (store_snap);
			}
			return pkg;
		}

		public SnapPackage? get_snap_by_app_id (string app_id) {
			string desktop_id = app_id.has_suffix (".desktop") ? app_id : app_id + ".desktop";
			foreach (unowned Snapd.Snap snap in get_installed_app_snaps ()) {
				unowned Snapd.App? primary_app = get_primary_app (snap);
				if (primary_app == null || primary_app.desktop_file == null) {
					continue;
				}
				if (Path.get_basename (primary_app.desktop_file) == desktop_id) {
					Snapd.Snap? store_snap = get_store_snap (snap.name);
					SnapPackageLinked pkg = initialize_snap (snap, snap, store_snap);
					if (store_snap != null) {
						pkg.set_store_snap (store_snap);
					}
					return pkg;
				}
			}
			return null;
		}

		Snapd.Snap? get_local_snap (string name) {
			try {
				Snapd.Snap found = client.get_snap_sync (name, null);
				if (found.snap_type == Snapd.SnapType.APP) {
					return found;
				}
			} catch (Error e) {
				// an error is reported if not found
			}
			return null;
		}

		// returns true if the store snap is known, found or not
		bool lookup_store_snap (string name, out Snapd.Snap? found) {
			lock (store_snaps_cache) {
				found = store_snaps_cache.lookup (name);
				return found != null || name in missing_store_snaps;
			}
		}

		void cache_store_snap (string name, Snapd.Snap? found) {
			lock (store_snaps_cache) {
				if (found != null) {
					store_snaps_cache.insert (name, found);
				} else {
					missing_store_snaps.add (name);
				}
			}
		}

		// network errors are not cached, only snaps not found
		static bool is_store_snap_not_found (GenericArray<unowned Snapd.Snap>? founds, Error? error) {
			if (error != null) {
				return error is Snapd.Error.NOT_FOUND;
			}
			return founds.length != 1;
		}

		Snapd.Snap? get_store_snap (string name) {
			Snapd.Snap? found;
			if (lookup_store_snap (name, out found)) {
				return found;
			}
			GenericArray<unowned Snapd.Snap>? founds = null;
			Error? error = null;
			try {
				founds = client.find_sync (Snapd.FindFlags.SCOPE_WIDE | Snapd.FindFlags.MATCH_NAME, name, null, null);
			} catch (Error e) {
				error = e;
			}
			if (is_store_snap_not_found (founds, error)) {
				cache_store_snap (name, null);
			} else if (error == null) {
				found = founds[0];
				cache_store_snap (name, found);
			}
			return found;
		}

		async void fetch_store_snap (string name) {
			GenericArray<unowned Snapd.Snap>? founds = null;
			Error? error = null;
			try {
				string suggested_currency;
				founds = yield client.find_async (Snapd.FindFlags.SCOPE_WIDE | Snapd.FindFlags.MATCH_NAME, name, null, out suggested_currency);
			} catch (Error e) {
				error = e;
			}
			if (is_store_snap_not_found (founds, error)) {
				cache_store_snap (name, null);
			} else if (error == null) {
				cache_store_snap (name, founds[0]);
			}
		}

		// get store data of several snaps with parallel requests
		void prefetch_store_snaps (GenericArray<unowned Snapd.Snap> snaps) {
			var context = new MainContext ();
			context.push_thread_default ();
			uint pending = 0;
			foreach (unowned Snapd.Snap snap in snaps) {
				Snapd.Snap? found;
				if (lookup_store_snap (snap.name, out found)) {
					continue;
				}
				pending++;
				fetch_store_snap.begin (snap.name, () => {
					pending--;
				});
			}
			while (pending > 0) {
				context.iteration (true);
			}
			context.pop_thread_default ();
		}

		public void get_installed_snaps (ref GenericArray<SnapPackage> pkgs) {
			GenericArray<unowned Snapd.Snap> snaps = get_installed_app_snaps ();
			// store data is needed to display channels and screenshots
			prefetch_store_snaps (snaps);
			foreach (unowned Snapd.Snap snap in snaps) {
				Snapd.Snap? store_snap;
				lookup_store_snap (snap.name, out store_snap);
				SnapPackageLinked pkg = initialize_snap (snap, snap, store_snap);
				if (store_snap != null) {
					pkg.set_store_snap (store_snap);
				}
				pkgs.add (pkg);
			}
		}

		static int64 get_file_age (File file) {
			try {
				FileInfo info = file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
				DateTime last_modified = info.get_modification_date_time ();
				return new DateTime.now_utc ().difference (last_modified);
			} catch (Error e) {
				return int64.MAX;
			}
		}

		public string get_installed_snap_icon (string name) throws Error {
			if (name == "" || "/" in name || name.has_prefix (".")) {
				throw new IOError.INVALID_ARGUMENT ("invalid snap name: %s", name);
			}
			// keep icons in a private per-user cache: in a shared /tmp directory,
			// another user could plant fake icons or symlinks to make us write elsewhere
			string icons_dir = Path.build_filename (Environment.get_user_cache_dir (), "pamac", "snap-icons");
			DirUtils.create_with_parents (icons_dir, 0700);
			var cached_icon = File.new_for_path (Path.build_filename (icons_dir, name));
			// the icon can change with a snap update
			if (get_file_age (cached_icon) > ICON_MAX_AGE) {
				try {
					Snapd.Icon icon = client.get_icon_sync (name, null);
					// written to a temporary file then renamed: no partial icon is left on error
					string? new_etag;
					cached_icon.replace_contents (icon.data.get_data (), null, false, FileCreateFlags.PRIVATE, out new_etag);
				} catch (Error e) {
					// keep the previous icon if any
					if (!cached_icon.query_exists ()) {
						throw e;
					}
				}
			}
			return cached_icon.get_path ();
		}

		// map pamac categories to snap store ones
		static string[] get_snap_categories (string category) {
			switch (category) {
				case "Photo & Video":
					return {"photo-and-video", "art-and-design"};
				case "Music & Audio":
					return {"music-and-audio"};
				case "Productivity":
					return {"productivity", "finance"};
				case "Communication & News":
					return {"social", "news-and-weather", "entertainment"};
				case "Education & Science":
					return {"education", "science"};
				case "Games":
					return {"games"};
				case "Utilities":
					return {"utilities", "health-and-fitness", "personalisation"};
				case "Development":
					return {"development"};
				default:
					return {};
			}
		}

		GenericArray<unowned Snapd.Snap>? find_category_snaps (string snap_category) {
			GenericArray<unowned Snapd.Snap>? found;
			lock (category_snaps_cache) {
				found = category_snaps_cache.lookup (snap_category);
			}
			if (found == null) {
				try {
					found = client.find_category_sync (Snapd.FindFlags.NONE, snap_category, null, null);
				} catch (Error e) {
					warning (e.message);
					return null;
				}
				lock (category_snaps_cache) {
					category_snaps_cache.insert (snap_category, found);
				}
			}
			return found;
		}

		public void get_category_snaps (string category, ref GenericArray<SnapPackage> pkgs) {
			if (category == "Featured") {
				foreach (unowned string name in FEATURED_SNAPS) {
					SnapPackage? pkg = get_snap (name);
					if (pkg != null) {
						pkgs.add (pkg);
					}
				}
				return;
			}
			string[] snap_categories = get_snap_categories (category);
			if (snap_categories.length == 0) {
				return;
			}
			HashTable<string, Snapd.Snap> installed_snaps = get_installed_snaps_table ();
			// a snap can be in several snap categories
			var added = new GenericSet<string> (str_hash, str_equal);
			foreach (unowned string snap_category in snap_categories) {
				GenericArray<unowned Snapd.Snap>? found = find_category_snaps (snap_category);
				if (found != null) {
					add_store_snaps (found, installed_snaps, added, pkgs);
				}
			}
		}

		void emit_error (string message, string[] details) {
			var details_array = new GenericArray<string> (details.length);
			foreach (unowned string detail in details) {
				details_array.add (detail);
			}
			sink.emit_error (message, details_array);
		}

		// a previous transaction can have been cancelled or have failed during a download
		void begin_transaction (TransactionSink sink) {
			this.sink = sink;
			cancellable.reset ();
			downloading = false;
			started_downloads.remove_all ();
			finished_downloads.remove_all ();
		}

		public bool trans_run (TransactionSink sink, string[] to_install, string[] to_remove) {
			begin_transaction (sink);
			foreach (unowned string name in to_remove) {
				if (!remove (name) || cancellable.is_cancelled ()) {
					return false;
				}
			}
			foreach (unowned string name in to_install) {
				if (!install (name) || cancellable.is_cancelled ()) {
					return false;
				}
			}
			return true;
		}

		public void refresh () {
			lock (store_snaps_cache) {
				store_snaps_cache.remove_all ();
				missing_store_snaps.remove_all ();
			}
			lock (search_snaps_cache) {
				search_snaps_cache.remove_all ();
			}
			lock (category_snaps_cache) {
				category_snaps_cache.remove_all ();
			}
			lock (pkgs_cache) {
				pkgs_cache.remove_all ();
			}
		}

		public void trans_cancel (TransactionSink sink) {
			if (sink == this.sink) {
				cancellable.cancel ();
			}
		}

		bool install (string name, string? channel = null) {
			try {
				main_action = dgettext (null, "Installing %s").printf (name);
				init_download = true;
				client.install2_sync (Snapd.InstallFlags.NONE, name, channel, null, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (e is Snapd.Error.NEEDS_CLASSIC) {
					try {
						// confirmation already obtained in transaction.vala
						client.install2_sync (Snapd.InstallFlags.CLASSIC, name, channel, null, progress_callback, cancellable);
						return true;
					} catch (Error e) {
						if (!cancellable.is_cancelled ()) {
							emit_error (dgettext (null, "Snap install error"), {e.message});
						}
					}
				} else if (!cancellable.is_cancelled ()) {
					emit_error (dgettext (null, "Snap install error"), {e.message});
				}
			}
			return false;
		}

		public bool switch_channel (TransactionSink sink, string name, string channel) {
			begin_transaction (sink);
			try {
				main_action = dgettext (null, "Installing %s").printf ("%s (%s)".printf (name, channel));
				init_download = true;
				client.refresh_sync (name, channel, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					emit_error (dgettext (null, "Snap switch error"), {e.message});
				}
			}
			return false;
		}

		bool remove (string name) {
			try {
				main_action = dgettext (null, "Removing %s").printf (name);
				client.remove2_sync (Snapd.RemoveFlags.NONE, name, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					emit_error (dgettext (null, "Snap remove error"), {e.message});
				}
			}
			return false;
		}

		void emit_download (uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			double fraction;
			if (init_download) {
				sink.start_downloading ();
				init_download = false;
				download_rate = 0;
				rates_nb = 0;
				previous_xfered = 0;
				current_progress = 0;
				fraction = 0;
				timer.start ();
			} else {
				double elapsed = timer.elapsed ();
				if (elapsed <= 0.1) {
					return;
				}
				// never negative, even if snapd reports a lower progress
				uint64 new_xfered = xfered > previous_xfered ? xfered - previous_xfered : 0;
				download_rate = ((download_rate * rates_nb) + (uint64) (new_xfered / elapsed)) / (rates_nb + 1);
				rates_nb++;
				previous_xfered = xfered;
				fraction = total > 0 ? (double) xfered / total : 0;
				if (fraction <= 1) {
					text.append ("%s/%s  ".printf (format_size (xfered), format_size (total)));
					uint remaining_seconds = 0;
					if (download_rate > 0) {
						remaining_seconds = (uint) Math.roundf ((float) (total - xfered) / download_rate);
					}
					// display remaining time after 2s
					if (remaining_seconds > 0 && rates_nb > 19) {
						if (remaining_seconds < 60) {
							text.append (dngettext (null, "About %lu second remaining",
										"About %lu seconds remaining", remaining_seconds).printf (remaining_seconds));
						} else {
							uint remaining_minutes = (uint) Math.roundf ((float) remaining_seconds / 60);
							text.append (dngettext (null, "About %lu minute remaining",
										"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
						}
					}
				} else {
					text.append (format_size (xfered));
				}
				timer.start ();
			}
			// the total can grow when the real size of a download replaces its estimation,
			// never display a lower progress
			current_progress = double.max (fraction, current_progress);
			current_status = text.str;
			sink.emit_download_progress (current_action, current_status, current_progress);
		}

		// snapd download task summaries look like: Download snap "name" (rev) from channel "stable",
		// fall back to the whole summary if it has no quoted name
		static string get_download_name (string summary) {
			string[] splitted = summary.split ("\"", 3);
			if (splitted.length < 3 || splitted[1].length == 0) {
				return summary;
			}
			return splitted[1];
		}

		// snapd only gives the size of a download when it starts,
		// use the store size to not increase the total during the download
		uint64 get_estimated_download_size (string name) {
			Snapd.Snap? store_snap = get_store_snap (name);
			if (store_snap != null) {
				return store_snap.download_size;
			}
			return 0;
		}

		void progress_callback (Snapd.Client client, Snapd.Change change, void* deprecated) {
			uint total = 0;
			uint done = 0;
			// all downloads of the change: snapd runs them in parallel
			uint64 download_xfered = 0;
			uint64 download_total = 0;
			bool downloads_pending = false;
			unowned GenericArray<Snapd.Task> tasks = change.get_tasks ();
			foreach (unowned Snapd.Task task in tasks) {
				total++;
				if (task.status == "Done") {
					done++;
				}
				// the summary is translated by snapd, not the kind
				if (task.kind == "download-snap") {
					string pkgname = get_download_name (task.summary);
					// at the beginning task.progress_total = 1 because the download size is unknown
					bool size_known = task.progress_total > 1;
					uint64 size = size_known ? task.progress_total : get_estimated_download_size (pkgname);
					download_total += size;
					switch (task.status) {
						case "Do":
						case "Wait":
							downloads_pending = true;
							break;
						case "Doing":
							downloads_pending = true;
							if (size_known) {
								download_xfered += task.progress_done;
								if (!(pkgname in started_downloads)) {
									current_action = dgettext (null, "Download of %s started").printf (pkgname);
									started_downloads.add (pkgname);
									downloading = true;
								}
							}
							break;
						case "Done":
							download_xfered += size;
							if (pkgname in started_downloads && !(pkgname in finished_downloads)) {
								current_action = dgettext (null, "Download of %s finished").printf (pkgname);
								finished_downloads.add (pkgname);
							}
							break;
						default:
							// aborted or undone
							break;
					}
				} else if (task.status == "Doing" && task.summary != current_details) {
					current_details = task.summary;
					sink.emit_script_output (current_details);
				}
			}
			if (downloading) {
				emit_download (download_xfered, download_total);
				if (!downloads_pending) {
					downloading = false;
					sink.stop_downloading ();
				}
			} else if (total > 0) {
				sink.emit_action_progress (main_action, "", (double) done / total);
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.Snap);
}
