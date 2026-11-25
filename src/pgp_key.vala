/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
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
	// informations about a PGP key found on a keyserver,
	// given to the user before importing it
	public class PGPKey : Object {
		// the key as requested in the package build files
		public string key { get; internal set; }
		// fingerprint or key id returned by the keyserver
		public string? keyserver_id { get; internal set; }
		public string? algorithm { get; internal set; }
		public uint length { get; internal set; }
		public DateTime? creation_date { get; internal set; }
		public DateTime? expiration_date { get; internal set; }
		public GenericArray<string> uids { get; internal set; }
		public bool revoked { get; internal set; }
		public bool disabled { get; internal set; }
		public bool expired { get; internal set; }
		// number of keys matching the request on the keyserver
		public uint matching_keys { get; internal set; }
		// keyserver configured in gpg
		public string? keyserver { get; internal set; }
		// address of the keyserver which answered
		public string? keyserver_address { get; internal set; }
		// package which build files require the key
		public string pkgname { get; internal set; }

		internal PGPKey (string key, string pkgname) {
			Object (key: key, pkgname: pkgname);
			uids = new GenericArray<string> ();
		}

		// parse the output of gpg --with-colons --search-keys run with LC_ALL=C
		internal void parse_search_output (string line) {
			if (line.has_prefix ("gpg: data source: ")) {
				keyserver_address = line.substring ("gpg: data source: ".length).strip ();
				return;
			}
			string[] fields = line.split (":");
			if (fields[0] == "pub") {
				matching_keys++;
				// only keep the first key found
				if (matching_keys > 1) {
					return;
				}
				// pub:<keyid>:<algo>:<keylen>:<creationdate>:<expirationdate>:<flags>
				if (fields.length > 1 && fields[1] != "") {
					keyserver_id = fields[1];
				}
				if (fields.length > 2 && fields[2] != "") {
					algorithm = get_algorithm_name (fields[2]);
				}
				if (fields.length > 3 && fields[3] != "") {
					length = (uint) uint64.parse (fields[3]);
				}
				if (fields.length > 4) {
					creation_date = parse_date (fields[4]);
				}
				if (fields.length > 5) {
					expiration_date = parse_date (fields[5]);
				}
				if (fields.length > 6) {
					revoked = "r" in fields[6];
					disabled = "d" in fields[6];
					expired = "e" in fields[6];
				}
				if (expiration_date != null && expiration_date.compare (new DateTime.now_utc ()) < 0) {
					expired = true;
				}
			} else if (fields[0] == "uid" && matching_keys == 1) {
				// uid:<escaped uid string>:<creationdate>:<expirationdate>:<flags>
				if (fields.length > 1 && fields[1] != "") {
					string? uid = Uri.unescape_string (fields[1]);
					uids.add (uid ?? fields[1]);
				}
			}
		}

		// the key requested by the build files is a fingerprint or a key id,
		// check that the key found ends with it
		public bool match_key () {
			if (keyserver_id == null) {
				return false;
			}
			string requested = key.up ();
			if (requested.has_prefix ("0X")) {
				requested = requested.substring (2);
			}
			string found = keyserver_id.up ();
			return requested.has_suffix (found) || found.has_suffix (requested);
		}

		// fingerprint split in groups of 4 characters for readability
		public string get_formatted_fingerprint () {
			string fingerprint = keyserver_id ?? key;
			var builder = new StringBuilder ();
			for (int i = 0; i < fingerprint.length; i++) {
				if (i > 0 && i % 4 == 0) {
					builder.append_c (' ');
				}
				builder.append_c (fingerprint[i]);
			}
			return builder.str.up ();
		}

		// translated "label: value" lines describing the key
		public GenericArray<string> get_details () {
			var details = new GenericArray<string> ();
			details.add ("%s: %s".printf (dgettext (null, "Fingerprint"), get_formatted_fingerprint ()));
			if (uids.length == 0) {
				details.add ("%s: %s".printf (dgettext (null, "Owner"), dgettext (null, "Unknown")));
			} else {
				foreach (unowned string uid in uids) {
					details.add ("%s: %s".printf (dgettext (null, "Owner"), uid));
				}
			}
			if (algorithm != null) {
				if (length > 0) {
					details.add ("%s: %s %u".printf (dgettext (null, "Algorithm"), algorithm, length));
				} else {
					details.add ("%s: %s".printf (dgettext (null, "Algorithm"), algorithm));
				}
			}
			if (creation_date != null) {
				details.add ("%s: %s".printf (dgettext (null, "Creation date"), creation_date.to_local ().format ("%x")));
			}
			if (expiration_date != null) {
				details.add ("%s: %s".printf (dgettext (null, "Expiration date"), expiration_date.to_local ().format ("%x")));
			} else {
				details.add ("%s: %s".printf (dgettext (null, "Expiration date"), dgettext (null, "Never")));
			}
			string source;
			if (keyserver != null && keyserver_address != null) {
				source = "%s (%s)".printf (keyserver, keyserver_address);
			} else {
				source = keyserver ?? keyserver_address ?? dgettext (null, "Unknown keyserver");
			}
			details.add ("%s: %s".printf (dgettext (null, "Source"), source));
			details.add ("%s: %s".printf (dgettext (null, "Required by"), dgettext (null, "%s build files (validpgpkeys)").printf (pkgname)));
			return details;
		}

		// translated warnings about the key
		public GenericArray<string> get_warnings () {
			var warnings = new GenericArray<string> ();
			if (revoked) {
				warnings.add (dgettext (null, "This key has been revoked by its owner"));
			}
			if (expired) {
				warnings.add (dgettext (null, "This key has expired"));
			}
			if (disabled) {
				warnings.add (dgettext (null, "This key is disabled on the keyserver"));
			}
			if (matching_keys > 1) {
				warnings.add (dgettext (null, "%u keys match %s on the keyserver, only the first one is shown").printf (matching_keys, key));
			}
			if (!match_key ()) {
				warnings.add (dgettext (null, "The key found on the keyserver does not match the requested key %s").printf (key));
			}
			// AUR build files are user produced content: the key is only
			// trustworthy if it is confirmed by the upstream project
			warnings.add (dgettext (null, "Keyservers do not verify key owners: compare the fingerprint with the one published by the upstream project before trusting this key"));
			return warnings;
		}

		// parse the output of gpgconf --list-options dirmngr
		internal void parse_dirmngr_options (string line) {
			// keyserver:<flags>:<level>:<description>:<type>:<alt-type>:<argname>:<default>:<argdef>:<value>
			if (!line.has_prefix ("keyserver:")) {
				return;
			}
			string[] fields = line.split (":");
			if (fields.length < 10) {
				return;
			}
			// use the value set by the user, else the default one
			string value = fields[9] != "" ? fields[9] : fields[7];
			if (value == "") {
				return;
			}
			// string values start with a quote and are percent-escaped,
			// several keyservers are separated by commas
			if (value.has_prefix ("\"")) {
				value = value.substring (1);
			}
			string first = value.split (",")[0];
			keyserver = Uri.unescape_string (first) ?? first;
		}

		static DateTime? parse_date (string field) {
			if (field == "") {
				return null;
			}
			// usually seconds since epoch, ISO 8601 is also allowed
			if ("T" in field) {
				return new DateTime.from_iso8601 (field, new TimeZone.utc ());
			}
			int64 timestamp;
			if (!int64.try_parse (field, out timestamp) || timestamp <= 0) {
				return null;
			}
			return new DateTime.from_unix_utc (timestamp);
		}

		static string get_algorithm_name (string algo) {
			// RFC 4880 and RFC 9580 public key algorithms
			switch (algo) {
				case "1":
				case "2":
				case "3":
					return "RSA";
				case "16":
				case "20":
					return "ElGamal";
				case "17":
					return "DSA";
				case "18":
					return "ECDH";
				case "19":
					return "ECDSA";
				case "22":
					return "EdDSA";
				case "25":
					return "X25519";
				case "27":
					return "Ed25519";
				default:
					return algo;
			}
		}
	}
}
