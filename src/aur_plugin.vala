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
	// shares the strings repeated between packages (dependencies, licenses, maintainers…),
	// kept alive by the infos using it
	internal class AURStringPool {
		HashTable<unowned string, string> strings;

		internal AURStringPool () {
			strings = new HashTable<unowned string, string> (str_hash, str_equal);
		}

		internal unowned string intern (string str) {
			unowned string? found = strings.lookup (str);
			if (found != null) {
				return found;
			}
			string copy = str;
			unowned string interned = copy;
			strings.insert (interned, (owned) copy);
			return interned;
		}
	}

	// only the needed data is kept, not the whole json tree which would use a lot of memory
	internal class AURInfosLinked : AURInfos {
		// returned for empty lists, never modified
		static GenericArray<unowned string> empty_array = new GenericArray<unowned string> ();
		// protects the lazily created dates, shared by all instances since creating them is fast
		static Mutex dates_mutex;

		AURStringPool pool;
		string _name;
		string _version;
		string? _desc;
		unowned string? _license;
		string? _url;
		// points to name when they are equal, else to a pool string
		unowned string? _packagebase;
		unowned string? _maintainer;
		GenericArray<unowned string>? _groups;
		GenericArray<unowned string>? _depends;
		GenericArray<unowned string>? _optdepends;
		GenericArray<unowned string>? _makedepends;
		GenericArray<unowned string>? _checkdepends;
		GenericArray<unowned string>? _provides;
		GenericArray<unowned string>? _replaces;
		GenericArray<unowned string>? _conflicts;
		double _popularity;
		uint64 _numvotes;
		int64 lastmodified_time;
		int64 firstsubmitted_time;
		// -1 if not out of date
		int64 outofdate_time;
		DateTime? _lastmodified;
		DateTime? _outofdate;
		DateTime? _firstsubmitted;

		public override string name { get { return _name; } }
		public override string version { get { return _version; } }
		public override string? desc { get { return _desc; } }
		public override string? license { get { return _license ?? dgettext (null, "Unknown"); } }
		public override string? url { get { return _url; } }
		public override GenericArray<string> groups { get { return get_array (_groups); } }
		public override GenericArray<string> depends { get { return get_array (_depends); } }
		public override GenericArray<string> optdepends { get { return get_array (_optdepends); } }
		public override GenericArray<string> makedepends { get { return get_array (_makedepends); } }
		public override GenericArray<string> checkdepends { get { return get_array (_checkdepends); } }
		public override GenericArray<string> provides { get { return get_array (_provides); } }
		public override GenericArray<string> replaces { get { return get_array (_replaces); } }
		public override GenericArray<string> conflicts { get { return get_array (_conflicts); } }
		public override string? packagebase { get { return _packagebase; } }
		public override string? maintainer { get { return _maintainer; } }
		public override double popularity { get { return _popularity; } }
		public override DateTime? lastmodified {
			get {
				dates_mutex.lock ();
				if (_lastmodified == null) {
					_lastmodified = new DateTime.from_unix_local (lastmodified_time);
				}
				dates_mutex.unlock ();
				return _lastmodified;
			}
		}
		public override DateTime? outofdate {
			get {
				if (outofdate_time < 0) {
					return null;
				}
				dates_mutex.lock ();
				if (_outofdate == null) {
					_outofdate = new DateTime.from_unix_local (outofdate_time);
				}
				dates_mutex.unlock ();
				return _outofdate;
			}
		}
		public override DateTime? firstsubmitted {
			get {
				dates_mutex.lock ();
				if (_firstsubmitted == null) {
					_firstsubmitted = new DateTime.from_unix_local (firstsubmitted_time);
				}
				dates_mutex.unlock ();
				return _firstsubmitted;
			}
		}
		public override uint64 numvotes { get { return _numvotes; } }

		AURInfosLinked (string name, Json.Object json_object, AURStringPool pool) {
			this.pool = pool;
			_name = name;
			_version = get_string_member (json_object, "Version") ?? "";
			_desc = get_string_member (json_object, "Description");
			_url = get_string_member (json_object, "URL");
			unowned string? packagebase = get_string_member (json_object, "PackageBase");
			if (packagebase == null || packagebase == _name) {
				// in most cases
				_packagebase = _name;
			} else {
				_packagebase = pool.intern (packagebase);
			}
			unowned string? maintainer = get_string_member (json_object, "Maintainer");
			if (maintainer != null) {
				_maintainer = pool.intern (maintainer);
			}
			GenericArray<unowned string>? licenses = get_array_member (json_object, "License");
			if (licenses != null) {
				var license_str = new StringBuilder (licenses[0]);
				for (uint i = 1; i < licenses.length; i++) {
					license_str.append_c (' ');
					license_str.append (licenses[i]);
				}
				_license = pool.intern (license_str.str);
			}
			_groups = get_array_member (json_object, "Groups");
			_depends = get_array_member (json_object, "Depends");
			_optdepends = get_array_member (json_object, "OptDepends");
			_makedepends = get_array_member (json_object, "MakeDepends");
			_checkdepends = get_array_member (json_object, "CheckDepends");
			_provides = get_array_member (json_object, "Provides");
			_replaces = get_array_member (json_object, "Replaces");
			_conflicts = get_array_member (json_object, "Conflicts");
			unowned Json.Node? node = get_value_member (json_object, "Popularity");
			_popularity = node != null ? node.get_double () : 0;
			node = get_value_member (json_object, "NumVotes");
			_numvotes = node != null ? (uint64) node.get_int () : 0;
			node = get_value_member (json_object, "LastModified");
			lastmodified_time = node != null ? node.get_int () : 0;
			node = get_value_member (json_object, "FirstSubmitted");
			firstsubmitted_time = node != null ? node.get_int () : 0;
			node = get_value_member (json_object, "OutOfDate");
			outofdate_time = node != null ? node.get_int () : -1;
		}

		// null if the object has no name
		internal static AURInfosLinked? from_json (Json.Object json_object, AURStringPool pool) {
			unowned string? name = get_string_member (json_object, "Name");
			if (name == null) {
				return null;
			}
			return new AURInfosLinked (name, json_object, pool);
		}

		// null if the member is missing or has a null value
		static unowned Json.Node? get_value_member (Json.Object json_object, string member) {
			unowned Json.Node? node = json_object.get_member (member);
			if (node == null || node.get_node_type () != Json.NodeType.VALUE) {
				return null;
			}
			return node;
		}

		static unowned string? get_string_member (Json.Object json_object, string member) {
			unowned Json.Node? node = get_value_member (json_object, member);
			if (node == null || node.get_value_type () != typeof (string)) {
				return null;
			}
			return node.get_string ();
		}

		// null if empty, to not allocate an array for each package
		GenericArray<unowned string>? get_array_member (Json.Object json_object, string member) {
			unowned Json.Node? node = json_object.get_member (member);
			if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
				return null;
			}
			unowned Json.Array json_array = node.get_array ();
			uint length = json_array.get_length ();
			if (length == 0) {
				return null;
			}
			var array = new GenericArray<unowned string> (length);
			for (uint i = 0; i < length; i++) {
				unowned Json.Node element = json_array.get_element (i);
				if (element.get_value_type () == typeof (string)) {
					array.add (pool.intern (element.get_string ()));
				}
			}
			return array.length > 0 ? array : null;
		}

		// the strings are owned by the pool, the array has no free function
		static unowned GenericArray<string> get_array (GenericArray<unowned string>? array) {
			return (GenericArray<string>) (array ?? empty_array);
		}
	}

	internal class AUR : Object, AURPlugin {
		const string DB_FILENAME = "packages-meta-ext-v1.json.gz";
		string db_path;
		// replaced when the database file changes, protected by lock (cached_infos)
		HashTable<unowned string, AURInfosLinked> cached_infos;
		// serialises the database (re)loading
		Mutex load_mutex;
		// modification time and size of the loaded file, null if never checked
		string? loaded_file_stamp;
		string real_build_dir;

		public AUR () {
			Object ();
		}

		construct {
			cached_infos = new HashTable<unowned string, AURInfosLinked> (str_hash, str_equal);
			// the database is downloaded by alpm_utils in the sync dbs directory
			var alpm_config = new AlpmConfig ("/etc/pacman.conf");
			db_path = Path.build_filename (alpm_config.dbpath, "sync", DB_FILENAME);
		}

		public unowned string get_real_build_dir () {
			return real_build_dir;
		}

		public void set_real_build_dir (string config_aur_build_dir) {
			string new_build_dir;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				new_build_dir = "/var/cache/pamac";
			} else if (config_aur_build_dir == "/var/tmp" || config_aur_build_dir == "/tmp") {
				new_build_dir = Path.build_filename (config_aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
				// the path is predictable in a shared directory:
				// another user could create it first and modify build files
				if (!is_private_dir (new_build_dir)) {
					string fallback = Path.build_filename (Environment.get_user_cache_dir (), "pamac", "build");
					warning ("%s is not a private directory, using %s", new_build_dir, fallback);
					DirUtils.create_with_parents (fallback, 0700);
					new_build_dir = (owned) fallback;
				}
			} else {
				new_build_dir = config_aur_build_dir;
			}
			// only replace the string if needed, callers may hold an unowned reference
			if (new_build_dir != real_build_dir) {
				real_build_dir = (owned) new_build_dir;
			}
		}

		string get_file_stamp (File file) {
			try {
				FileInfo info = file.query_info (FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC + "," + FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
				return "%s.%u:%s".printf (info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED).to_string (),
											info.get_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC),
											info.get_size ().to_string ());
			} catch (Error e) {
				if (!(e is IOError.NOT_FOUND)) {
					warning ("Failed to read AUR data from %s: %s", db_path, e.message);
				}
				return "";
			}
		}

		// (re)load the database if the file changed since the last load,
		// e.g. after a refresh, the check is a simple stat
		void ensure_loaded () {
			load_mutex.lock ();
			var file = File.new_for_path (db_path);
			string stamp = get_file_stamp (file);
			if (stamp != loaded_file_stamp) {
				// remember the stamp even on error to not parse a broken file at each call
				loaded_file_stamp = stamp;
				var new_infos = new HashTable<unowned string, AURInfosLinked> (str_hash, str_equal);
				if (stamp != "") {
					parse_db (file, new_infos);
				}
				lock (cached_infos) {
					cached_infos = new_infos;
				}
			}
			load_mutex.unlock ();
		}

		void parse_db (File file, HashTable<unowned string, AURInfosLinked> infos) {
			var pool = new AURStringPool ();
			try {
				// the file has one package object per line, parse them one by one
				// to not build the whole json tree in memory
				var stream = new DataInputStream (new ConverterInputStream (file.read (), new ZlibDecompressor (ZlibCompressorFormat.GZIP)));
				var parser = new Json.Parser.immutable_new ();
				string? line;
				while ((line = stream.read_line ()) != null) {
					unowned string? json = trim_line (line);
					if (json == null) {
						continue;
					}
					try {
						parser.load_from_data (json, -1);
					} catch (Error e) {
						// unexpected format
						infos.remove_all ();
						parse_db_whole (file, infos, pool);
						return;
					}
					add_infos (parser.get_root (), infos, pool);
				}
			} catch (Error e) {
				warning ("Failed to read AUR data from %s: %s", db_path, e.message);
			}
		}

		// remove the array delimiters around an object line, null if nothing remains
		static unowned string? trim_line (string line) {
			unowned string start = line;
			while (start[0] == '[' || start[0] == ' ' || start[0] == '\t') {
				start = (string) ((char*) start + 1);
			}
			long length = start.length;
			while (length > 0 && (start[length - 1] == ']' || start[length - 1] == ',' || start[length - 1].isspace ())) {
				length--;
			}
			if (length == 0) {
				return null;
			}
			// line is owned by the caller and can be modified
			((char*) start)[length] = '\0';
			return start;
		}

		void parse_db_whole (File file, HashTable<unowned string, AURInfosLinked> infos, AURStringPool pool) {
			try {
				var stream = new ConverterInputStream (file.read (), new ZlibDecompressor (ZlibCompressorFormat.GZIP));
				var parser = new Json.Parser.immutable_new ();
				parser.load_from_stream (stream);
				unowned Json.Node? root = parser.get_root ();
				if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
					warning ("Failed to read AUR data from %s", db_path);
					return;
				}
				foreach (unowned Json.Node node in root.get_array ().get_elements ()) {
					add_infos (node, infos, pool);
				}
			} catch (Error e) {
				warning ("Failed to read AUR data from %s: %s", db_path, e.message);
			}
		}

		static void add_infos (Json.Node? node, HashTable<unowned string, AURInfosLinked> infos, AURStringPool pool) {
			if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
				return;
			}
			AURInfosLinked? data = AURInfosLinked.from_json (node.get_object (), pool);
			if (data != null) {
				// the key is owned by data
				infos.replace (data.name, data);
			}
		}

		public AURInfos? get_infos (string pkgname) {
			ensure_loaded ();
			lock (cached_infos) {
				return cached_infos.lookup (pkgname);
			}
		}

		// returned infos are owned: the database can be reloaded meanwhile
		public GenericArray<AURInfos> get_multi_infos (GenericArray<string> pkgnames) {
			var result = new GenericArray<AURInfos> ();
			ensure_loaded ();
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

		// name of a dependency or provide without version constraint
		static string get_dep_name (string dep) {
			for (int i = 0; i < dep.length; i++) {
				char c = dep[i];
				if (c == '<' || c == '=' || c == '>') {
					return dep.substring (0, i);
				}
			}
			return dep;
		}

		// same rules as pacman: an unversioned provide doesn't satisfy a versioned dependency
		static bool provide_satisfies (string provide, Alpm.Depend dep) {
			Alpm.Depend prov = Alpm.Depend.from_string (provide);
			if (dep.mod == Alpm.Depend.Mode.ANY) {
				return true;
			}
			if (prov.mod != Alpm.Depend.Mode.EQ || prov.version == null || dep.version == null) {
				return false;
			}
			int cmp = Alpm.pkg_vercmp (prov.version, dep.version);
			switch (dep.mod) {
				case Alpm.Depend.Mode.EQ:
					return cmp == 0;
				case Alpm.Depend.Mode.GE:
					return cmp >= 0;
				case Alpm.Depend.Mode.LE:
					return cmp <= 0;
				case Alpm.Depend.Mode.GT:
					return cmp > 0;
				case Alpm.Depend.Mode.LT:
					return cmp < 0;
				default:
					return false;
			}
		}

		public GenericArray<AURInfos> get_providers (string depend) {
			var result = new GenericArray<AURInfos> ();
			Alpm.Depend dep = Alpm.Depend.from_string (depend);
			ensure_loaded ();
			lock (cached_infos) {
				var iter = HashTableIter<unowned string, AURInfosLinked> (cached_infos);
				unowned AURInfosLinked data;
				while (iter.next (null, out data)) {
					foreach (unowned string provide in data.provides) {
						// compare names first to avoid parsing all provides
						if (get_dep_name (provide) == dep.name && provide_satisfies (provide, dep)) {
							result.add (data);
							break;
						}
					}
				}
			}
			return result;
		}

		// AND search: a package matches if each term matches its name, description, provides or groups,
		// terms are case insensitive regexes like with pacman -Ss
		public GenericArray<AURInfos> search (string search_string) {
			var result = new GenericArray<AURInfos> ();
			string[] terms = {};
			Regex?[] regexes = {};
			foreach (unowned string term in search_string.split (" ")) {
				if (term == "") {
					continue;
				}
				Regex? regex = null;
				try {
					regex = new Regex (term, RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE);
				} catch (Error e) {
					// not a valid regex: it will be searched as plain text
				}
				terms += term.down ();
				regexes += (owned) regex;
			}
			if (terms.length == 0) {
				return result;
			}
			ensure_loaded ();
			lock (cached_infos) {
				var iter = HashTableIter<unowned string, AURInfosLinked> (cached_infos);
				unowned AURInfosLinked data;
				while (iter.next (null, out data)) {
					bool all_matched = true;
					for (int i = 0; i < terms.length; i++) {
						if (!find_match (data, terms[i], regexes[i])) {
							all_matched = false;
							break;
						}
					}
					if (all_matched) {
						result.add (data);
					}
				}
			}
			return result;
		}

		static bool string_matches (string str, string term, Regex? regex) {
			if (regex != null) {
				return regex.match (str);
			}
			return term in str.down ();
		}

		static bool find_match (AURInfosLinked data, string term, Regex? regex) {
			if (string_matches (data.name, term, regex)) {
				return true;
			}
			unowned string? desc = data.desc;
			if (desc != null && string_matches (desc, term, regex)) {
				return true;
			}
			foreach (unowned string provide in data.provides) {
				if (string_matches (provide, term, regex)) {
					return true;
				}
			}
			foreach (unowned string group in data.groups) {
				if (string_matches (group, term, regex)) {
					return true;
				}
			}
			return false;
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.AUR);
}
