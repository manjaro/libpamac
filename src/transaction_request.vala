/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
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
	// arguments of an alpm transaction run,
	// sent to the daemon as a dictionary (a{sv}):
	// a missing key keeps its default value and an unknown key is ignored
	internal class TransactionRequest {
		public bool sysupgrade;
		public bool enable_downgrade;
		public bool simple_install;
		public bool keep_built_pkgs;
		public int trans_flags;
		public string[] to_install;
		public string[] to_remove;
		public string[] to_load_local;
		public string[] to_load_remote;
		public string[] to_install_as_dep;
		public string[] ignorepkgs;
		public string[] overwrite_files;

		public TransactionRequest () {
			sysupgrade = false;
			enable_downgrade = false;
			simple_install = false;
			keep_built_pkgs = false;
			trans_flags = 0;
			to_install = {};
			to_remove = {};
			to_load_local = {};
			to_load_remote = {};
			to_install_as_dep = {};
			ignorepkgs = {};
			overwrite_files = {};
		}

		public TransactionRequest.from_dict (HashTable<string, Variant> dict) {
			this ();
			sysupgrade = get_bool (dict, "sysupgrade");
			enable_downgrade = get_bool (dict, "enable_downgrade");
			simple_install = get_bool (dict, "simple_install");
			keep_built_pkgs = get_bool (dict, "keep_built_pkgs");
			unowned Variant? flags = dict.lookup ("trans_flags");
			if (flags != null && flags.is_of_type (VariantType.INT32)) {
				trans_flags = flags.get_int32 ();
			}
			to_install = get_strv (dict, "to_install");
			to_remove = get_strv (dict, "to_remove");
			to_load_local = get_strv (dict, "to_load_local");
			to_load_remote = get_strv (dict, "to_load_remote");
			to_install_as_dep = get_strv (dict, "to_install_as_dep");
			ignorepkgs = get_strv (dict, "ignorepkgs");
			overwrite_files = get_strv (dict, "overwrite_files");
		}

		public HashTable<string, Variant> to_dict () {
			var dict = new HashTable<string, Variant> (str_hash, str_equal);
			dict.insert ("sysupgrade", new Variant.boolean (sysupgrade));
			dict.insert ("enable_downgrade", new Variant.boolean (enable_downgrade));
			dict.insert ("simple_install", new Variant.boolean (simple_install));
			dict.insert ("keep_built_pkgs", new Variant.boolean (keep_built_pkgs));
			dict.insert ("trans_flags", new Variant.int32 (trans_flags));
			dict.insert ("to_install", new Variant.strv (to_install));
			dict.insert ("to_remove", new Variant.strv (to_remove));
			dict.insert ("to_load_local", new Variant.strv (to_load_local));
			dict.insert ("to_load_remote", new Variant.strv (to_load_remote));
			dict.insert ("to_install_as_dep", new Variant.strv (to_install_as_dep));
			dict.insert ("ignorepkgs", new Variant.strv (ignorepkgs));
			dict.insert ("overwrite_files", new Variant.strv (overwrite_files));
			return dict;
		}

		static bool get_bool (HashTable<string, Variant> dict, string key) {
			unowned Variant? val = dict.lookup (key);
			return val != null && val.is_of_type (VariantType.BOOLEAN) && val.get_boolean ();
		}

		static string[] get_strv (HashTable<string, Variant> dict, string key) {
			unowned Variant? val = dict.lookup (key);
			if (val == null || !val.is_of_type (VariantType.STRING_ARRAY)) {
				return {};
			}
			return val.dup_strv ();
		}
	}

	// the names of a set, in an array
	internal string[] set_to_strv (GenericSet<string?> set) {
		var array = new GenericArray<string> (set.length);
		foreach (unowned string name in set) {
			array.add (name);
		}
		return array.data;
	}
}
