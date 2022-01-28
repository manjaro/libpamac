/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2022 Guillaume Benoit <guillaume@manjaro.org>
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
	internal class AUR: Object {
		// AUR urls
		const string aur_url = "https://aur.archlinux.org";
		const string db_gz = "packages-meta-ext-v1.json.gz";
		const string rpc_url = aur_url + "/rpc/?v=5";
		const string rpc_search = "&type=search&arg=";
		const string rpc_suggest = "&type=suggest&arg=";
		const string rpc_multiinfo = "&type=info";
		const string rpc_multiinfo_arg = "&arg[]=";
		Config config;
		AlpmUtils alpm_utils;
		Soup.Session session;
		HashTable<unowned string, Json.Object> cached_infos;
		HashTable<string, Json.Array> search_results;
		HashTable<string, Json.Array> suggest_results;
		string real_build_dir;
		bool db_loaded;

		public AUR (Config config, AlpmUtils alpm_utils) {
			this.config = config;
			this.alpm_utils = alpm_utils;
			session = this.alpm_utils.soup_session;
			cached_infos = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
			search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			suggest_results = new HashTable<string, Json.Array> (str_hash, str_equal);
		}

		public unowned string get_real_build_dir () {
			if (real_build_dir == null) {
				if (Posix.geteuid () == 0) {
					// build as root with systemd-run
					// set aur_build_dir to "/var/cache/pamac"
					real_build_dir = "/var/cache/pamac";
				} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
					real_build_dir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
				} else {
					real_build_dir = config.aur_build_dir;
				}
			}
			return real_build_dir;
		}

		void parse_db (bool force = false) {
			if (!force && db_loaded) {
				return;
			}
			string absolute_path = Path.build_filename (get_real_build_dir (), db_gz);
			var zipfile = File.new_for_commandline_arg (absolute_path);
			if (!zipfile.query_exists ()) {
				return;
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
						lock (suggest_results) {
							suggest_results.remove_all ();
						}
						lock (search_results) {
							search_results.remove_all ();
						}
						lock (cached_infos) {
							cached_infos.remove_all ();
							uint array_length = array.get_length ();
							for (uint i = 0; i < array_length; i++) {
								unowned Json.Object json_object = array.get_object_element (i);
								cached_infos.insert (json_object.get_string_member ("Name"), json_object);
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
			var builddir = File.new_for_path (get_real_build_dir ());
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
			// dload defined in alpm_utils.vala
			int ret = dload (alpm_utils, "https://aur.archlinux.org", db_gz, real_build_dir, force, false, emit_signal);
			if (ret < 0) {
				return false;
			}
			if (ret == 0) {
				parse_db (true);
			}
			return true;
		}

		Json.Array? rpc_query (string uri) {
			try {
				var message = new Soup.Message ("GET", uri);
				InputStream input_stream = session.send (message);
				uint status_code = message.status_code;
				if (status_code >= 400) {
					stderr.printf ("Failed to query %s from AUR: error %u\n", uri, status_code);
					return null;
				}
				var parser = new Json.Parser.immutable_new ();
				parser.load_from_stream (input_stream);
				unowned Json.Node? root = parser.get_root ();
				if (root != null) {
					unowned Json.Object obj = root.get_object ();
					if (obj.get_string_member ("type") == "error") {
						unowned string error_details = obj.get_string_member ("error");
						stderr.printf ("Failed to query %s from AUR: %s\n", uri, error_details);
					} else {
						return obj.get_array_member ("results");
					}
				}
			} catch (Error e) {
				stderr.printf ("Failed to query %s from AUR: %s\n", uri, e.message);
			}
			return null;
		}

		Json.Array? multiinfo (GenericArray<string> pkgnames) {
			// query pkgnames hundred by hundred to avoid too long uri error
			// example: ros-lunar-desktop
			if (pkgnames.length <= 200) {
				var builder = new StringBuilder (rpc_url);
				builder.append (rpc_multiinfo);
				foreach (unowned string pkgname in pkgnames) {
					builder.append (rpc_multiinfo_arg);
					builder.append (Uri.escape_string (pkgname));
				}
				return rpc_query (builder.str);
			} else {
				var result = new Json.Array ();
				int index_max = pkgnames.length - 1;
				int index = 0;
				while (index < index_max) {
					var builder = new StringBuilder (rpc_url);
					builder.append (rpc_multiinfo);
					for (int i = 0; i < 200; i++) {
						unowned string pkgname = pkgnames[index];
						builder.append (rpc_multiinfo_arg);
						builder.append (Uri.escape_string (pkgname));
						index++;
						if (index == index_max) {
							break;
						}
					}
					Json.Array? array = rpc_query (builder.str);
					if (array != null) {
						uint array_length = array.get_length ();
						for (uint i = 0; i < array_length; i++) {
							result.add_element (array.dup_element (i));
						}
					}
				}
				return result;
			}
		}

		public unowned Json.Object? get_infos (string pkgname) {
			parse_db ();
			unowned Json.Object? json_object = null;
			lock (cached_infos) {
				json_object = cached_infos.lookup (pkgname);
			}
			if (json_object == null && !db_loaded) {
				var to_query = new GenericArray<string> ();
				to_query.add (pkgname);
				Json.Array? results = multiinfo (to_query);
				if (results != null && results.get_length () == 1) {
					json_object = results.get_object_element (0);
					if (json_object != null) {
						lock (cached_infos) {
							cached_infos.insert (json_object.get_string_member ("Name"), json_object);
						}
					}
				}
			}
			return json_object;
		}

		public GenericArray<Json.Object> get_multi_infos (GenericArray<string> pkgnames) {
			var result = new GenericArray<Json.Object> ();
			var to_query = new GenericArray<string> ();
			parse_db ();
			lock (cached_infos) {
				foreach (unowned string pkgname in pkgnames) {
					unowned Json.Object? json_object = cached_infos.lookup (pkgname);
					if (json_object == null) {
						if (!db_loaded) {
							to_query.add (pkgname);
						}
					} else {
						result.add (json_object);
					}
				}
			}
			if (to_query.length > 0) {
				Json.Array? results = multiinfo (to_query);
				if (results != null) {
					lock (cached_infos) {
						uint results_length = results.get_length ();
						for (uint i = 0; i < results_length; i++) {
							unowned Json.Object json_object = results.get_object_element (i);
							result.add (json_object);
							cached_infos.insert (json_object.get_string_member ("Name"), json_object);
						}
					}
				}
			}
			return result;
		}

		public GenericArray<unowned Json.Object> get_providers (string depend) {
			var objects = new GenericArray<unowned Json.Object> ();
			parse_db ();
			if (db_loaded) {
				lock (cached_infos) {
					var iter = HashTableIter<unowned string, Json.Object> (cached_infos);
					unowned Json.Object object;
					while (iter.next (null, out object)) {
						unowned Json.Node? node = object.get_member ("Provides");
						if (node != null) {
							unowned Json.Array array = node.get_array ();
							uint array_length = array.get_length ();
							for (uint i = 0; i < array_length; i++) {
								unowned string provide = array.get_string_element (i);
								if (provide.has_prefix (depend)) {
									objects.add (object);
								}
							}
						}
					}
				}
			}
			return objects;
		}

		public unowned Json.Array? suggest (string search_string) {
			parse_db ();
			if (db_loaded) {
				return suggest_db (search_string);
			} else {
				return suggest_rpc (search_string);
			}
		}

		public unowned Json.Array? suggest_db (string search_string) {
			unowned Json.Array? suggest_array;
			lock (suggest_results) {
				suggest_array = suggest_results.lookup (search_string);
			}
			if (suggest_array == null) {
				var suggest_array_new = new Json.Array ();
				lock (cached_infos) {
					var iter = HashTableIter<unowned string, Json.Object> (cached_infos);
					unowned Json.Object object;
					while (iter.next (null, out object)) {
						unowned string name = object.get_string_member ("Name");
						if (name.has_prefix (search_string)) {
							suggest_array_new.add_string_element (name);
						}
					}
				}
				lock (suggest_results) {
					suggest_results.insert (search_string, suggest_array_new);
				}
				suggest_array = suggest_array_new;
			}
			return suggest_array;
		}

		public unowned Json.Array? suggest_rpc (string search_string) {
			unowned Json.Array? suggest_array;
			lock (suggest_results) {
				suggest_array = suggest_results.lookup (search_string);
			}
			if (suggest_array == null) {
				var builder = new StringBuilder (rpc_url);
				builder.append (rpc_suggest);
				builder.append (Uri.escape_string (search_string));
				// special query because it return an array of string
				try {
					var message = new Soup.Message ("GET", builder.str);
					InputStream input_stream = session.send (message);
					uint status_code = message.status_code;
					if (status_code >= 400) {
						stderr.printf ("Failed to query %s from AUR: error %u\n", builder.str, status_code);
					} else {
						var parser = new Json.Parser.immutable_new ();
						parser.load_from_stream (input_stream);
						unowned Json.Node? root = parser.get_root ();
						if (root != null) {
							suggest_array = root.get_array ();
							lock (suggest_results) {
								suggest_results.insert (search_string, suggest_array);
							}
						}
					}
				} catch (Error e) {
					stderr.printf ("Failed to query %s from AUR: %s\n", builder.str, e.message);
				}
			}
			return suggest_array;
		}

		public GenericArray<Json.Object> search (string search_string) {
			parse_db ();
			if (db_loaded) {
				return search_db (search_string);
			} else {
				return search_rpc (search_string);
			}
		}

		GenericArray<Json.Object> search_db (string search_string) {
			var needle_match = new GenericArray<Json.Object> ();
			string[] needles = search_string.split (" ");
			if (needles.length == 0) {
				return new GenericArray<Json.Object> ();
			} else {
				unowned string targ = needles[0];
				Regex? regex = null;
				try {
					regex = new Regex (targ);
				} catch (Error e) {
					warning (e.message);
				}
				lock (cached_infos) {
					var iter = HashTableIter<unowned string, Json.Object> (cached_infos);
					unowned Json.Object object;
					while (iter.next (null, out object)) {
						if (find_match (object, targ, regex)) {
							needle_match.add (object);
						}
					}
				}
				uint needles_length = needles.length;
				if (needles_length > 1) {
					GenericArray<Json.Object> all_match = needle_match;
					uint i;
					for (i = 1;  i < needles_length; i++) {
						needle_match = new GenericArray<Json.Object> ();
						targ = needles[i];
						try {
							regex = new Regex (targ);
						} catch (Error e) {
							warning (e.message);
						}
						foreach (unowned Json.Object obj in all_match) {
							if (find_match (obj, targ, regex)) {
								needle_match.add (obj);
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

		bool find_match (Json.Object object, string targ, Regex regex) {
			bool matched = false;
			unowned string name = object.get_string_member ("Name");
			unowned string desc = object.get_string_member ("Description");
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
				unowned Json.Node? node = object.get_member ("Provides");
				if (node != null) {
					unowned Json.Array array = node.get_array ();
					uint array_length = array.get_length ();
					for (uint i = 0; i < array_length; i++) {
						unowned string provide = array.get_string_element (i);
						if (targ == provide || (regex != null && regex.match (provide))) {
							matched = true;
							break;
						}
					}
				}
			}
			if (!matched) {
				// check groups as plain text AND pattern
				unowned Json.Node? node = object.get_member ("Groups");
				if (node != null) {
					unowned Json.Array array = node.get_array ();
					uint array_length = array.get_length ();
					for (uint i = 0; i < array_length; i++) {
						unowned string group = array.get_string_element (i);
						if (targ == group || (regex != null && regex.match (group))) {
							matched = true;
							break;
						}
					}
				}
			}
			return matched;
		}

		GenericArray<Json.Object> search_rpc (string search_string) {
			string[] needles = search_string.split (" ");
			if (needles.length == 0) {
				return new GenericArray<Json.Object> ();
			} else if (needles.length == 1) {
				unowned string needle = needles[0];
				if (needle.length < 2) {
					// query arg too small
					return new GenericArray<Json.Object> ();
				}
				Json.Array? found;
				lock (search_results) {
					found = search_results.lookup (needle);
				}
				if (found == null) {
					var builder = new StringBuilder (rpc_url);
					builder.append (rpc_search);
					builder.append (Uri.escape_string (needle));
					found = rpc_query (builder.str);
				}
				if (found == null) {
					// a error occured, do not cache the result
					return new GenericArray<Json.Object> ();
				}
				lock (search_results) {
					search_results.insert (needle, found);
				}
				var objects = new GenericArray<Json.Object> ();
				uint found_length = found.get_length ();
				for (uint i = 0; i < found_length; i++) {
					objects.add (found.get_object_element (i));
				}
				return objects;
			} else {
				// compute the intersection of all found packages
				var builder = new StringBuilder (rpc_url);
				builder.append (rpc_search);
				var all_found = new GenericArray<Json.Array> ();
				foreach (unowned string needle in needles) {
					if (needle.length < 2) {
						// query arg too small
						continue;
					}
					Json.Array? found;
					lock (search_results) {
						found = search_results.lookup (needle);
					}
					if (found == null) {
						var needle_builder = new StringBuilder (builder.str);
						needle_builder.append (Uri.escape_string (needle));
						found = rpc_query (needle_builder.str);
					}
					if (found == null) {
						// a error occured, just continue
						continue;
					}
					lock (search_results) {
						search_results.insert (needle, found);
					}
					if (found.get_length () == 0) {
						// a zero length array mean the inter length will be zero
						return new GenericArray<Json.Object> ();
					}
					all_found.add (found);
				}
				uint all_found_length = all_found.length;
				// case of all needle search failed
				if (all_found_length == 0) {
					return new GenericArray<Json.Object> ();
				}
				// case of errors occured and only one needle succeed
				if (all_found_length == 1) {
					unowned Json.Array found = all_found[0];
					var objects = new GenericArray<Json.Object> ();
					uint found_length = found.get_length ();
					for (uint i = 0; i < found_length; i++) {
						objects.add (found.get_object_element (i));
					}
					return objects;
				}
				// add first array member in a hash set
				var check_set = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
				unowned Json.Array found = all_found[0];
				uint found_length = found.get_length ();
				uint i;
				for (i = 0; i < found_length; i++) {
					unowned Json.Object object = found.get_object_element (i);
					check_set.insert (object.get_string_member ("Name"), object);
				}
				// compare next array members with check_set
				// and use inter as next check_set
				for (i = 1; i < all_found_length; i++) {
					var inter = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
					found = all_found[i];
					found_length = found.get_length ();
					for (uint j = 0; j < found_length; j++) {
						unowned Json.Object object = found.get_object_element (j);
						unowned string pkgname = object.get_string_member ("Name");
						if (pkgname in check_set) {
							inter.insert (pkgname, object);
						}
					}
					check_set = (owned) inter;
				}
				var objects = new GenericArray<Json.Object> ();
				var iter = HashTableIter<unowned string, Json.Object> (check_set);
				unowned Json.Object object;
				while (iter.next (null, out object)) {
					objects.add (object);
				}
				return objects;
			}
		}
	}
}
