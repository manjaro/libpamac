/*
 *  alpm_config
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

GLib.Once<string> pamac_tmp_dir_once;

// /tmp/pamac-<user> is predictable: another user can create it first
// and plant symlinks or fake databases in it.
// Only use it if it is a real directory owned by us and not writable by others.
bool is_private_dir (string path) {
	if (Posix.mkdir (path, 0700) != 0 && Posix.errno != Posix.EEXIST) {
		return false;
	}
	Posix.Stat st;
	if (Posix.lstat (path, out st) != 0) {
		return false;
	}
	if (!Posix.S_ISDIR (st.st_mode)) {
		return false;
	}
	if (st.st_uid != Posix.geteuid ()) {
		return false;
	}
	if ((st.st_mode & (Posix.S_IWGRP | Posix.S_IWOTH)) != 0) {
		return false;
	}
	return true;
}

string get_pamac_tmp_dir () {
	return pamac_tmp_dir_once.once (() => {
		string path = "/tmp/pamac-%s".printf (Environment.get_user_name ());
		if (is_private_dir (path)) {
			return path;
		}
		warning ("%s is not a private directory, using a new one", path);
		try {
			return DirUtils.make_tmp ("pamac-%s-XXXXXX".printf (Environment.get_user_name ()));
		} catch (FileError e) {
			warning (e.message);
		}
		path = Path.build_filename (Environment.get_user_cache_dir (), "pamac-tmp");
		DirUtils.create_with_parents (path, 0700);
		return path;
	});
}

// a value written in a configuration file must stay on its line:
// a newline would allow to inject other directives
bool is_safe_config_value (string val) {
	for (int i = 0; i < val.length; i++) {
		// char is signed: bytes of non ASCII characters would be negative
		uchar c = (uchar) val[i];
		if (c < 0x20 || c == 0x7f) {
			return false;
		}
	}
	return true;
}

// keep only the options with the expected type and a safe value
HashTable<string, Variant> validate_new_conf (HashTable<string, Variant> new_conf, HashTable<string, VariantType> expected_types) {
	var valid_conf = new HashTable<string, Variant> (str_hash, str_equal);
	var iter = HashTableIter<string, Variant> (new_conf);
	unowned string key;
	unowned Variant val;
	while (iter.next (out key, out val)) {
		unowned VariantType? expected_type = expected_types.lookup (key);
		if (expected_type == null) {
			warning ("ignoring unknown option %s", key);
		} else if (!val.is_of_type (expected_type)) {
			warning ("ignoring option %s: wrong type %s", key, val.get_type_string ());
		} else if (val.is_of_type (VariantType.STRING) && !is_safe_config_value (val.get_string ())) {
			warning ("ignoring option %s: invalid value", key);
		} else {
			valid_conf.insert (key, val);
		}
	}
	return valid_conf;
}

// write a configuration file atomically:
// a crash can not leave a missing or partially written file
void write_config_file (File file, string data) {
	try {
		string? new_etag;
		file.replace_contents (data.data, null, false, FileCreateFlags.NONE, out new_etag);
	} catch (Error e) {
		warning (e.message);
	}
}

// key of a directive line, also when it is commented: "#IgnorePkg   =" gives "IgnorePkg",
// null for other lines like "# Pacman won't upgrade packages listed in IgnorePkg"
string? get_directive_key (string line, out bool commented) {
	string str = line.strip ();
	commented = str.has_prefix ("#");
	if (commented) {
		str = str.substring (1).strip ();
	}
	int end = 0;
	while (end < str.length && str[end].isalnum ()) {
		end++;
	}
	if (end == 0) {
		return null;
	}
	string rest = str.substring (end).strip ();
	if (rest.length == 0 || rest.has_prefix ("=")) {
		return str.substring (0, end);
	}
	return null;
}

// replace the directives of a configuration file by new_lines (key -> new line):
// the first line of a directive is replaced, its other active lines are commented,
// the directives not found are added after the last directive.
// With a section, only the directives of this section are processed
// and it is created at the beginning of the file if needed.
// keys gives the order of the added directives.
void write_config_directives (string path, HashTable<string, string> new_lines, string[] keys, string? section) {
	if (new_lines.size () == 0) {
		return;
	}
	var file = GLib.File.new_for_path (path);
	try {
		var dis = new DataInputStream (file.read ());
		var lines = new GenericArray<string> ();
		bool in_section = section == null;
		string? section_header = section == null ? null : "[%s]".printf (section);
		// where to add the directives not found: after the last directive of the section
		int insert_index = -1;
		var written = new GenericSet<string> (str_hash, str_equal);
		string? line;
		while ((line = dis.read_line ()) != null) {
			string stripped = line.strip ();
			if (section_header != null && stripped.has_prefix ("[") && stripped.has_suffix ("]")) {
				in_section = stripped == section_header;
				lines.add (line);
				if (in_section) {
					insert_index = (int) lines.length;
				}
				continue;
			}
			if (in_section) {
				bool commented;
				string? key = get_directive_key (line, out commented);
				// a comment like "# REPOSITORIES" looks like a commented directive:
				// only the commented directives to write are recognized
				if (key != null && (!commented || new_lines.contains (key))) {
					unowned string? new_line = new_lines.lookup (key);
					if (new_line == null) {
						lines.add (line);
					} else if (!(key in written)) {
						// replace the first line of the directive
						lines.add (new_line);
						written.add (key);
					} else if (commented) {
						lines.add (line);
					} else {
						// comment the other lines
						lines.add ("#" + line);
					}
					insert_index = (int) lines.length;
					continue;
				}
			}
			lines.add (line);
		}
		// add the directives not found
		var missing = new GenericArray<string> ();
		foreach (unowned string key in keys) {
			unowned string? new_line = new_lines.lookup (key);
			if (new_line != null && !(key in written)) {
				missing.add (new_line);
			}
		}
		if (missing.length > 0) {
			if (insert_index == -1) {
				if (section_header == null) {
					// no directive: add them at the end
					if (lines.length > 0 && lines[lines.length - 1].strip () != "") {
						lines.add ("");
					}
					insert_index = (int) lines.length;
				} else {
					missing.insert (0, section_header);
					missing.add ("");
					insert_index = 0;
				}
			}
			for (uint i = 0; i < missing.length; i++) {
				lines.insert (insert_index + (int) i, missing[i]);
			}
		}
		var data = new StringBuilder ();
		foreach (unowned string l in lines) {
			data.append (l);
			data.append_c ('\n');
		}
		write_config_file (file, data.str);
	} catch (IOError.NOT_FOUND e) {
		warning ("File '%s' doesn't exist.", path);
	} catch (Error e) {
		warning (e.message);
	}
}

// run a command without shell parsing of its arguments
int run_command (string[] argv) {
	int status = 1;
	try {
		Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
	} catch (SpawnError e) {
		warning (e.message);
	}
	return status;
}

[Compact]
class AlpmRepo {
	public string name;
	public Alpm.Signature.Level siglevel;
	public Alpm.Signature.Level siglevel_mask;
	public Alpm.DB.Usage usage;
	public GenericArray<string> urls;

	public AlpmRepo (string name) {
		this.name = name;
		siglevel = Alpm.Signature.Level.USE_DEFAULT;
		usage = 0;
		urls = new GenericArray<string> ();
	}

	public static bool equal_name (AlpmRepo a, AlpmRepo b) {
		return str_equal (a.name, b.name);
	}
}

internal class AlpmConfig {
	string conf_path;
	string? rootdir;
	public string? dbpath;
	public string? logfile;
	string? gpgdir;
	string download_user;
	bool disable_sandbox_filesystem;
	bool disable_sandbox_syscalls;
	bool disable_dl_timeout;
	int usesyslog;
	public bool checkspace;
	GenericArray<string> architectures;
	GenericArray<string> cachedirs;
	GenericArray<string> hookdirs;
	GenericArray<string> ignoregroups;
	public GenericSet<string?> ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
	GenericArray<string> noextracts;
	GenericArray<string> noupgrades;
	public GenericSet<string?> holdpkgs = new GenericSet<string?> (str_hash, str_equal);
	public GenericSet<string?> syncfirsts = new GenericSet<string?> (str_hash, str_equal);
	Alpm.Signature.Level siglevel;
	Alpm.Signature.Level localfilesiglevel;
	Alpm.Signature.Level remotefilesiglevel;
	Alpm.Signature.Level siglevel_mask;
	Alpm.Signature.Level localfilesiglevel_mask;
	Alpm.Signature.Level remotefilesiglevel_mask;
	GenericArray<AlpmRepo> repo_order;

	public AlpmConfig (string path) {
		conf_path = path;
		reload ();
	}

	public void reload () {
		// set default options, the previous values must not be kept
		rootdir = null;
		dbpath = null;
		logfile = null;
		gpgdir = null;
		architectures = new GenericArray<string> ();
		cachedirs = new GenericArray<string> ();
		hookdirs = new GenericArray<string> ();
		ignoregroups = new GenericArray<string> ();
		ignorepkgs.remove_all ();
		noextracts = new GenericArray<string> ();
		noupgrades = new GenericArray<string> ();
		holdpkgs.remove_all ();
		syncfirsts.remove_all ();
		usesyslog = 0;
		checkspace = false;
		disable_sandbox_filesystem = false;
		disable_sandbox_syscalls = false;
		disable_dl_timeout = false;
		download_user = "alpm";
		siglevel = Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL | Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL;
		localfilesiglevel = Alpm.Signature.Level.USE_DEFAULT;
		remotefilesiglevel = Alpm.Signature.Level.USE_DEFAULT;
		siglevel_mask = 0;
		localfilesiglevel_mask = 0;
		remotefilesiglevel_mask = 0;
		repo_order = new GenericArray<AlpmRepo> ();
		// parse conf file
		parse_file (conf_path);
		// if rootdir is set and dbpath/logfile are not
		// set, then set those as well to reside under the root.
		if (rootdir != null) {
			if (dbpath == null) {
				dbpath = Path.build_filename (rootdir, "var/lib/pacman/");
			}
			if (logfile == null) {
				logfile = Path.build_filename (rootdir, "var/log/pacman.log");
			}
		} else {
			rootdir = "/";
			if (dbpath == null) {
				dbpath = "/var/lib/pacman/";
			}
			if (logfile == null) {
				logfile = "/var/log/pacman.log";
			}
		}
		if (cachedirs.length == 0) {
			cachedirs.add ("/var/cache/pacman/pkg/");
		}
		if (hookdirs.length == 0) {
			hookdirs.add ("/etc/pacman.d/hooks/");
		}
		if (gpgdir == null) {
			// gpgdir it is not relative to rootdir, even if
			// rootdir is defined because it contains configuration data.
			gpgdir = "/etc/pacman.d/gnupg/";
		}
		if (architectures.length == 0) {
			architectures.add (Posix.utsname().machine);
		}
		// add archlinux-keyring and manjaro-keyring to syncfirsts
		syncfirsts.add ("archlinux-keyring");
		syncfirsts.add ("manjaro-keyring");
	}

	public unowned GenericArray<string> get_cachedirs () {
		return cachedirs;
	}

	// the local database of a temporary handle is a link to the real one:
	// in both cases, upgrading the database format needs root
	Alpm.Handle? new_handle (string handle_dbpath, out Alpm.Errno error) {
		var handle = new Alpm.Handle (rootdir, handle_dbpath, out error);
		if (error == Alpm.Errno.DB_VERSION) {
			run_command ({"pacman-db-upgrade"});
			handle = new Alpm.Handle (rootdir, handle_dbpath, out error);
		}
		return handle;
	}

	public Alpm.Handle? get_handle (bool files_db = false, bool tmp_db = false, bool copy_dbs = true) {
		Alpm.Errno error = 0;
		Alpm.Handle? handle = null;
		if (tmp_db) {
			string tmp_dbpath = Path.build_filename (get_pamac_tmp_dir (), "dbs");
			// dbpath can be defined by the user with or without a trailing slash
			string localdb_path = Path.build_filename (dbpath, "local");
			string syncdb_path = Path.build_filename (dbpath, "sync");
			if (DirUtils.create_with_parents (tmp_dbpath, 0700) != 0) {
				warning ("failed to create %s", tmp_dbpath);
			}
			run_command ({"ln", "-sfn", "--", localdb_path, Path.build_filename (tmp_dbpath, "local")});
			if (copy_dbs) {
				var file = GLib.File.new_for_path (syncdb_path);
				if (file.query_exists ()) {
					run_command ({"cp", "--preserve=timestamps", "-ru", "--", syncdb_path, tmp_dbpath});
				}
			}
			// remove an existing pamac_aur.db file
			FileUtils.unlink (Path.build_filename (tmp_dbpath, "sync", "pamac_aur.db"));
			handle = new_handle (tmp_dbpath, out error);
		} else {
			handle = new_handle (dbpath, out error);
		}
		if (handle == null) {
			warning ("Failed to initialize alpm library (%s)", Alpm.strerror (error));
			return null;
		}
		// define options
		if (files_db) {
			handle.dbext = ".files";
		}
		if (!tmp_db) {
			handle.logfile = logfile;
		}
		handle.gpgdir = gpgdir;
		handle.usesyslog = usesyslog;
		handle.checkspace = checkspace ? 1 : 0;
		handle.defaultsiglevel = siglevel;
		handle.localfilesiglevel = merge_siglevel (siglevel, localfilesiglevel, localfilesiglevel_mask);
		handle.remotefilesiglevel = merge_siglevel (siglevel, remotefilesiglevel, remotefilesiglevel_mask);
		foreach (unowned string arch in architectures) {
			handle.add_architecture (arch);
		}
		foreach (unowned string cachedir in cachedirs) {
			handle.add_cachedir (cachedir);
		}
		foreach (unowned string hookdir in hookdirs) {
			handle.add_hookdir (hookdir);
		}
		foreach (unowned string ignoregroup in ignoregroups) {
			handle.add_ignoregroup (ignoregroup);
		}
		// ignorepkgs will be manually added in database and transaction
		foreach (unowned string noextract in noextracts) {
			handle.add_noextract (noextract);
		}
		foreach (unowned string noupgrade in noupgrades) {
			handle.add_noupgrade (noupgrade);
		}
		handle.sandboxuser = download_user;
		handle.disable_sandbox_filesystem = disable_sandbox_filesystem ? 1 : 0;
		handle.disable_sandbox_syscalls = disable_sandbox_syscalls ? 1 : 0;
		handle.disable_dl_timeout = disable_dl_timeout ? 1 : 0;
		return handle;
	}

	public void register_syncdbs (Alpm.Handle handle) {
		foreach (unowned AlpmRepo repo in repo_order) {
			unowned Alpm.DB db = handle.register_syncdb (repo.name, merge_siglevel (siglevel, repo.siglevel, repo.siglevel_mask));
			foreach (unowned string url in repo.urls) {
				db.add_server (url.replace ("$repo", repo.name).replace ("$arch", architectures[0]));
			}
			if (repo.usage == 0) {
				db.usage = Alpm.DB.Usage.ALL;
			} else {
				db.usage = repo.usage;
			}
		}
	}

	// same limit as pacman
	const int MAX_INCLUDE_DEPTH = 10;

	// split a list value on whitespace, skipping empty entries
	static GenericArray<string> split_values (string val) {
		var values = new GenericArray<string> ();
		foreach (unowned string item in val.split_set (" \t")) {
			if (item.length > 0) {
				values.add (item);
			}
		}
		return values;
	}

	// Include values may be glob patterns, like in pacman
	void parse_include (string pattern, string? section, int depth) {
		var matches = Posix.Glob ();
		int ret = matches.glob (pattern);
		if (ret == Posix.GLOB_NOMATCH) {
			warning ("No file matches Include '%s'", pattern);
			return;
		}
		if (ret != 0) {
			warning ("Failed to expand Include '%s'", pattern);
			return;
		}
		foreach (unowned string path in matches.pathv) {
			parse_file (path, section, depth);
		}
	}

	void parse_file (string path, string? section = null, int depth = 0) {
		if (depth > MAX_INCLUDE_DEPTH) {
			warning ("Too many levels of Include, ignoring '%s'", path);
			return;
		}
		string? current_section = section;
		var file = GLib.File.new_for_path (path);
		try {
			// Open file for reading and wrap returned FileInputStream into a
			// DataInputStream, so we can read line by line
			var dis = new DataInputStream (file.read ());
			string? line;
			// Read lines until end of file (null) is reached
			while ((line = dis.read_line ()) != null) {
				if (line.length == 0) {
					continue;
				}
				// ignore whole line and end of line comments
				string[] splitted = line.split ("#", 2);
				line = splitted[0].strip ();
				if (line.length == 0) {
					continue;
				}
				if (line[0] == '[' && line[line.length-1] == ']') {
					current_section = line[1:-1].strip ();
					if (current_section.length == 0) {
						warning ("Empty section name in '%s'", path);
						current_section = null;
						continue;
					}
					if (current_section != "options") {
						var repo = new AlpmRepo (current_section);
						if (!repo_order.find_with_equal_func (repo, AlpmRepo.equal_name)) {
							repo_order.add ((owned) repo);
						}
					}
					continue;
				}
				splitted = line.split ("=", 2);
				unowned string key = splitted[0]._strip ();
				unowned string? val = null;
				if (splitted.length == 2) {
					val = splitted[1]._strip ();
				}
				// options without value
				if (current_section == "options") {
					switch (key) {
						case "UseSysLog":
							usesyslog = 1;
							continue;
						case "CheckSpace":
							checkspace = true;
							continue;
						case "DisableDownloadTimeout":
							disable_dl_timeout = true;
							continue;
						case "DisableSandbox":
							disable_sandbox_filesystem = true;
							disable_sandbox_syscalls = true;
							continue;
						case "DisableSandboxFilesystem":
							disable_sandbox_filesystem = true;
							continue;
						case "DisableSandboxSyscalls":
							disable_sandbox_syscalls = true;
							continue;
						case "Color":
						case "ILoveCandy":
						case "VerbosePkgLists":
						case "NoProgressBar":
							// pacman display options
							continue;
						default:
							break;
					}
				}
				if (val == null || val.length == 0) {
					warning ("Missing value for '%s' in '%s'", key, path);
					continue;
				}
				if (key == "Include") {
					parse_include (val, current_section, depth + 1);
					continue;
				}
				if (current_section == null) {
					continue;
				}
				if (current_section == "options") {
					if (key == "RootDir") {
						rootdir = val;
					} else if (key == "DBPath") {
						dbpath = val;
					} else if (key == "CacheDir") {
						foreach (unowned string dir in split_values (val)) {
							cachedirs.add (dir);
						}
					} else if (key == "HookDir") {
						foreach (unowned string dir in split_values (val)) {
							hookdirs.add (dir);
						}
					} else if (key == "LogFile") {
						logfile = val;
					} else if (key == "GPGDir") {
						gpgdir = val;
					} else if (key == "Architecture") {
						foreach (unowned string arch in split_values (val)) {
							if (arch == "auto") {
								architectures.add (Posix.utsname ().machine);
							} else {
								architectures.add (arch);
							}
						}
					} else if (key == "SigLevel") {
						process_siglevel (val, ref siglevel, ref siglevel_mask);
					} else if (key == "LocalFileSigLevel") {
						process_siglevel (val, ref localfilesiglevel, ref localfilesiglevel_mask);
					} else if (key == "RemoteFileSigLevel") {
						process_siglevel (val, ref remotefilesiglevel, ref remotefilesiglevel_mask);
					} else if (key == "HoldPkg") {
						foreach (unowned string name in split_values (val)) {
							holdpkgs.add (name);
						}
					} else if (key == "SyncFirst") {
						foreach (unowned string name in split_values (val)) {
							syncfirsts.add (name);
						}
					} else if (key == "IgnoreGroup") {
						foreach (unowned string name in split_values (val)) {
							ignoregroups.add (name);
						}
					} else if (key == "IgnorePkg") {
						foreach (unowned string name in split_values (val)) {
							ignorepkgs.add (name);
						}
					} else if (key == "NoExtract") {
						foreach (unowned string name in split_values (val)) {
							noextracts.add (name);
						}
					} else if (key == "NoUpgrade") {
						foreach (unowned string name in split_values (val)) {
							noupgrades.add (name);
						}
					} else if (key == "DownloadUser") {
						download_user = val;
					}
				} else {
					foreach (unowned AlpmRepo repo in repo_order) {
						if (repo.name == current_section) {
							if (key == "Server") {
								repo.urls.add (val);
							} else if (key == "SigLevel") {
								process_siglevel (val, ref repo.siglevel, ref repo.siglevel_mask);
							} else if (key == "Usage") {
								repo.usage = define_usage (val);
							}
							break;
						}
					}
				}
			}
		} catch (IOError.NOT_FOUND e) {
			warning ("File '%s' doesn't exist", path);
		} catch (Error e) {
			warning (e.message);
		}
	}

	public void write (HashTable<string,Variant> received_conf) {
		var expected_types = new HashTable<string, VariantType> (str_hash, str_equal);
		expected_types.insert ("IgnorePkg", VariantType.STRING);
		expected_types.insert ("CheckSpace", VariantType.BOOLEAN);
		var new_conf = validate_new_conf (received_conf, expected_types);
		// the new lines of the directives to write
		var new_lines = new HashTable<string, string> (str_hash, str_equal);
		unowned Variant? val = new_conf.lookup ("IgnorePkg");
		if (val != null) {
			unowned string pkgs = val.get_string ();
			new_lines.insert ("IgnorePkg", pkgs == "" ? "#IgnorePkg   =" : "IgnorePkg   = %s".printf (pkgs));
		}
		val = new_conf.lookup ("CheckSpace");
		if (val != null) {
			new_lines.insert ("CheckSpace", val.get_boolean () ? "CheckSpace" : "#CheckSpace");
		}
		write_config_directives (conf_path, new_lines, {"IgnorePkg", "CheckSpace"}, "options");
	}

	Alpm.DB.Usage define_usage (string conf_string) {
		Alpm.DB.Usage usage = 0;
		foreach (unowned string directive in split_values (conf_string)) {
			if (directive == "Sync") {
				usage |= Alpm.DB.Usage.SYNC;
			} else if (directive == "Search") {
				usage |= Alpm.DB.Usage.SEARCH;
			} else if (directive == "Install") {
				usage |= Alpm.DB.Usage.INSTALL;
			} else if (directive == "Upgrade") {
				usage |= Alpm.DB.Usage.UPGRADE;
			} else if (directive == "All") {
				usage |= Alpm.DB.Usage.ALL;
			} else {
				warning ("unrecognized Usage directive: %s", directive);
			}
		}
		return usage;
	}

	// like pacman: an optional Package or Database prefix, then the exact option
	void process_siglevel (string conf_string, ref Alpm.Signature.Level siglevel, ref Alpm.Signature.Level siglevel_mask) {
		foreach (unowned string directive in split_values (conf_string)) {
			bool affect_package = true;
			bool affect_database = true;
			unowned string option = directive;
			if (directive.has_prefix ("Package")) {
				affect_database = false;
				option = directive.offset ("Package".length);
			} else if (directive.has_prefix ("Database")) {
				affect_package = false;
				option = directive.offset ("Database".length);
			}
			if (option == "Never") {
				if (affect_package) {
					siglevel &= ~Alpm.Signature.Level.PACKAGE;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE;
				}
				if (affect_database) {
					siglevel &= ~Alpm.Signature.Level.DATABASE;
					siglevel_mask |= Alpm.Signature.Level.DATABASE;
				}
			} else if (option == "Optional") {
				if (affect_package) {
					siglevel |= (Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL);
				}
				if (affect_database) {
					siglevel |= (Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL);
				}
			} else if (option == "Required") {
				if (affect_package) {
					siglevel |= Alpm.Signature.Level.PACKAGE;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE;
					siglevel &= ~Alpm.Signature.Level.PACKAGE_OPTIONAL;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE_OPTIONAL;
				}
				if (affect_database) {
					siglevel |= Alpm.Signature.Level.DATABASE;
					siglevel_mask |= Alpm.Signature.Level.DATABASE;
					siglevel &= ~Alpm.Signature.Level.DATABASE_OPTIONAL;
					siglevel_mask |= Alpm.Signature.Level.DATABASE_OPTIONAL;
				}
			} else if (option == "TrustedOnly") {
				if (affect_package) {
					siglevel &= ~(Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
				}
				if (affect_database) {
					siglevel &= ~(Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
				}
			} else if (option == "TrustAll") {
				if (affect_package) {
					siglevel |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
				}
				if (affect_database) {
					siglevel |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
				}
			} else {
				warning ("unrecognized SigLevel directive: %s", directive);
			}
		}
		siglevel &= ~Alpm.Signature.Level.USE_DEFAULT;
	}

	Alpm.Signature.Level merge_siglevel(Alpm.Signature.Level sigbase, Alpm.Signature.Level sigover, Alpm.Signature.Level sigmask) {
		return (sigmask != 0) ? (sigover & sigmask) | (sigbase & ~sigmask) : sigover;
	}
}
