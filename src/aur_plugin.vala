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
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {
	internal class AURInfosLinked : AURInfos {
		Json.Object? json_object;
		bool license_set;
		unowned string _name;
		unowned string _version;
		unowned string? _desc;
		string? _license;
		unowned string? _url;
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		unowned string? _packagebase;
		unowned string? _maintainer;
		double _popularity;
		DateTime _lastmodified;
		DateTime? _outofdate;
		DateTime _firstsubmitted;
		uint64 _numvotes;

		public override string name {
			get {
				if (_name == null && json_object != null) {
					_name = json_object.get_string_member ("Name");
				}
				return _name;
			}
		}
		public override string version {
			get {
				if (_version == null && json_object != null) {
					_version = json_object.get_string_member ("Version");
				}
				return _version;
			}
		}
		public override string? desc {
			get {
				if (_desc == null && json_object != null) {
					unowned Json.Node? node = json_object.get_member ("Description");
					if (node != null) {
						_desc = node.get_string ();
					}
				}
				return _desc;
			}
		}
		public override string? license {
			get {
				if (_license == null && !license_set) {
					license_set = true;
					if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("License");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							var license_str = new StringBuilder (json_array.get_string_element (0));
							uint json_array_length = json_array.get_length ();
							for (uint i = 1; i < json_array_length; i++) {
								license_str.append (" ");
								license_str.append (json_array.get_string_element (i));
							}
							_license = (owned) license_str.str;
						} else {
							_license = dgettext (null, "Unknown");
						}
					}
				}
				return _license;
			}
		}
		public override string? url {
			get {
				if (_url == null && json_object != null) {
					unowned Json.Node? node = json_object.get_member ("URL");
					if (node != null) {
						_url = node.get_string ();
					}
				}
				return _url;
			}
		}
		public override GenericArray<string> groups {
			get {
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					get_property_array ("Groups", ref _groups);
				}
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					get_property_array ("Depends", ref _depends);
				}
				return _depends;
			}
		}
		public override GenericArray<string> optdepends {
			get {
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					get_property_array ("OptDepends", ref _optdepends);
				}
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					get_property_array ("MakeDepends", ref _makedepends);
				}
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					get_property_array ("CheckDepends", ref _checkdepends);
				}
				return _checkdepends;
			}
		}
		public override GenericArray<string> provides {
			get {
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					get_property_array ("Provides", ref _provides);
				}
				return _provides;
			}
		}
		public override GenericArray<string> replaces {
			get {
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					get_property_array ("Replaces", ref _replaces);
				}
				return _replaces;
			}
		}
		public override GenericArray<string> conflicts {
			get {
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					get_property_array ("Conflicts", ref _conflicts);
				}
				return _conflicts;
			}
		}
		public override string? packagebase {
			get {
				if (_packagebase == null && json_object != null) {
					_packagebase = json_object.get_string_member ("PackageBase");
				}
				return _packagebase;
			}
		}
		public override string? maintainer {
			get {
				if (_maintainer == null && json_object != null) {
					_maintainer = json_object.get_string_member ("Maintainer");
				}
				return _maintainer;
			}
		}
		public override double popularity {
			get {
				if (_popularity == 0 && json_object != null) {
					_popularity = json_object.get_double_member ("Popularity");
				}
				return _popularity;
			}
		}
		public override DateTime? lastmodified {
			get {
				if (_lastmodified == null && json_object != null) {
					_lastmodified = new DateTime.from_unix_local (json_object.get_int_member ("LastModified"));
				}
				return _lastmodified;
			}
		}
		public override DateTime? outofdate {
			get {
				if (_outofdate == null && json_object != null) {
					unowned Json.Node? node = json_object.get_member ("OutOfDate");
					if (!node.is_null ()) {
						_outofdate = new DateTime.from_unix_local (node.get_int ());
					}
				}
				return _outofdate;
			}
		}
		public override DateTime? firstsubmitted {
			get {
				if (_firstsubmitted == null && json_object != null) {
					_firstsubmitted = new DateTime.from_unix_local (json_object.get_int_member ("FirstSubmitted"));
				}
				return _firstsubmitted;
			}
		}
		public override uint64 numvotes {
			get {
				if (_numvotes == 0) {
					_numvotes = (uint64) json_object.get_int_member ("NumVotes");
				}
				return _numvotes;
			}
		}

		internal AURInfosLinked (Json.Object? json_object) {
			this.json_object = json_object;
		}

		void get_property_array (string property, ref GenericArray<string> array) {
			if (json_object != null) {
				unowned Json.Node? node = json_object.get_member (property);
				if (node != null) {
					unowned Json.Array? json_array = node.get_array ();
					if (json_array != null) {
						uint json_array_length = json_array.get_length ();
						for (uint i = 0; i < json_array_length; i++) {
							array.add (json_array.get_string_element (i));
						}
					}
				}
			}
		}
	}

	internal class AUR : Object, AURPlugin {
		// AUR urls
		const string aur_url = "https://aur.archlinux.org";
		const string db_gz = "packages-meta-ext-v1.json.gz";
		const string db_path = "/var/tmp/pamac";
		Soup.Session soup_session;
		HashTable<string, AURInfosLinked> cached_infos;
		HashTable<string, GenericArray<AURInfosLinked>> search_results;
		string real_build_dir;
		bool db_loaded;
		// download data
		Cancellable cancellable;
		uint64 already_downloaded;
		double current_progress;
		public Timer rate_timer;
		Queue<double?> download_rates;
		double download_rate;

		public AUR () {
			Object ();
		}

		construct {
			cancellable = new Cancellable ();
			rate_timer = new Timer ();
			download_rates = new Queue<double?> ();
			cached_infos = new HashTable<string, AURInfosLinked> (str_hash, str_equal);
			search_results = new HashTable<string, GenericArray<Pamac.AURInfosLinked>> (str_hash, str_equal);
			// get_user_agent defined in utils.vala
			string user_agent = get_user_agent ();
			soup_session = new Soup.Session ();
			soup_session.user_agent = user_agent;
			// set a little timeout, aur should be fast
			soup_session.timeout = 1;
		}

		public unowned string get_real_build_dir () {
			return real_build_dir;
		}

		public void set_real_build_dir (string config_aur_build_dir) {
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				real_build_dir = "/var/cache/pamac";
			} else if (config_aur_build_dir == "/var/tmp" || config_aur_build_dir == "/tmp") {
				real_build_dir = Path.build_filename (config_aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_build_dir = config_aur_build_dir;
			}
		}

		void parse_db (bool force = false) {
			if (!force && db_loaded) {
				return;
			}
			string absolute_path = Path.build_filename (db_path, db_gz);
			var zipfile = File.new_for_path (absolute_path);
			if (!zipfile.query_exists ()) {
				message ("downloading AUR data");
				update_db (false, false);
			}
			try {
				// decompress gzip
				var src_stream = zipfile.read ();
				var dst_stream = new MemoryOutputStream (null, GLib.realloc, GLib.free);
				var conv_stream = new ConverterOutputStream (dst_stream, new ZlibDecompressor (ZlibCompressorFormat.GZIP));
				// pumps all data from an InputStream to an OutputStream
				conv_stream.splice (src_stream, 0);
				// parse data
				var parser = new Json.Parser.immutable_new ();
				parser.load_from_data ((string) dst_stream.get_data ());
				unowned Json.Node? root = parser.get_root ();
				if (root == null) {
					stderr.printf ("Failed to read AUR data from %s\n", absolute_path);
				} else {
					unowned Json.Array? array = root.get_array ();
					if (array == null) {
						stderr.printf ("Failed to read AUR data from %s\n", absolute_path);
					} else {
						lock (search_results) {
							search_results.remove_all ();
						}
						lock (cached_infos) {
							cached_infos.remove_all ();
							uint array_length = array.get_length ();
							for (uint i = 0; i < array_length; i++) {
								unowned Json.Object json_object = array.get_object_element (i);
								var data = new AURInfosLinked (json_object);
								cached_infos.insert (data.name, data);
							}
							db_loaded = true;
						}
					}
				}
			} catch (Error e) {
				stderr.printf ("Failed to read AUR data from %s : %s\n", absolute_path, e.message);
			}
		}

		public bool update_db (bool force_refresh, bool emit_signal) {
			var builddir = File.new_for_path (db_path);
			if (!builddir.query_exists ()) {
				try {
					builddir.make_directory_with_parents ();
				} catch (Error e) {
					warning (e.message);
					return false;
				}
			}
			int force = 0;
			if (force_refresh) {
				force = 1;
			}
			string server = "https://aur.manjaro.org";
			string? id = get_os_id ();
			if (id == null || id != "manjaro") {
				server = aur_url;
			}
			// dload defined in alpm_utils.vala
			int ret = dload (server, db_gz, db_path, force, false, emit_signal);
			if (ret < 0) {
				return false;
			}
			if (ret == 0) {
				parse_db (true);
			}
			return true;
		}

		int dload (string mirror, string filename, string localpath, int force, bool parallel, bool emit_signals) {
			if (cancellable.is_cancelled ()) {
				return -1;
			}
			string url =  Path.build_filename (mirror, filename);
			var destfile = File.new_for_path (Path.build_filename (localpath, filename));
			var tempfile = File.new_for_path (destfile.get_path () + ".part");
			int64 size = 0;
			string? last_modified = null;
			var emit_timer = new Timer ();
			try {
				var message = new Soup.Message ("GET", url);
				if (force == 0 && destfile.query_exists ()) {
					// start from scratch only download if our local is out of date.
					FileInfo info = destfile.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
					DateTime time = info.get_modification_date_time ();
					message.request_headers.append ("If-Modified-Since", Soup.date_time_to_string (time, Soup.DateFormat.HTTP));
				}
				if (tempfile.query_exists ()) {
					// removing partial download
					tempfile.delete ();
				}
				InputStream input = soup_session.send (message);
				if (message.status_code == 304) {
					// not modified, our existing file is up to date
					return 1;
				}
				if (message.status_code >= 400) {
					return -1;
				}
				size = message.response_headers.get_content_length ();
				last_modified = message.response_headers.get_one ("Last-Modified");
				FileOutputStream output = tempfile.create (FileCreateFlags.NONE);
				uint64 progress = 0;
				uint8[] buf = new uint8[8192];
				// start download
				already_downloaded= 0;
				current_progress = 0;
				if (emit_signals) {
					emit_download (0, size);
					emit_timer.start ();
				}
				while (true) {
					ssize_t read = input.read (buf, cancellable);
					if (read == 0) {
						// End of file reached
						break;
					}
					output.write (buf[0:read]);
					if (cancellable.is_cancelled ()) {
						break;
					}
					progress += read;
					if (emit_signals && emit_timer.elapsed () > 0.1) {
						emit_download (progress, size);
						// reinitialize emit_timer
						emit_timer.start ();
					}
				}
			} catch (Error e) {
				// cancelled download goes here
				if (e.code != IOError.CANCELLED) {
					// workaround for #1305
					if (e.message == "Unacceptable TLS certificate") {
						// return no error
						return 0;
					}
					emit_download_error ("%s: %s".printf (url, e.message));
				}
				emit_timer.stop ();
				try {
					if (tempfile.query_exists ()) {
						tempfile.delete ();
					}
				} catch (Error e) {
					warning (e.message);
				}
				return -1;
			}
			// download succeeded
			if (emit_signals) {
				emit_timer.stop ();
				emit_download (size, size);
			}
			try {
				tempfile.move (destfile, FileCopyFlags.OVERWRITE);
				// set modification time
				if (last_modified != null) {
					var datetime = Soup.date_time_new_from_http_string (last_modified);
					FileInfo info = destfile.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
					info.set_modification_date_time (datetime);
					destfile.set_attributes_from_info (info, FileQueryInfoFlags.NONE);
				}
				return 0;
			} catch (Error e) {
				warning (e.message);
				return -1;
			}
		}

		void emit_download (uint64 xfered, uint64 total) {
			// this will be run in the threadpool
			if (xfered == 0) {
				rate_timer.start ();
				download_rates.clear ();
				download_rate = 0;
			}
			var text = new StringBuilder ("%s".printf (format_size (xfered)));
			// if previous progress is out of limit no need to continue
			if (current_progress < 1) {
				double fraction = (double) xfered / total;
				if (fraction <= 1) {
					text.append ("/%s".printf (format_size (total)));
					double elapsed = rate_timer.elapsed ();
					if (elapsed > 1) {
						double current_rate = (xfered - already_downloaded) / elapsed;
						already_downloaded = xfered;
						// only keep the last 10 rates
						if (download_rates.length > 10) {
							download_rates.pop_head ();
						}
						download_rates.push_tail (current_rate);
						if (xfered == total) {
							rate_timer.stop ();
						} else {
							// reinitialize rate_timer
							rate_timer.start ();
						}
						// calculate download on the last 10 rates
						if (download_rates.length == 10) {
							double total_rates = 0;
							foreach (double previous_rate in download_rates.head) {
								total_rates += previous_rate;
							}
							download_rate = total_rates /10;
						}
					}
					if (download_rate > 0) {
						uint remaining_seconds = (uint) Math.round ((total - xfered) / download_rate);
						// display remaining
						text.append (" ");
						if (remaining_seconds > 0) {
							if (remaining_seconds < 60) {
								text.append (dngettext (null, "About %lu second remaining",
											"About %lu seconds remaining", remaining_seconds).printf (remaining_seconds));
							} else {
								uint remaining_minutes = (uint) Math.round (remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					}
				} else {
					fraction = 1;
					// rate_timer no more needed
					rate_timer.stop ();
				}
				if (fraction != current_progress) {
					current_progress = fraction;
				}
			}
			emit_download_progress (text.str, current_progress);
		}

		public AURInfos? get_infos (string pkgname) {
			AURInfosLinked? data = null;
			parse_db ();
			lock (cached_infos) {
				data = cached_infos.lookup (pkgname);
			}
			return data;
		}

		public GenericArray<unowned AURInfos> get_multi_infos (GenericArray<string> pkgnames) {
			var result = new GenericArray<unowned AURInfosLinked> ();
			parse_db ();
			lock (cached_infos) {
				foreach (unowned string pkgname in pkgnames) {
					unowned AURInfosLinked? data = cached_infos.lookup (pkgname);
					if (data != null) {
						result.add (data);
					}
				}
			}
			return result;
		}

		public GenericArray<unowned AURInfos> get_providers (string depend) {
			var result = new GenericArray<unowned AURInfosLinked> ();
			parse_db ();
			lock (cached_infos) {
				var iter = HashTableIter<string, AURInfosLinked> (cached_infos);
				unowned AURInfosLinked data;
				while (iter.next (null, out data)) {
					foreach (unowned string provide in data.provides) {
						if (provide.has_prefix (depend)) {
							result.add (data);
						}
					}
				}
			}
			return result;
		}

		public GenericArray<AURInfos> search (string search_string) {
			parse_db ();
			var needle_match = new GenericArray<AURInfosLinked> ();
			string[] needles = search_string.split (" ");
			if (needles.length == 0) {
				return new GenericArray<AURInfosLinked> ();
			} else {
				unowned string targ = needles[0];
				Regex? regex = null;
				try {
					regex = new Regex (targ);
				} catch (Error e) {
					warning (e.message);
				}
				lock (cached_infos) {
					var iter = HashTableIter<string, AURInfosLinked> (cached_infos);
					unowned AURInfosLinked data;
					while (iter.next (null, out data)) {
						if (find_match (data, targ, regex)) {
							needle_match.add (data);
						}
					}
				}
				uint needles_length = needles.length;
				if (needles_length > 1) {
					GenericArray<AURInfosLinked> all_match = needle_match;
					uint i;
					for (i = 1;  i < needles_length; i++) {
						needle_match = new GenericArray<AURInfosLinked> ();
						targ = needles[i];
						try {
							regex = new Regex (targ);
						} catch (Error e) {
							warning (e.message);
						}
						foreach (unowned AURInfosLinked data in all_match) {
							if (find_match (data, targ, regex)) {
								needle_match.add (data);
							}
						}
						// use the returned list for the next needle
						// this allows for AND-based package searching
						all_match = needle_match;
					}
					return all_match;
				} else {
					return needle_match;
				}
			}
		}

		bool find_match (AURInfosLinked data, string targ, Regex regex) {
			bool matched = false;
			unowned string name = data.name;
			unowned string desc = data.desc;
			// check name as plain text AND pattern
			if (name != null && (targ == name || targ == name.down () || (regex != null && regex.match (name)))) {
				matched = true;
			}
			// check if desc contains targ
			else if (desc != null && (targ in desc)) {
				matched = true;
			}
			if (!matched) {
				// check provides as plain text AND pattern
				foreach (unowned string provide in data.provides) {
					if (targ == provide || (regex != null && regex.match (provide))) {
						matched = true;
						break;
					}
				}
			}
			if (!matched) {
				// check groups as plain text AND pattern
				foreach (unowned string group in data.groups) {
					if (targ == group || (regex != null && regex.match (group))) {
						matched = true;
						break;
					}
				}
			}
			return matched;
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.AUR);
}
