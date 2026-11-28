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
	public class Transaction: Object {
		TransactionInterface transaction_interface;
		// receives the progress of the operations, from any thread
		TransactionSink sink;
		// packages with unresolvable dependencies found by the last failed prepare
		GenericArray<string> unresolvables;
		unowned Config config;
		unowned MainContext context;
		// run transaction data
		AlpmUtils alpm_utils;
		// sysupgrade explicitly asked, AUR updates are also checked
		bool sysupgrading;
		// sysupgrade of the alpm transaction: also done when installing packages
		// to avoid partial upgrades, unless simple install is enabled
		bool alpm_sysupgrade;
		bool force_refresh;
		int trans_flags;
		GenericSet<string?> to_install;
		GenericSet<string?> to_remove;
		GenericSet<string?> to_load_local;
		GenericSet<string?> to_load_remote;
		GenericSet<string?> to_build;
		GenericSet<string?> clone_files;
		GenericSet<string?> clone_deps_files;
		GenericSet<string?> ignorepkgs;
		GenericSet<string?> overwrite_files;
		GenericSet<string?> to_install_as_dep;
		HashTable<string, SnapPackage> snap_to_install;
		HashTable<string, SnapPackage> snap_to_remove;
		HashTable<string, FlatpakPackage> flatpak_to_install;
		HashTable<string, FlatpakPackage> flatpak_to_remove;
		HashTable<string, FlatpakPackage> flatpak_to_upgrade;
		// keys asked to be imported
		HashTable<string, PGPKey> pgp_keys;
		// building data
		string tmp_path;
		string aurdb_path;
		GenericSet<string?> already_checked_aur_dep;
		GenericSet<string?> aur_desc_list;
		Queue<string> to_build_queue;
		GenericSet<string?> aur_pkgs_to_install;
		bool building;
		Cancellable build_cancellable;
		// transaction options
		public Database database { get; construct set; }
		public bool download_only { get; set; }
		public bool dry_run { get; set; }
		public bool install_if_needed { get; set; }
		public bool remove_if_unneeded { get; set; }
		public bool cascade { get; set; }
		public bool keep_config_files { get; set; }
		public bool install_as_dep { get; set; }
		public bool install_as_explicit { get; set; }
		public bool no_refresh { get; set; }

		// a restart is required to use the packages installed by the last successful run
		public bool reboot_required { get; private set; }
		// the summary of the committed transaction requires a reboot
		bool pending_reboot;

		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_download_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		// the progress of the current step of the transaction, see TransactionStep for the units
		public signal void emit_transaction_progress (TransactionStep step, uint64 current, uint64 total);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, GenericArray<string> details);
		public signal void start_waiting ();
		public signal void stop_waiting ();
		public signal void start_preparing ();
		public signal void stop_preparing ();
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void start_building ();
		public signal void stop_building ();
		public signal void important_details_outpout (bool must_show);

		public Transaction (Database database) {
			Object (database: database);
		}

		construct {
			config = database.config;
			context = database.context;
			alpm_utils = new AlpmUtils (config);
			sink = new MainContextSink (this, context);
			unresolvables = new GenericArray<string> ();
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot (alpm_utils, context, sink);
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (config, sink);
			}
			// transaction options
			download_only = false;
			dry_run = false;
			install_if_needed = true;
			remove_if_unneeded = false;
			cascade = false;
			keep_config_files = true;
			install_as_dep = false;
			install_as_explicit = false;
			no_refresh = false;
			// run transaction data
			sysupgrading = false;
			alpm_sysupgrade = false;
			force_refresh = false;
			to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load_local = new GenericSet<string?> (str_hash, str_equal);
			to_load_remote = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			clone_files = new GenericSet<string?> (str_hash, str_equal);
			clone_deps_files = new GenericSet<string?> (str_hash, str_equal);
			ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			overwrite_files = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new GenericSet<string?> (str_hash, str_equal);
			pgp_keys = new HashTable<string, PGPKey> (str_hash, str_equal);
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_upgrade = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			// building data
			tmp_path = get_pamac_tmp_dir ();
			aurdb_path = "%s/aur".printf (tmp_path);
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			aur_pkgs_to_install = new GenericSet<string?> (str_hash, str_equal);
			to_build_queue = new Queue<string> ();
			build_cancellable = new Cancellable ();
			building = false;
		}

		~Transaction () {
			quit_daemon ();
		}

		public void quit_daemon () {
			try {
				transaction_interface.quit_daemon ();
			} catch (Error e) {
				report_daemon_error ("quit_daemon", e);
			}
		}

		// method: the failed TransactionInterface method
		void report_daemon_error (string method, Error e) {
			if (e is IOError.CLOSED) {
				// the connection to the daemon was lost:
				// already reported by TransactionInterfaceDaemon
				return;
			}
			var details = new GenericArray<string> (1);
			details.add ("%s: %s".printf (method, e.message));
			emit_error ("Daemon Error", details);
		}

		protected virtual async bool ask_commit (TransactionSummary summary) {
			// no confirm
			return true;
		}

		protected virtual async bool ask_edit_build_files (TransactionSummary summary) {
			// no edit
			return false;
		}

		protected virtual async void edit_build_files (GenericArray<string> pkgnames) {
			// do nothing
		}

		// details of the key given to ask_import_key, null outside of it
		public PGPKey? get_pgp_key (string key) {
			return pgp_keys.lookup (key);
		}

		protected virtual async bool ask_import_key (string pkgname, string key, string? owner) {
			// no import
			return false;
		}

		// return the real path of a file listed in .SRCINFO,
		// or null if it does not exist or is outside the package build dir
		string? get_build_file_path (string pkgdir, string filename) {
			string? real_pkgdir = Posix.realpath (pkgdir);
			string? real_path = Posix.realpath (Path.build_filename (pkgdir, filename));
			if (real_pkgdir == null || real_path == null) {
				return null;
			}
			if (!real_path.has_prefix (real_pkgdir + "/")) {
				return null;
			}
			return real_path;
		}

		protected async GenericArray<string> get_build_files_async (string pkgname) {
			if (!config.support_aur) {
				return new GenericArray<string> ();
			}
			unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
			string pkgdir_name = Path.build_filename (real_aur_build_dir, pkgname);
			var files = new GenericArray<string> ();
			// PKGBUILD
			files.add (Path.build_filename (pkgdir_name, "PKGBUILD"));
			var srcinfo = File.new_for_path (Path.build_filename (pkgdir_name, ".SRCINFO"));
			try {
				// read .SRCINFO
				var dis = new DataInputStream (yield srcinfo.read_async ());
				string? line;
				// sources can also be specific to the architecture
				string arch_source = "source_%s = ".printf (Posix.utsname ().machine);
				while ((line = yield dis.read_line_async ()) != null) {
					if ("source = " in line || arch_source in line) {
						string source = line.split (" = ", 2)[1];
						if (!("://" in source)) {
							string? source_path = get_build_file_path (pkgdir_name, source);
							if (source_path != null) {
								files.add ((owned) source_path);
							}
						}
					} else if ("install = " in line) {
						string install = line.split (" = ", 2)[1];
						string? install_path = get_build_file_path (pkgdir_name, install);
						if (install_path != null) {
							files.add ((owned) install_path);
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return files;
		}

		protected virtual async GenericArray<string> choose_optdeps (string pkgname, GenericArray<string> optdeps) {
			// do not install optdeps
			return new GenericArray<string> ();
		}

		protected virtual async int choose_provider (string depend, GenericArray<string> providers) {
			// choose first provider
			return 0;
		}

		protected virtual async bool ask_snap_install_classic (string name) {
			// do not install
			return false;
		}

		public async bool get_authorization_async () {
			try {
				return yield transaction_interface.get_authorization ();
			} catch (Error e) {
				report_daemon_error ("get_authorization", e);
			}
			return false;
		}

		public void remove_authorization () {
			try {
				transaction_interface.remove_authorization ();
			} catch (Error e) {
				report_daemon_error ("remove_authorization", e);
			}
		}

		public async void generate_mirrors_list_async (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			try {
				yield transaction_interface.generate_mirrors_list (country);
			} catch (Error e) {
				report_daemon_error ("generate_mirrors_list", e);
			}
			database.refresh ();
		}

		public async void clean_cache_async () {
			HashTable<string, uint64?> details = yield database.get_clean_cache_details_async ();
			var iter = HashTableIter<string, uint64?> (details);
			var array = new GenericArray<string> (details.length);
			unowned string name;
			while (iter.next (out name, null)) {
				array.add (name);
			}
			try {
				yield transaction_interface.clean_cache (array);
			} catch (Error e) {
				report_daemon_error ("clean_cache", e);
			}
		}

		public async void clean_build_files_async () {
			if (!config.support_aur) {
				return;
			}
			unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
			try {
				yield transaction_interface.clean_build_files (real_aur_build_dir);
			} catch (Error e) {
				report_daemon_error ("clean_build_files", e);
			}
		}

		public async bool set_pkgreason_async (string pkgname, uint reason) {
			bool success = false;
			try {
				success = yield transaction_interface.set_pkgreason (pkgname, reason);
			} catch (Error e) {
				report_daemon_error ("set_pkgreason", e);
			}
			database.refresh ();
			return success;
		}

		public async bool download_updates_async () {
			bool success = false;
			try {
				success = yield transaction_interface.download_updates ();
			} catch (Error e) {
				report_daemon_error ("download_updates", e);
			}
			return success;
		}

		async bool compute_aur_build_list () {
			// set building to allow cancellation
			building = true;
			build_cancellable.reset ();
			start_building ();
			bool success = yield compute_aur_build_list_real ();
			stop_building ();
			building = false;
			if (build_cancellable.is_cancelled ()) {
				emit_script_output ("");
				emit_action (dgettext (null, "Transaction cancelled") + ".");
			}
			return success;
		}

		async int launch_subprocess (string[] cmds) {
			int status = 1;
			try {
				var process = new Subprocess.newv (cmds, SubprocessFlags.NONE);
				yield process.wait_async ();
				if (process.get_if_exited ()) {
					status = process.get_exit_status ();
				}
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add (e.message);
				emit_error (dgettext (null, "Failed to prepare transaction"), details);
			}
			return status;
		}

		// the fake aur db dir is small: one dir with a desc file by package
		static void delete_recursive (File file) {
			try {
				FileInfo info = file.query_info ("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
				if (info.get_file_type () == FileType.DIRECTORY) {
					FileEnumerator enumerator = file.enumerate_children ("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
					FileInfo child_info;
					while ((child_info = enumerator.next_file ()) != null) {
						delete_recursive (file.get_child (child_info.get_name ()));
					}
				}
				file.delete ();
			} catch (Error e) {
				if (!(e is IOError.NOT_FOUND)) {
					warning (e.message);
				}
			}
		}

		async bool compute_aur_build_list_real () {
			DirUtils.create_with_parents (aurdb_path, 0700);
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			var to_build_array = new GenericArray<string> ();
			foreach (unowned string pkgname in to_build) {
				to_build_array.add (pkgname);
			}
			bool success = yield check_aur_dep_list (to_build_array);
			if (success && aur_desc_list.length > 0) {
				// create a fake aur db
				string tmp_aurdb_path = Path.build_filename (tmp_path, "pamac_aur.db");
				FileUtils.unlink (tmp_aurdb_path);
				var cmdline = new GenericArray<string> (5 + aur_desc_list.length);
				cmdline.add ("bsdtar");
				cmdline.add ("-cf");
				cmdline.add (tmp_aurdb_path);
				cmdline.add ("-C");
				cmdline.add (aurdb_path);
				foreach (unowned string name_version in aur_desc_list) {
					cmdline.add (name_version);
				}
				// spawnv needs a null terminated array
				cmdline.length = cmdline.length + 1;
				int ret = yield launch_subprocess (cmdline.data);
				if (ret == 0) {
					// remove aur db dir
					delete_recursive (File.new_for_path (aurdb_path));
				} else {
					success = false;
				}
			}
			return success;
		}

		async bool check_aur_dep_list (GenericArray<string> pkgnames) {
			var dep_to_check = new GenericArray<string> ();
			var to_get_from_aur = new GenericArray<string> ();
			foreach (unowned string pkgname in pkgnames) {
				if (already_checked_aur_dep.contains (pkgname)) {
					continue;
				}
				if (pkgname in clone_files) {
					to_get_from_aur.add (pkgname);
				}
			}
			HashTable<string, AURPackage?> aur_pkgs = null;
			if (to_get_from_aur.length > 0) {
				aur_pkgs = yield database.get_aur_pkgs_async (to_get_from_aur);
			}
			unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
			foreach (unowned string pkgname in pkgnames) {
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				if (already_checked_aur_dep.contains (pkgname)) {
					continue;
				}
				unowned AURPackage? aur_pkg = null;
				File? clone_dir = File.new_for_path (Path.build_filename (real_aur_build_dir, pkgname));
				if (pkgname in clone_files) {
					aur_pkg = aur_pkgs.lookup (pkgname);
					if (aur_pkg == null) {
						// may be a virtual package
						// use search and add results
						var providers = database.get_aur_providers (pkgname);
						foreach (unowned AURInfos info in providers) {
							unowned string provider_name = info.name;
							dep_to_check.add (provider_name);
							clone_files.add (provider_name);
							if (pkgname in clone_deps_files) {
								clone_deps_files.add (provider_name);
							}
						}
						already_checked_aur_dep.add (pkgname);
						// make this error not fatal to propose to edit build files
						continue;
					} else if (clone_dir.query_exists ()) {
						// refresh build files
						// use packagebase in case of split package
						emit_action (dgettext (null, "Cloning %s build files").printf (aur_pkg.packagebase) + "...");
						clone_dir = yield database.clone_build_files_async (aur_pkg.packagebase, false, build_cancellable);
						if (build_cancellable.is_cancelled ()) {
							return false;
						}
						if (clone_dir == null) {
							// error
							var details = new GenericArray<string> (1);
							details.add (dgettext (null, "Failed to clone %s build files").printf (aur_pkg.packagebase));
							emit_error (dgettext (null, "Failed to prepare transaction"), details);
							return false;
						} else {
							emit_action (dgettext (null, "Generating %s information").printf (pkgname) + "...");
							bool success = yield database.regenerate_srcinfo_async (pkgname, build_cancellable);
							if (!success) {
								// error
								var details = new GenericArray<string> (1);
								details.add (dgettext (null, "Failed to generate %s information").printf (pkgname));
								emit_error (dgettext (null, "Failed to prepare transaction"), details);
								return false;
							}
						}
					} else {
						clone_files.add (aur_pkg.packagebase);
					}
				} else if (clone_dir.query_exists ()) {
					emit_action (dgettext (null, "Generating %s information").printf (pkgname) + "...");
					bool success = yield database.regenerate_srcinfo_async (pkgname, build_cancellable);
					if (!success) {
						// error
						var details = new GenericArray<string> (1);
						details.add (dgettext (null, "Failed to generate %s information").printf (pkgname));
						emit_error (dgettext (null, "Failed to prepare transaction"), details);
						return false;
					}
				} else {
					// didn't find the target
					// look for it in all build dirs, e.g. a split package stored by its pkgbase
					clone_dir = yield find_build_dir (real_aur_build_dir, pkgname);
					if (clone_dir == null) {
						var details = new GenericArray<string> (1);
						details.add (dgettext (null, "target not found: %s").printf (pkgname));
						emit_error (dgettext (null, "Failed to prepare transaction"), details);
						return false;
					}
				}
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				emit_action (dgettext (null, "Checking %s dependencies").printf (pkgname) + "...");
				string arch = Posix.utsname ().machine;
				if (clone_dir.query_exists ()) {
					// use .SRCINFO
					var srcinfo = clone_dir.get_child (".SRCINFO");
					try {
						// read .SRCINFO
						var dis = new DataInputStream (yield srcinfo.read_async ());
						string? line;
						string current_section = "";
						bool current_section_is_pkgbase = true;
						var version = new StringBuilder ("");
						string pkgbase = "";
						string desc = "";
						var pkgnames_found = new GenericArray<string> ();
						var global_depends = new GenericArray<string> ();
						var global_makedepends = new GenericArray<string> ();
						var global_conflicts = new GenericArray<string> ();
						var global_provides = new GenericArray<string> ();
						var global_replaces = new GenericArray<string> ();
						var pkgnames_table = new HashTable<string, AURPackage> (str_hash, str_equal);
						while ((line = yield dis.read_line_async ()) != null) {
							if ("pkgbase = " in line) {
								pkgbase = line.split (" = ", 2)[1];
							} else if ("pkgdesc = " in line) {
								desc = line.split (" = ", 2)[1];
								if (!current_section_is_pkgbase) {
									unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
									if (aur_pkg_found != null) {
										aur_pkg_found.desc = desc;
									}
								}
							} else if ("pkgver = " in line) {
								version.append (line.split (" = ", 2)[1]);
							} else if ("pkgrel = " in line) {
								version.append ("-");
								version.append (line.split (" = ", 2)[1]);
							} else if ("epoch = " in line) {
								version.prepend (":");
								version.prepend (line.split (" = ", 2)[1]);
							// don't compute optdepends, it will be done by makepkg
							} else if ("optdepends" in line) {
								// pass
								continue;
							// compute depends, makedepends and checkdepends:
							// list name may contains arch, e.g. depends_x86_64
							// depends, provides, replaces and conflicts in pkgbase section are stored
							// in order to be added after if the list in pkgname is empty,
							// makedepends will be added in depends, checkdepends are not needed with --nocheck
							} else if ("depends" in line) {
								if ("depends = " in line || "depends_%s = ".printf (arch) in line) {
									string depend = line.split (" = ", 2)[1];
									if ("checkdepends" in line) {
										// not needed: makepkg is run with --nocheck
									} else if (current_section_is_pkgbase) {
										if ("makedepends" in line) {
											global_makedepends.add ((owned) depend);
										} else {
											global_depends.add ((owned) depend);
										}
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.depends.add ((owned) depend);
										}
									}
								}
							} else if ("provides" in line) {
								if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
									string provide = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_provides.add ((owned) provide);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.provides.add ((owned) provide);
										}
									}
								}
							} else if ("conflicts" in line) {
								if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
									string conflict = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_conflicts.add ((owned) conflict);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.conflicts.add ((owned) conflict);
										}
									}
								}
							} else if ("replaces" in line) {
								if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
									string replace = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_replaces.add ((owned) replace);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.replaces.add ((owned) replace);
										}
									}
								}
							} else if ("pkgname = " in line) {
								string pkgname_found = line.split (" = ", 2)[1];
								current_section = pkgname_found;
								current_section_is_pkgbase = false;
								if (!pkgnames_table.contains (pkgname_found)) {
									var aur_pkg_found = new AURPackageStatic ();
									aur_pkg_found.name = pkgname_found;
									aur_pkg_found.version = version.str;
									aur_pkg_found.desc = desc;
									aur_pkg_found.packagebase = pkgbase;
									pkgnames_table.insert (pkgname_found, aur_pkg_found);
									pkgnames_found.add ((owned) pkgname_found);
								}
							}
						}
						foreach (unowned string pkgname_found in pkgnames_found) {
							already_checked_aur_dep.add (pkgname_found);
						}
						// create fake aur db entries
						foreach (unowned string pkgname_found in pkgnames_found) {
							unowned AURPackage? aur_pkg_found = pkgnames_table.get (pkgname_found);
							// populate empty list will global ones
							if (global_depends.length != 0 && aur_pkg_found.depends.length == 0) {
								aur_pkg_found.depends = global_depends.copy (strdup);
							}
							if (global_provides.length != 0 && aur_pkg_found.provides.length == 0) {
								aur_pkg_found.provides = global_provides.copy (strdup);
							}
							if (global_conflicts.length != 0 && aur_pkg_found.conflicts.length == 0) {
								aur_pkg_found.conflicts = global_conflicts.copy (strdup);
							}
							if (global_replaces.length != 0 && aur_pkg_found.replaces.length == 0) {
								aur_pkg_found.replaces = global_replaces.copy (strdup);
							}
							// add makedepends in depends
							foreach (unowned string global_makedepend in global_makedepends) {
								aur_pkg_found.depends.add (global_makedepend);
							}
							foreach (unowned string dep_string in aur_pkg_found.depends) {
								add_dep_to_check (dep_string, pkgname, dep_to_check);
							}
							yield write_desc_file (pkgname_found, aur_pkg_found.version, aur_pkg_found.packagebase, aur_pkg_found.desc, arch,
													aur_pkg_found.depends, aur_pkg_found.conflicts, aur_pkg_found.provides, aur_pkg_found.replaces);
						}
					} catch (Error e) {
						var details = new GenericArray<string> (1);
						details.add (dgettext (null, "Failed to check %s dependencies").printf (pkgname));
						emit_error (dgettext (null, "Failed to prepare transaction"), details);
						return false;
					}
				} else {
					// use aur infos
					already_checked_aur_dep.add (aur_pkg.name);
					// add makedepends in depends, checkdepends are not needed: makepkg is run with --nocheck
					var depends = new GenericArray<string> ();
					foreach (unowned string name in aur_pkg.depends) {
						depends.add (name);
					}
					foreach (unowned string name in aur_pkg.makedepends) {
						depends.add (name);
					}
					foreach (unowned string name in depends) {
						add_dep_to_check (name, pkgname, dep_to_check);
					}
					try {
						yield write_desc_file (aur_pkg.name, aur_pkg.version, aur_pkg.packagebase, aur_pkg.desc, arch,
												depends, aur_pkg.conflicts, aur_pkg.provides, aur_pkg.replaces);
					} catch (Error e) {
						var details = new GenericArray<string> (1);
						details.add (dgettext (null, "Failed to check %s dependencies").printf (pkgname));
						emit_error (dgettext (null, "Failed to prepare transaction"), details);
						return false;
					}
				}
			}
			if (dep_to_check.length > 0) {
				return yield check_aur_dep_list (dep_to_check);
			}
			return true;
		}

		// the build dir whose .SRCINFO lists pkgname, null if not found,
		// .SRCINFO files are regenerated if needed
		async File? find_build_dir (string real_aur_build_dir, string pkgname) {
			var builddir = File.new_for_path (real_aur_build_dir);
			try {
				FileEnumerator enumerator = yield builddir.enumerate_children_async ("standard::name,standard::type", FileQueryInfoFlags.NONE);
				List<FileInfo> infos;
				while ((infos = yield enumerator.next_files_async (50)) != null) {
					foreach (unowned FileInfo info in infos) {
						if (info.get_file_type () != FileType.DIRECTORY) {
							continue;
						}
						File child = builddir.get_child (info.get_name ());
						if (!child.get_child ("PKGBUILD").query_exists ()) {
							continue;
						}
						// only regenerated if the PKGBUILD is newer, in a thread
						if (!(yield database.regenerate_srcinfo_async (info.get_name (), build_cancellable))) {
							continue;
						}
						if (yield srcinfo_has_pkgname (child.get_child (".SRCINFO"), pkgname)) {
							return child;
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return null;
		}

		async bool srcinfo_has_pkgname (File srcinfo, string pkgname) {
			try {
				var dis = new DataInputStream (yield srcinfo.read_async ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					if (line.has_prefix ("pkgname = ") && line.substring (10) == pkgname) {
						return true;
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return false;
		}

		// a dependency not found in installed and sync packages will be looked for in the AUR
		void add_dep_to_check (string dep_string, string pkgname, GenericArray<string> dep_to_check) {
			if (database.has_installed_satisfier (dep_string) || database.has_sync_satisfier (dep_string)) {
				return;
			}
			string dep_name = database.get_alpm_dep_name (dep_string);
			if (dep_name in already_checked_aur_dep) {
				return;
			}
			dep_to_check.add (dep_name);
			if (pkgname in clone_deps_files) {
				clone_files.add (dep_name);
				clone_deps_files.add (dep_name);
			}
		}

		static void append_desc_entry (StringBuilder content, string key, string? value) {
			content.append_c ('%');
			content.append (key);
			content.append ("%\n");
			content.append (value ?? "");
			content.append ("\n\n");
		}

		static void append_desc_list (StringBuilder content, string key, GenericArray<string> values) {
			if (values.length == 0) {
				return;
			}
			content.append_c ('%');
			content.append (key);
			content.append ("%\n");
			foreach (unowned string value in values) {
				content.append (value);
				content.append_c ('\n');
			}
			content.append_c ('\n');
		}

		// write the desc file of a package in the fake aur db
		async void write_desc_file (string name, string version, string? pkgbase, string? desc, string arch,
									GenericArray<string> depends, GenericArray<string> conflicts,
									GenericArray<string> provides, GenericArray<string> replaces) throws Error {
			string pkgdir = "%s-%s".printf (name, version);
			aur_desc_list.add (pkgdir);
			var dir = File.new_for_path (Path.build_filename (aurdb_path, pkgdir));
			if (!dir.query_exists ()) {
				yield dir.make_directory_async ();
			}
			var content = new StringBuilder ();
			// fake filename
			append_desc_entry (content, "FILENAME", "%s-%s-any.pkg.tar".printf (name, version));
			append_desc_entry (content, "NAME", name);
			append_desc_entry (content, "VERSION", version);
			append_desc_entry (content, "BASE", pkgbase);
			append_desc_entry (content, "DESC", desc);
			append_desc_entry (content, "ARCH", arch);
			append_desc_list (content, "DEPENDS", depends);
			append_desc_list (content, "CONFLICTS", conflicts);
			append_desc_list (content, "PROVIDES", provides);
			append_desc_list (content, "REPLACES", replaces);
			// always recreate desc in case of .SRCINFO modifications
			FileOutputStream fos = yield dir.get_child ("desc").replace_async (null, false, FileCreateFlags.NONE);
			size_t bytes_written;
			yield fos.write_all_async (content.str.data, Priority.DEFAULT, null, out bytes_written);
			yield fos.close_async ();
		}

		async bool clone_build_files_if_needed (string pkgdir, string pkgname) {
			File? clone_dir = File.new_for_path (pkgdir);
			if (!clone_dir.query_exists ()) {
				if (pkgname in clone_files) {
					// clone build files
					emit_action (dgettext (null, "Cloning %s build files").printf (pkgname) + "...");
					clone_dir = yield database.clone_build_files_async (pkgname, false, build_cancellable);
					if (build_cancellable.is_cancelled ()) {
						return false;
					}
					if (clone_dir == null) {
						// error
						return false;
					}
					// generating srcinfo
					emit_action (dgettext (null, "Generating %s information").printf (pkgname) + "...");
					bool success = yield database.regenerate_srcinfo_async (pkgname, build_cancellable);
					if (!success) {
						return false;
					}
				} else {
					var details = new GenericArray<string> (1);
					details.add (dgettext (null, "target not found: %s").printf (pkgname));
					emit_error (dgettext (null, "Failed to prepare transaction"), details);
					return false;
				}
			}
			return true;
		}

		// false if a needed key could not be imported, the build would fail
		async bool check_signatures (string pkgdir, string pkgname) {
			File? clone_dir = File.new_for_path (pkgdir);
			if (clone_dir.query_exists ()) {
				var srcinfo = clone_dir.get_child (".SRCINFO");
				try {
					// read .SRCINFO
					var dis = new DataInputStream (yield srcinfo.read_async ());
					string? line;
					var global_validpgpkeys = new GenericArray<string> ();
					while ((line = yield dis.read_line_async ()) != null) {
						if ("validpgpkeys = " in line) {
							global_validpgpkeys.add (line.split (" = ", 2)[1]);
						}
					}
					// check signature
					if (global_validpgpkeys.length > 0) {
						return yield check_signature (pkgname, global_validpgpkeys);
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			return true;
		}

		async bool check_signature (string pkgname, GenericArray<string> keys) {
			bool all_imported = true;
			foreach (unowned string key in keys) {
				var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
				try {
					// keys come from the AUR package: "--" so they can't be read as options
					var process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--list-keys", "--", key});
					yield process.wait_async ();
					if (process.get_if_exited ()) {
						if (process.get_exit_status () != 0) {
							// key is not imported in keyring
							// try to get key infos
							bool success = false;
							launcher.set_flags (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
							// untranslated messages to read the keyserver used
							launcher.setenv ("LC_ALL", "C", true);
							process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--search-keys", "--", key});
							// read the whole output before waiting,
							// gpg could block on a full pipe
							var dis = new DataInputStream (process.get_stdout_pipe ());
							var pgp_key = new PGPKey (key, pkgname);
							string? line;
							// get the configured keyserver, the search only gives its address
							try {
								var gpgconf = new Subprocess.newv ({"gpgconf", "--list-options", "dirmngr"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
								string? gpgconf_output;
								yield gpgconf.communicate_utf8_async (null, null, out gpgconf_output, null);
								if (gpgconf_output != null) {
									foreach (unowned string gpgconf_line in gpgconf_output.split ("\n")) {
										pgp_key.parse_dirmngr_options (gpgconf_line);
									}
								}
							} catch (Error e) {
								warning (e.message);
							}
							while ((line = yield dis.read_line_async ()) != null) {
								pgp_key.parse_search_output (line);
							}
							yield process.wait_async ();
							if (process.get_if_exited ()) {
								if (process.get_exit_status () == 0) {
									// frontends get the key details with get_pgp_key ()
									pgp_keys.replace (key, pgp_key);
									// keep the first uid as owner for frontends using it
									string? owner = pgp_key.uids.length > 0 ? pgp_key.uids[0] : null;
									bool import = yield ask_import_key (pkgname, key, owner);
									pgp_keys.remove (key);
									if (import) {
										var cmdline = new GenericArray<string> (5);
										cmdline.add ("gpg");
										cmdline.add ("--with-colons");
										cmdline.add ("--batch");
										cmdline.add ("--recv-keys");
										cmdline.add ("--");
										cmdline.add (key);
										int status = yield run_build_cmd_line (cmdline, null);
										emit_script_output ("");
										if (status == 0) {
											success = true;
										}
									}
								}
							}
							if (!success) {
								emit_error (dgettext (null, "key %s could not be imported").printf (key), new GenericArray<string> ());
								all_imported = false;
							}
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			return all_imported;
		}

		public async bool run_async () {
			if (transaction_interface == null) {
				var details = new GenericArray<string> (1);
				details.add ("failed to connect to dbus daemon");
				emit_error ("Daemon Error", details);
				return false;
			}
			bool success = true;
			reboot_required = false;
			pending_reboot = false;
			if (sysupgrading ||
				to_install.length > 0 ||
				to_remove.length > 0 ||
				to_load_local.length > 0 ||
				to_load_remote.length > 0 ||
				to_build.length > 0) {
				success = yield run_alpm_transaction ();
				if (!dry_run && success) {
					if (!download_only && to_build_queue.get_length () != 0) {
						success = yield build_aur_packages ();
						build_cancellable.reset ();
					}
					to_build_queue.clear ();
					if (success) {
						if (snap_to_install.length > 0 ||
							snap_to_remove.length > 0) {
							success = yield run_snap_transaction ();
						}
					}
					if (success) {
						if (flatpak_to_install.length > 0 ||
							flatpak_to_remove.length > 0 ||
							flatpak_to_upgrade.length > 0) {
							success = yield run_flatpak_transaction ();
						}
					}
				}
				remove_authorization ();
				if (!dry_run) {
					database.refresh ();
				}
				if (success) {
					reboot_required = !dry_run && pending_reboot;
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
				}
				// do not keep anything for the next transaction, e.g. after a dry run
				to_build_queue.clear ();
				clear_snaps_flatpaks ();
				sysupgrading = false;
				alpm_sysupgrade = false;
				force_refresh = false;
				to_install.remove_all ();
				to_remove.remove_all ();
				to_load_local.remove_all ();
				to_load_remote.remove_all ();
				to_build.remove_all ();
				clone_files.remove_all ();
				clone_deps_files.remove_all ();
				ignorepkgs.remove_all ();
				overwrite_files.remove_all ();
				to_install_as_dep.remove_all ();
			} else {
				if (snap_to_install.length > 0) {
					emit_action (dgettext (null, "Preparing") + "...");
					start_preparing ();
					yield ask_classic_snaps ();
					stop_preparing ();
				}
				// ask confirmation
				var summary = new TransactionSummary ();
				add_snaps_flatpaks_to_summary (summary);
				if (summary.to_install.length == 0 &&
					summary.to_remove.length == 0 &&
					summary.to_upgrade.length == 0) {
					emit_action (dgettext (null, "Nothing to do") + ".");
					clear_snaps_flatpaks ();
					return false;
				}
				success = yield ask_commit (summary);
				if (!success) {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
				}
				if (dry_run || !success) {
					clear_snaps_flatpaks ();
					return dry_run;
				}
				if (snap_to_install.length > 0 ||
					snap_to_remove.length > 0) {
					success = yield run_snap_transaction ();
				}
				if (success) {
					if (flatpak_to_install.length > 0 ||
						flatpak_to_remove.length > 0 ||
						flatpak_to_upgrade.length > 0) {
						success = yield run_flatpak_transaction ();
					}
				}
				if (success) {
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
				}
				database.refresh ();
				clear_snaps_flatpaks ();
			}
			return success;
		}

		void clear_snaps_flatpaks () {
			snap_to_install.remove_all ();
			snap_to_remove.remove_all ();
			flatpak_to_install.remove_all ();
			flatpak_to_remove.remove_all ();
			flatpak_to_upgrade.remove_all ();
		}

		// ask confirmation for snaps with classic confinement, refused ones are not installed
		async void ask_classic_snaps () {
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			var not_install = new GenericArray<string> ();
			unowned string snap_name;
			SnapPackage pkg;
			while (iter.next (out snap_name, out pkg)) {
				if (pkg.confined != dgettext (null, "Yes")) {
					bool answer = yield ask_snap_install_classic (pkg.app_name);
					if (!answer) {
						not_install.add (snap_name);
					}
				}
			}
			foreach (unowned string name in not_install) {
				snap_to_install.remove (name);
			}
		}

		void add_snaps_flatpaks_to_summary (TransactionSummary summary) {
			var snap_iter = HashTableIter<string, SnapPackage> (snap_to_install);
			SnapPackage snap_pkg;
			while (snap_iter.next (null, out snap_pkg)) {
				summary.add_item (snap_pkg, SummaryReason.REQUESTED, null, 0);
				summary.download_size += snap_pkg.download_size;
				summary.to_install.add (snap_pkg);
			}
			snap_iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (snap_iter.next (null, out snap_pkg)) {
				summary.add_item (snap_pkg, SummaryReason.REQUESTED, null, snap_pkg.installed_size);
				summary.to_remove.add (snap_pkg);
			}
			var flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
			FlatpakPackage flatpak_pkg;
			while (flatpak_iter.next (null, out flatpak_pkg)) {
				summary.add_item (flatpak_pkg, SummaryReason.REQUESTED, null, 0);
				summary.download_size += flatpak_pkg.download_size;
				summary.to_install.add (flatpak_pkg);
			}
			flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
			while (flatpak_iter.next (null, out flatpak_pkg)) {
				summary.add_item (flatpak_pkg, SummaryReason.REQUESTED, null, flatpak_pkg.installed_size);
				summary.to_remove.add (flatpak_pkg);
			}
			flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
			while (flatpak_iter.next (null, out flatpak_pkg)) {
				summary.add_item (flatpak_pkg, SummaryReason.REQUESTED, null, flatpak_pkg.installed_size);
				summary.download_size += flatpak_pkg.download_size;
				summary.to_upgrade.add (flatpak_pkg);
			}
		}

		void add_config_ignore_pkgs () {
			foreach (unowned string name in config.ignorepkgs) {
				ignorepkgs.add (name);
			}
		}

		async void add_optdeps () {
			var to_add_to_install = new GenericSet<string?> (str_hash, str_equal);
			foreach (unowned string name in to_install) {
				// do not check if reinstall
				if (!database.is_installed_pkg (name)) {
					var uninstalled_optdeps = yield database.get_uninstalled_optdeps_async (name);
					var real_uninstalled_optdeps = new GenericArray<string> ();
					foreach (unowned string optdep in uninstalled_optdeps) {
						string[] splitted = optdep.split (": ", 2);
						unowned string optdep_name = splitted[0];
						if (!(optdep_name in to_install) && !(optdep_name in to_add_to_install)) {
							real_uninstalled_optdeps.add (optdep);
						}
					}
					if (real_uninstalled_optdeps.length > 0) {
						var optdeps = yield choose_optdeps (name, real_uninstalled_optdeps);
						foreach (unowned string optdep in optdeps) {
							string optdep_name = optdep.split (": ", 2)[0];
							to_add_to_install.add ((owned) optdep_name);
						}
					}
				}
			}
			foreach (unowned string name in to_add_to_install) {
				add_pkg_to_install (name);
				add_pkg_to_mark_as_dep (name);
			}
		}

		async bool run_alpm_transaction () {
			emit_action (dgettext (null, "Preparing") + "...");
			// check if we need to sysupgrade
			bool auto_sysupgrading = false;
			if (!dry_run && !sysupgrading && !config.simple_install && to_install.length > 0) {
				foreach (unowned string name in to_install) {
					if (database.is_installed_pkg (name)) {
						if (database.is_sync_pkg (name)) {
							AlpmPackage? pkg = database.get_installed_pkg (name);
							if (pkg.installed_version != pkg.version) {
								auto_sysupgrading = true;
								break;
							}
						}
					} else {
						auto_sysupgrading = true;
						break;
					}
				}
			}
			alpm_sysupgrade = sysupgrading || auto_sysupgrading;
			bool success = false;
			if (!dry_run && !no_refresh && alpm_sysupgrade) {
				success = yield get_authorization_async ();
				if (!success) {
					return false;
				}
				// don't refresh AUR db if sysupgrading is not explicitly requested
				success = yield refresh_dbs_real (sysupgrading && config.enable_aur);
				if (!success) {
					return false;
				}
			}
			if (to_install.length > 0) {
				yield add_optdeps ();
			}
			if (sysupgrading && config.check_aur_updates) {
				var updates = yield database.get_aur_updates_async (ignorepkgs);
				foreach (unowned AURPackage aur_pkg in updates.aur_updates) {
					add_pkg_to_build (aur_pkg.name, true, true);
				}
				foreach (unowned AURPackage aur_pkg in updates.ignored_aur_updates) {
					emit_script_output ("%s: %s".printf (
										dgettext (null, "Warning"),
										dgettext (null, "%1$s: ignoring package upgrade (%2$s => %3$s)").printf (
												aur_pkg.name, aur_pkg.installed_version, aur_pkg.version)));
				}
			}
			if (alpm_sysupgrade) {
				if (to_build.length > 0) {
					// run sysupgrade first
					var to_build_copy = (owned) to_build;
					to_build = new GenericSet<string?> (str_hash, str_equal);
					TransactionSummary summary;
					success = yield trans_prepare (out summary);
					if (success) {
						success = yield trans_run (summary);
					}
					if (!success) {
						return false;
					}
					to_build = (owned) to_build_copy;
				}
			}
			if (to_build.length > 0) {
				success = yield compute_aur_build_list ();
				if (!success) {
					return false;
				}
			}
			TransactionSummary summary;
			success = yield trans_prepare (out summary);
			if (success) {
				success = yield trans_run (summary);
			}
			return success;
		}

		async bool trans_check_prepare (out TransactionSummary summary) {
			bool success = false;
			summary = new TransactionSummary ();
			if (to_load_remote.length > 0) {
				success = yield get_authorization_async ();
				if (!success) {
					return false;
				}
				try {
					var to_load_remote_array = new GenericArray<string> (to_load_remote.length);
					foreach (unowned string url in to_load_remote) {
						to_load_remote_array.add (url);
					}
					string[] dload_paths = yield transaction_interface.download_pkgs (to_load_remote_array);
					if (dload_paths.length == 0) {
						// error
						success = false;
					} else {
						// replace to_load_remote with the dload_paths
						to_load_remote.remove_all ();
						foreach (unowned string path in dload_paths) {
							to_load_remote.add (path);
						}
					}
				} catch (Error e) {
					report_daemon_error ("download_pkgs", e);
					success = false;
				}
				if (!success) {
					return false;
				}
			}
			var new_summary = new TransactionSummary ();
			var new_unresolvables = new GenericArray<string> ();
			try {
				success = yield run_in_thread ("trans_check_prepare", context, () => {
					// not cancellable
					return alpm_utils.trans_check_prepare (sink,
															new Cancellable (),
															alpm_sysupgrade,
															config.enable_downgrade,
															config.simple_install,
															trans_flags,
															to_install,
															to_remove,
															to_load_local,
															to_load_remote,
															to_build,
															ignorepkgs,
															overwrite_files,
															ref new_summary,
															out new_unresolvables);
				});
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add (e.message);
				emit_error (dgettext (null, "Failed to prepare transaction"), details);
				success = false;
			}
			summary = new_summary;
			unresolvables = new_unresolvables;
			return success;
		}

		public async void check_dbs () {
			if (database.dbs_missing) {
				// aur db will also be refreshed if enabled
				yield refresh_dbs_async ();
				database.refresh ();
			} else if (config.enable_aur) {
				string absolute_path = Path.build_filename (config.db_path, "sync", "packages-meta-ext-v1.json.gz");
				var zipfile = File.new_for_path (absolute_path);
				if (!zipfile.query_exists ()) {
					yield refresh_dbs_async ();
					database.refresh ();
				}
			}
		}

		public async bool refresh_dbs_async () {
			return yield refresh_dbs_real (config.enable_aur);
		}

		async bool refresh_dbs_real (bool refresh_aur) {
			bool success = false;
			try {
				// trans_refresh returns false only if cancelled
				success = yield transaction_interface.trans_refresh (force_refresh);
				if (success && refresh_aur) {
					bool aur_success = yield transaction_interface.trans_refresh_aur (force_refresh);
					if (!aur_success) {
						emit_warning (dgettext (null, "Failed to synchronize AUR database"));
					}
				}
			} catch (Error e) {
				report_daemon_error ("trans_refresh", e);
				success = false;
			}
			return success;
		}

		public async bool refresh_files_dbs_async () {
			bool success = false;
			try {
				success = yield transaction_interface.trans_refresh_files (force_refresh);
			} catch (Error e) {
				report_daemon_error ("trans_refresh_files", e);
				success = false;
			}
			return success;
		}

		async bool trans_prepare (out TransactionSummary summary) {
			start_preparing ();
			add_config_ignore_pkgs ();
			set_flags ();
			bool success = yield trans_check_prepare (out summary);
			stop_preparing ();
			if (!success) {
				if (to_build.length > 0) {
					var empty_summary = new TransactionSummary ();
					if (yield ask_edit_build_files_real (empty_summary)) {
						foreach (unowned string name in to_build) {
							bool found = unresolvables.find_with_equal_func (name, str_equal, null);
							if (!found) {
								unresolvables.add (name);
							}
						}
						// build files are stored by pkgbase, which differs
						// from the package name for split packages
						var pkgbases = new GenericArray<string> ();
						var aur_pkgs = yield database.get_aur_pkgs_async (unresolvables);
						foreach (unowned string name in unresolvables) {
							unowned AURPackage? aur_pkg = aur_pkgs.lookup (name);
							string pkgbase = aur_pkg == null ? name : aur_pkg.packagebase;
							if (aur_pkg != null && name in clone_files) {
								clone_files.add (pkgbase);
							}
							if (!pkgbases.find_with_equal_func (pkgbase, str_equal, null)) {
								pkgbases.add (pkgbase);
							}
						}
						unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
						foreach (unowned string pkgbase in pkgbases) {
							string pkgdir = Path.build_filename (real_aur_build_dir, pkgbase);
							success = yield clone_build_files_if_needed (pkgdir, pkgbase);
							if (!success) {
								var details = new GenericArray<string> (1);
								details.add (dgettext (null, "Failed to clone %s build files").printf (pkgbase));
								emit_error (dgettext (null, "Failed to prepare transaction"), details);
								unresolvables = new GenericArray<string> ();
								return false;
							}
						}
						yield edit_build_files (pkgbases);
						unresolvables = new GenericArray<string> ();
						emit_script_output ("");
						success = yield compute_aur_build_list ();
						if (!success) {
							return false;
						}
						success = yield trans_prepare (out summary);
					} else {
						emit_action (dgettext (null, "Transaction cancelled") + ".");
					}
				}
			}
			return success;
		}

		async bool trans_run (TransactionSummary summary) {
			if (summary.aur_pkgbases_to_build.length != 0) {
				// populate build queue
				to_build_queue.clear ();
				foreach (unowned string name in summary.aur_pkgbases_to_build) {
					to_build_queue.push_tail (name);
				}
				aur_pkgs_to_install.remove_all ();
				foreach (unowned Package pkg in summary.to_build) {
					unowned string pkgname = pkg.name;
					aur_pkgs_to_install.add (pkgname);
					if (!to_build.contains (pkgname)) {
						// check if pkg provide a name in to_build
						var alpmpkg = pkg as AlpmPackage;
						if (alpmpkg != null) {
							foreach (unowned string provide in alpmpkg.provides) {
								string provide_name = database.get_alpm_dep_name (provide);
								if (to_build.contains (provide_name)) {
									// replace with provider
									to_build.remove (provide_name);
									to_build.add (pkgname);
									break;
								}
							}
						}
					}
				}
				if (yield ask_edit_build_files_real (summary)) {
					unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
					foreach (unowned string pkgname in summary.aur_pkgbases_to_build) {
						string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
						bool success = yield clone_build_files_if_needed (pkgdir, pkgname);
						if (!success) {
							var details = new GenericArray<string> (1);
							details.add (dgettext (null, "Failed to clone %s build files").printf (pkgname));
							emit_error (dgettext (null, "Failed to prepare transaction"), details);
							return false;
						}
					}
					yield edit_build_files (summary.aur_pkgbases_to_build);
					emit_script_output ("");
					bool success = yield compute_aur_build_list ();
					if (!success) {
						return false;
					}
					TransactionSummary new_summary;
					success = yield trans_prepare (out new_summary);
					if (success) {
						return yield trans_run (new_summary);
					}
				}
			}
			if (summary.to_install.length != 0 ||
				summary.to_upgrade.length != 0 ||
				summary.to_downgrade.length != 0 ||
				summary.to_reinstall.length != 0 ||
				summary.conflicts_to_remove.length != 0 ||
				summary.to_remove.length != 0) {
				foreach (unowned Package pkg in summary.to_install) {
					unowned string pkgname = pkg.name;
					if (!to_install.contains (pkgname) &&
						!summary.to_load.find_with_equal_func (pkgname, str_equal)) {
						to_install.add (pkgname);
						bool find_top_provider = false;
						// check if pkg provide a name in to_install
						var alpmpkg = pkg as AlpmPackage;
						if (alpmpkg != null) {
							foreach (unowned string provide in alpmpkg.provides) {
								string provide_name = database.get_alpm_dep_name (provide);
								if (to_install.contains (provide_name)) {
									// replace with provider
									to_install.remove (provide_name);
									to_install.add (pkgname);
									find_top_provider = true;
									break;
								}
							}
						}
						if (!find_top_provider) {
							to_install_as_dep.add (pkgname);
						}
					}
				}
				to_remove.remove_all ();
				foreach (unowned Package pkg in summary.to_remove) {
					to_remove.add (pkg.name);
				}
				// ask_commit_real add flatpaks and snaps
				bool success = yield ask_commit_real (summary);
				// remove existing aur db
				if (!success && summary.to_build.length != 0) {
					FileUtils.unlink (Path.build_filename (tmp_path, "pamac_aur.db"));
				}
				if (dry_run) {
					return true;
				}
				if (success) {
					// clone build files and check signatures
					if (!(yield prepare_build_files (summary.aur_pkgbases_to_build))) {
						return false;
					}
					success = yield get_authorization_async ();
					if (!success) {
						return false;
					}
					try {
						var request = new TransactionRequest ();
						request.sysupgrade = alpm_sysupgrade;
						request.enable_downgrade = config.enable_downgrade;
						request.simple_install = config.simple_install;
						request.keep_built_pkgs = config.keep_built_pkgs;
						request.trans_flags = trans_flags;
						request.to_install = set_to_strv (to_install);
						request.to_remove = set_to_strv (to_remove);
						request.to_load_local = set_to_strv (to_load_local);
						request.to_load_remote = set_to_strv (to_load_remote);
						request.to_install_as_dep = set_to_strv (to_install_as_dep);
						request.ignorepkgs = set_to_strv (ignorepkgs);
						request.overwrite_files = set_to_strv (overwrite_files);
						success = yield transaction_interface.trans_run (request);
						if (success && summary.requires_reboot) {
							pending_reboot = true;
						}
					} catch (Error e) {
						report_daemon_error ("trans_run", e);
						success = false;
		 			}
		 			return success;
				} else {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			} else if (summary.to_build.length != 0) {
				// only AUR packages to build
				bool success = yield ask_commit_real (summary);
				// remove existing aur db
				if (!success) {
					FileUtils.unlink (Path.build_filename (tmp_path, "pamac_aur.db"));
				}
				if (dry_run) {
					return true;
				}
				if (success) {
					// clone build files and check signatures
					if (!(yield prepare_build_files (summary.aur_pkgbases_to_build))) {
						return false;
					}
					// the built packages are installed later if the build succeeds
					if (summary.requires_reboot) {
						pending_reboot = true;
					}
					// get_authorization here before building
					return yield get_authorization_async ();
				} else {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			} else {
				emit_action (dgettext (null, "Nothing to do") + ".");
				return true;
			}
		}

		// clone build files if needed and check their signature keys
		async bool prepare_build_files (GenericArray<string> pkgbases) {
			unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
			foreach (unowned string pkgbase in pkgbases) {
				string pkgdir = Path.build_filename (real_aur_build_dir, pkgbase);
				if (!(yield clone_build_files_if_needed (pkgdir, pkgbase))) {
					var details = new GenericArray<string> (1);
					details.add (dgettext (null, "Failed to clone %s build files").printf (pkgbase));
					emit_error (dgettext (null, "Failed to prepare transaction"), details);
					return false;
				}
				if (!(yield check_signatures (pkgdir, pkgbase))) {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			}
			return true;
		}

		void set_flags () {
			trans_flags = 0;
			if (download_only) {
				trans_flags |= (1 << 9); //Alpm.TransFlag.DOWNLOADONLY
			}
			// install flags
			if (install_if_needed) {
				trans_flags |= (1 << 13); //Alpm.TransFlag.NEEDED
			}
			if (install_as_dep) {
				trans_flags |= (1 << 8); //Alpm.TransFlag.ALLDEPS
			} else if (install_as_explicit) {
				trans_flags |= (1 << 14); //Alpm.TransFlag.ALLEXPLICIT
			}
			// remove flags
			if (remove_if_unneeded) {
				trans_flags |= (1 << 15); //Alpm.TransFlag.UNNEEDED
			} else if (cascade) {
				trans_flags |= (1 << 4); //Alpm.TransFlag.CASCADE
			}
			if (database.config.recurse) {
				trans_flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			if (!keep_config_files) {
				trans_flags |= (1 << 2); //Alpm.TransFlag.NOSAVE
			}
		}

		public void add_pkg_to_install (string name) {
			to_install.add (name);
		}

		public void add_pkg_to_remove (string name) {
			to_remove.add (name);
		}

		public void add_path_to_load (string path) {
			if ("://" in path) {
				to_load_remote.add (path);
			} else {
				to_load_local.add (path);
			}
		}

		public void add_pkg_to_build (string name, bool clone_build_files, bool clone_deps_build_files) {
			if (!config.support_aur) {
				return;
			}
			to_build.add (name);
			if (clone_build_files) {
				clone_files.add (name);
			}
			if (clone_deps_build_files) {
				clone_deps_files.add (name);
			}
		}

		public void add_temporary_ignore_pkg (string name) {
			ignorepkgs.add (name);
		}

		public void add_overwrite_file (string glob) {
			overwrite_files.add (glob);
		}

		public void add_pkg_to_mark_as_dep (string name) {
			to_install_as_dep.add (name);
		}

		public void add_pkgs_to_upgrade (bool force_refresh) {
			this.force_refresh = force_refresh;
			sysupgrading = true;
		}

		public void add_snap_to_install (SnapPackage pkg) {
			if (config.enable_snap) {
				snap_to_install.insert (pkg.name, pkg);
			} else {
				warning ("snap support disabled");
			}
		}

		public void add_snap_to_remove (SnapPackage pkg) {
			if (config.enable_snap) {
				snap_to_remove.insert (pkg.name, pkg);
			} else {
				warning ("snap support disabled");
			}
		}

		async bool run_snap_transaction () {
			var snap_to_install_array = new GenericArray<string> (snap_to_install.length);
			var snap_to_remove_array = new GenericArray<string> (snap_to_remove.length);
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			unowned string name;
			while (iter.next (out name, null)) {
				snap_to_install_array.add (name);
			}
			iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (iter.next (out name, null)) {
				snap_to_remove_array.add (name);
			}
			snap_to_install.remove_all ();
			snap_to_remove.remove_all ();
			bool success = false;
			// emit download signal to allow cancellation
			start_downloading ();
			try {
				success = yield transaction_interface.snap_trans_run (snap_to_install_array, snap_to_remove_array);
			} catch (Error e) {
				report_daemon_error ("snap_trans_run", e);
			}
			stop_downloading ();
			return success;
		}

		public async bool snap_switch_channel_async (string snap_name, string channel) {
			if (config.enable_snap) {
				try {
					return yield transaction_interface.snap_switch_channel (snap_name, channel);
				} catch (Error e) {
					report_daemon_error ("snap_switch_channel", e);
				}
			} else {
				warning ("snap support disabled");
			}
			return false;
		}

		public void add_flatpak_to_install (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_install.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		public void add_flatpak_to_remove (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_remove.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		public void add_flatpak_to_upgrade (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_upgrade.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		async bool run_flatpak_transaction () {
			var flatpak_to_install_array = new GenericArray<string> (flatpak_to_install.length);
			var flatpak_to_remove_array = new GenericArray<string> (flatpak_to_remove.length);
			var flatpak_to_upgrade_array = new GenericArray<string> (flatpak_to_upgrade.length);
			var iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
			unowned string id;
			while (iter.next (out id, null)) {
				flatpak_to_install_array.add (id);
			}
			iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
			while (iter.next (out id, null)) {
				flatpak_to_remove_array.add (id);
			}
			iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
			while (iter.next (out id, null)) {
				flatpak_to_upgrade_array.add (id);
			}
			flatpak_to_install.remove_all ();
			flatpak_to_remove.remove_all ();
			flatpak_to_upgrade.remove_all ();
			bool success = false;
			// emit download signal to allow cancellation
			start_downloading ();
			try {
				success = yield transaction_interface.flatpak_trans_run (flatpak_to_install_array,
																flatpak_to_remove_array,
																flatpak_to_upgrade_array);
			} catch (Error e) {
				report_daemon_error ("flatpak_trans_run", e);
			}
			stop_downloading ();
			return success;
		}

		string remove_bash_colors (string msg) {
			Regex regex = /\x1B\[[0-9;]*[JKmsu]/;
			try {
				return regex.replace (msg, -1, 0, "");
			} catch (Error e) {
				return msg;
			}
		}

		// pids of the descendants of pid, from /proc/<pid>/task/<tid>/children
		static void collect_descendants (string pid, GenericArray<string> descendants) {
			try {
				var tasks = Dir.open ("/proc/%s/task".printf (pid));
				unowned string? tid;
				while ((tid = tasks.read_name ()) != null) {
					string children;
					if (!FileUtils.get_contents ("/proc/%s/task/%s/children".printf (pid, tid), out children)) {
						continue;
					}
					foreach (unowned string child in children.split (" ")) {
						if (child != "") {
							descendants.add (child);
							collect_descendants (child, descendants);
						}
					}
				}
			} catch (Error e) {
				// the process has exited
			}
		}

		// killing only the direct child would let its children run, e.g. compilers started by makepkg
		static void kill_process_tree (Subprocess process) {
			unowned string? pid = process.get_identifier ();
			if (pid == null) {
				// already exited
				return;
			}
			var descendants = new GenericArray<string> ();
			collect_descendants (pid, descendants);
			process.send_signal (Posix.Signal.INT);
			foreach (unowned string descendant in descendants) {
				Posix.kill ((Posix.pid_t) int.parse (descendant), Posix.Signal.INT);
			}
			process.send_signal (Posix.Signal.KILL);
			foreach (unowned string descendant in descendants) {
				Posix.kill ((Posix.pid_t) int.parse (descendant), Posix.Signal.KILL);
			}
		}

		// run_cmd_line_async with build_cancellable, which may be overridden:
		// returns 1 if the command can not be run or is cancelled
		async int run_build_cmd_line (GenericArray<string> args, string? working_directory) {
			try {
				return yield run_cmd_line_async (args, working_directory, build_cancellable);
			} catch (IOError.CANCELLED e) {
				return 1;
			} catch (Error e) {
				warning (e.message);
				return 1;
			}
		}

		// run a command, send its output with emit_script_output and return its exit status.
		// Throws IOError.CANCELLED when cancellable is cancelled, after killing the command
		public async virtual int run_cmd_line_async (GenericArray<string> args, string? working_directory, Cancellable cancellable) throws Error {
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			// spawnv needs a null terminated array
			GenericArray<string> args_copy = args.copy (strdup);
			args_copy.length = args_copy.length + 1;
			Subprocess process = launcher.spawnv (args_copy.data);
			var dis = new DataInputStream (process.get_stdout_pipe ());
			try {
				string? line;
				// cancellable: stop waiting for a line, the process may not print anything for a long time
				while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
					emit_script_output (remove_bash_colors (line));
				}
				yield process.wait_async (cancellable);
			} catch (IOError.CANCELLED e) {
				kill_process_tree (process);
				throw e;
			}
			return process.get_if_exited () ? process.get_exit_status () : 1;
		}

		// get name from a package file name like name-version-release-arch.pkg.tar*
		string? get_pkgname_from_filename (string filename) {
			string name = filename;
			// strip arch, release and version
			for (int i = 0; i < 3; i++) {
				int index = name.last_index_of_char ('-');
				if (index <= 0) {
					return null;
				}
				name = name.substring (0, index);
			}
			return name;
		}

		// makepkg is run in a systemd service with a dynamic user when root
		GenericArray<string> get_makepkg_cmdline (string pkgbase) {
			var cmdline = new GenericArray<string> ();
			if (Posix.geteuid () == 0) {
				cmdline.add ("systemd-run");
				cmdline.add ("--service-type=oneshot");
				cmdline.add ("--pipe");
				cmdline.add ("--wait");
				cmdline.add ("--pty");
				cmdline.add ("--property=DynamicUser=yes");
				cmdline.add ("--property=CacheDirectory=pamac");
				cmdline.add ("--property=WorkingDirectory=/var/cache/pamac/%s".printf (pkgbase));
			}
			cmdline.add ("makepkg");
			return cmdline;
		}

		async bool build_aur_packages () {
			bool success = true;
			// get a fake aur db to check deps
			unowned Alpm.DB? aur_db = null;
			var tmp_handle = database.get_tmp_handle ();
			string tmp_aurdb_path = Path.build_filename (tmp_path, "pamac_aur.db");
			string? handle_aurdb_path = null;
			if (tmp_handle != null) {
				handle_aurdb_path = Path.build_filename (tmp_handle.dbpath, "sync", "pamac_aur.db");
				try {
					yield File.new_for_path (tmp_aurdb_path).copy_async (File.new_for_path (handle_aurdb_path), FileCopyFlags.OVERWRITE);
					aur_db = tmp_handle.register_syncdb ("pamac_aur", 0);
					if (aur_db == null) {
						emit_warning (dgettext (null, "Failed to initialize AUR database"));
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			var built_pkgs = new HashTable<string, string> (str_hash, str_equal);
			var to_install_as_dep_array = new GenericArray<string> ();
			uint builds_total = to_build_queue.length;
			uint builds_done = 0;
			while (to_build_queue.length > 0) {
				string pkgname = to_build_queue.pop_head ();
				builds_done++;
				emit_transaction_progress (TransactionStep.BUILDING, builds_done, builds_total);
				build_cancellable.reset ();
				var built_pkgs_path = new GenericArray<string> ();
				unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
				string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
				// building
				building = true;
				start_building ();
				var cmdline = get_makepkg_cmdline (pkgname);
				cmdline.add ("-cCf");
				cmdline.add ("--nocheck");
				if (!config.keep_built_pkgs) {
					cmdline.add ("--nosign");
					cmdline.add ("PKGDEST=%s".printf (pkgdir));
					cmdline.add ("PKGEXT=.pkg.tar");
				}
				emit_script_output ("");
				emit_action (dgettext (null, "Building %s").printf (pkgname) + "...");
				important_details_outpout (false);
				int status = yield run_build_cmd_line (cmdline, pkgdir);
				if (status != 0 && !build_cancellable.is_cancelled ()) {
					emit_error (dgettext (null, "Failed to build %s").printf (pkgname), new GenericArray<string> ());
				}
				if (status == 0) {
					// get built pkgs path
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
					launcher.set_cwd (pkgdir);
					try {
						cmdline = get_makepkg_cmdline (pkgname);
						cmdline.add ("--packagelist");
						if (!config.keep_built_pkgs) {
							cmdline.add ("PKGDEST=%s".printf (pkgdir));
							cmdline.add ("PKGEXT=.pkg.tar");
						}
						// spawnv needs a null terminated array
						cmdline.length = cmdline.length + 1;
						Subprocess process = launcher.spawnv (cmdline.data);
						// read the whole output before waiting,
						// makepkg could block on a full pipe
						var packagelist = new GenericArray<string> ();
						var dis = new DataInputStream (process.get_stdout_pipe ());
						string? line = null;
						while ((line = yield dis.read_line_async ()) != null) {
							packagelist.add (line);
						}
						yield process.wait_async ();
						status = 1;
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
						if (status == 0) {
							foreach (unowned string path in packagelist) {
								string? name = get_pkgname_from_filename (Path.get_basename (path));
								if (name == null) {
									continue;
								}
								if (name in aur_pkgs_to_install) {
									built_pkgs_path.add (path);
									built_pkgs.insert (name, path);
									if (!(name in to_build)) {
										to_install_as_dep_array.add (name);
									}
								}
							}
						}
					} catch (Error e) {
						warning (e.message);
						status = 1;
					}
				}
				stop_building ();
				building = false;
				if (status == 0 && built_pkgs_path.length > 0) {
					bool built_pkgs_needed = false;
					if (to_build_queue.length == 0) {
						// no more package to build
						built_pkgs_needed = true;
					} else if (aur_db == null) {
						// error, can't check deps
						built_pkgs_needed = true;
					} else {
						// check if built pkgs need to be installed
						// because next pkg to build depends on one of them
						unowned string next_pkg_name = to_build_queue.peek_head ();
						unowned Alpm.Package? next_pkg = aur_db.get_pkg (next_pkg_name);
						if (next_pkg == null) {
							// error
							built_pkgs_needed = true;
						} else {
							var iter = HashTableIter<string, string> (built_pkgs);
							unowned string built_pkg_name;
							unowned string built_pkg_path;
							while (iter.next (out built_pkg_name, out built_pkg_path)) {
								unowned Alpm.Package? built_pkg = aur_db.get_pkg (built_pkg_name);
								if (built_pkg == null) {
									// error
									built_pkgs_needed = true;
									break;
								}
								unowned Alpm.List<unowned Alpm.Depend> depends = next_pkg.depends;
								while (depends != null) {
									// check if built_pkg satisfy a dep of next_pkg
									Alpm.List<unowned Alpm.Package> list = null;
									list.add (built_pkg);
									if (Alpm.find_satisfier (list, depends.data.compute_string ()) != null) {
										built_pkgs_needed = true;
										break;
									}
									depends.next ();
								}
								if (built_pkgs_needed) {
									break;
								}
							}
						}
					}
					if (built_pkgs_needed) {
						var to_load_array = new GenericArray<string> ();
						var iter = HashTableIter<string, string> (built_pkgs);
						unowned string built_pkg_path;
						while (iter.next (null, out built_pkg_path)) {
							to_load_array.add (built_pkg_path);
						}
						success = yield install_built_pkgs (to_load_array, to_install_as_dep_array);
						if (!success) {
							break;
						}
						built_pkgs.remove_all ();
						to_install_as_dep_array = new GenericArray<string> ();
					}
				} else {
					important_details_outpout (true);
					to_build_queue.clear ();
					success = false;
					break;
				}
			}
			FileUtils.unlink (tmp_aurdb_path);
			if (handle_aurdb_path != null) {
				FileUtils.unlink (handle_aurdb_path);
			}
			return success;
		}

		async bool install_built_pkgs (GenericArray<string> to_load_array, GenericArray<string> to_install_as_dep_array) {
			bool success = false;
			try {
				emit_script_output ("");
				// only the built packages, other options are false
				var request = new TransactionRequest ();
				request.keep_built_pkgs = config.keep_built_pkgs;
				request.to_load_local = to_load_array.data;
				request.to_install_as_dep = to_install_as_dep_array.data;
				success = yield transaction_interface.trans_run (request);
			} catch (Error e) {
				report_daemon_error ("trans_run", e);
				success = false;
			}
			return success;
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else {
				try {
					transaction_interface.trans_cancel ();
				} catch (Error e) {
					report_daemon_error ("trans_cancel", e);
				}
			}
		}

		// called by alpm from a worker thread: ask in context and wait for the answer
		internal int choose_provider_real (string depend, GenericArray<string> providers) {
			if (context.is_owner ()) {
				// not expected: waiting would block the context, iterate it instead
				int index = 0;
				bool answered = false;
				choose_provider.begin (depend, providers, (obj, res) => {
					index = choose_provider.end (res);
					answered = true;
				});
				while (!answered) {
					context.iteration (true);
				}
				return index;
			}
			var answer = new AsyncQueue<int?> ();
			context.invoke (() => {
				choose_provider.begin (depend, providers, (obj, res) => {
					answer.push (choose_provider.end (res));
				});
				return false;
			});
			return answer.pop ();
		}

		async bool ask_commit_real (TransactionSummary summary) {
			if (build_cancellable.is_cancelled ()) {
				return false;
			}
			if (snap_to_install.length > 0) {
				yield ask_classic_snaps ();
			}
			add_snaps_flatpaks_to_summary (summary);
			return yield ask_commit (summary);
		}

		async bool ask_edit_build_files_real (TransactionSummary summary) {
			if (dry_run) {
				return false;
			}
			// a copy: the summary is given later to ask_commit_real which adds snaps and flatpaks too
			var full_summary = new TransactionSummary ();
			GenericArray<Package>[] sources = {summary.to_install, summary.to_upgrade, summary.to_downgrade, summary.to_reinstall,
												summary.to_remove, summary.conflicts_to_remove, summary.to_build};
			GenericArray<Package>[] targets = {full_summary.to_install, full_summary.to_upgrade, full_summary.to_downgrade, full_summary.to_reinstall,
												full_summary.to_remove, full_summary.conflicts_to_remove, full_summary.to_build};
			for (int i = 0; i < sources.length; i++) {
				foreach (unowned Package pkg in sources[i]) {
					targets[i].add (pkg);
				}
			}
			foreach (unowned string pkgbase in summary.aur_pkgbases_to_build) {
				full_summary.aur_pkgbases_to_build.add (pkgbase);
			}
			foreach (unowned string name in summary.to_load) {
				full_summary.to_load.add (name);
			}
			add_snaps_flatpaks_to_summary (full_summary);
			return yield ask_edit_build_files (full_summary);
		}
	}

	// emits the progress with the signals of a transaction, in its context
	internal class MainContextSink : Object, TransactionSink {
		// the transaction owns its sink
		unowned Transaction transaction;
		unowned MainContext context;

		public MainContextSink (Transaction transaction, MainContext context) {
			this.transaction = transaction;
			this.context = context;
		}

		// run func in context: at once if called from it,
		// so the order of the calls is kept in any case
		void invoke (owned SourceFunc func) {
			context.invoke ((owned) func);
		}

		public void emit_action (string action) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_action (action);
				return false;
			});
		}

		public void emit_action_progress (string action, string status, double progress) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_action_progress (action, status, progress);
				return false;
			});
		}

		public void emit_download_progress (string action, string status, double progress) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_download_progress (action, status, progress);
				return false;
			});
		}

		public void emit_hook_progress (string action, string details, string status, double progress) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_hook_progress (action, details, status, progress);
				return false;
			});
		}

		public void emit_transaction_progress (uint step, uint64 current, uint64 total) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_transaction_progress ((TransactionStep) step, current, total);
				return false;
			});
		}

		public void emit_script_output (string message) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_script_output (message);
				return false;
			});
		}

		public void emit_warning (string message) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_warning (message);
				return false;
			});
		}

		public void emit_error (string message, GenericArray<string> details) {
			Transaction t = transaction;
			invoke (() => {
				t.emit_error (message, details);
				return false;
			});
		}

		public void important_details_outpout (bool must_show) {
			Transaction t = transaction;
			invoke (() => {
				t.important_details_outpout (must_show);
				return false;
			});
		}

		public void start_downloading () {
			Transaction t = transaction;
			invoke (() => {
				t.start_downloading ();
				return false;
			});
		}

		public void stop_downloading () {
			Transaction t = transaction;
			invoke (() => {
				t.stop_downloading ();
				return false;
			});
		}

		public void start_waiting () {
			Transaction t = transaction;
			invoke (() => {
				t.start_waiting ();
				return false;
			});
		}

		public void stop_waiting () {
			Transaction t = transaction;
			invoke (() => {
				t.stop_waiting ();
				return false;
			});
		}

		public int choose_provider (string depend, GenericArray<string> providers) {
			return transaction.choose_provider_real (depend, providers);
		}
	}
}
