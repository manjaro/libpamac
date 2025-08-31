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
	public class Transaction: Object {
		TransactionInterface transaction_interface;
		bool waiting;
		unowned Config config;
		unowned MainContext context;
		// run transaction data
		AlpmUtils alpm_utils;
		bool sysupgrading;
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

		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_download_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
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
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot (alpm_utils, context);
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (config);
			}
			waiting = false;
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
			alpm_utils.choose_provider.connect (choose_provider_real);
			alpm_utils.emit_action.connect ((sender, action) => {
				context.invoke (() => {
					emit_action (action);
					return false;
				});
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				context.invoke (() => {
					emit_action_progress (action, status, progress);
					return false;
				});
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				context.invoke (() => {
					emit_hook_progress (action, details, status, progress);
					return false;
				});
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				context.invoke (() => {
					emit_download_progress (action, status, progress);
					return false;
				});
			});
			alpm_utils.start_downloading.connect ((sender) => {
				context.invoke (() => {
					start_downloading ();
					return false;
				});
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				context.invoke (() => {
					stop_downloading ();
					return false;
				});
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				context.invoke (() => {
					emit_script_output (message);
					return false;
				});
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				context.invoke (() => {
					emit_warning (message);
					return false;
				});
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				context.invoke (() => {
					emit_error (message, details);
					return false;
				});
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				context.invoke (() => {
					important_details_outpout (must_show);
					return false;
				});
			});
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_upgrade = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			// building data
			tmp_path = "/tmp/pamac-%s".printf (Environment.get_user_name ());
			aurdb_path = "%s/aur".printf (tmp_path);
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			aur_pkgs_to_install = new GenericSet<string?> (str_hash, str_equal);
			to_build_queue = new Queue<string> ();
			build_cancellable = new Cancellable ();
			building = false;
			connecting_signals ();
		}

		~Transaction () {
			quit_daemon ();
		}

		public void quit_daemon () {
			try {
				transaction_interface.quit_daemon ();
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("quit_daemon: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
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

		protected virtual async bool ask_import_key (string pkgname, string key, string? owner) {
			// no import
			return false;
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
				while ((line = yield dis.read_line_async ()) != null) {
					if ("source = " in line) {
						string source = line.split (" = ", 2)[1];
						if (!("://" in source)) {
							string source_path = Path.build_filename (pkgdir_name, source);
							var source_file = File.new_for_path (source_path);
							if (source_file.query_exists ()) {
								files.add ((owned) source_path);
							}
						}
					} else if ("install = " in line) {
						string install = line.split (" = ", 2)[1];
						string install_path = Path.build_filename (pkgdir_name, install);
						var install_file = File.new_for_path (install_path);
						if (install_file.query_exists ()) {
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
				var details = new GenericArray<string> (1);
				details.add ("get_authorization: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
			return false;
		}

		public void remove_authorization () {
			try {
				transaction_interface.remove_authorization ();
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("remove_authorization: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
		}

		public async void generate_mirrors_list_async (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			transaction_interface.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			try {
				yield transaction_interface.generate_mirrors_list (country);
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("generate_mirrors_list: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
			transaction_interface.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			database.refresh ();
		}

		void on_generate_mirrors_list_data (string line) {
			emit_script_output (line);
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
				var error_details = new GenericArray<string> (1);
				error_details.add ("clean_cache: %s".printf (e.message));
				emit_error ("Daemon Error", error_details);
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
				var details = new GenericArray<string> (1);
				details.add ("clean_build_files: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
		}

		public async bool set_pkgreason_async (string pkgname, uint reason) {
			bool success = false;
			try {
				success = yield transaction_interface.set_pkgreason (pkgname, reason);
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("set_pkgreason: %s".printf (e.message));
				emit_error ("Daemon Error", details);
			}
			database.refresh ();
			return success;
		}

		public async bool download_updates_async () {
			bool success = false;
			try {
				success = yield transaction_interface.download_updates ();
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("download_updates: %s".printf (e.message));
				emit_error ("Daemon Error", details);
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

		async bool compute_aur_build_list_real () {
			yield launch_subprocess ({"mkdir", "-p", aurdb_path});
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			var to_build_array = new GenericArray<string> ();
			foreach (unowned string pkgname in to_build) {
				to_build_array.add (pkgname);
			}
			bool success = yield check_aur_dep_list (to_build_array);
			if (success && aur_desc_list.length > 0) {
				// create a fake aur db
				string tmp_aurdb_path = "%s/pamac_aur.db".printf (tmp_path);
				yield launch_subprocess ({"rm", "-f", tmp_aurdb_path});
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
					yield launch_subprocess ({"rm", "-rf", aurdb_path});
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
			HashTable<string, unowned AURPackage?> aur_pkgs = null;
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
					// parse all builddir to be sure to find it
					bool found = false;
					var builddir = File.new_for_path (real_aur_build_dir);
					try {
						FileEnumerator enumerator = builddir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
						FileInfo info;
						while ((info = enumerator.next_file (null)) != null) {
							// check if it's a directory containing a PKGBUILD file
							if (info.get_file_type () == FileType.DIRECTORY) {
								unowned string filename = info.get_name ();
								string absolute_child_path = Path.build_filename (real_aur_build_dir, filename);
								var child_file = File.new_for_path (absolute_child_path);
								FileEnumerator child_enumerator = child_file.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
								FileInfo child_info;
								while ((child_info = child_enumerator.next_file (null)) != null) {
									unowned string child_filename = child_info.get_name ();
									if (child_filename == "PKGBUILD") {
										// check pkgnames of srcinfo to targets
										bool success = database.regenerate_srcinfo (filename, null);
										if (success) {
											var srcinfo = child_file.get_child (".SRCINFO");
											// read .SRCINFO
											var dis = new DataInputStream (srcinfo.read ());
											string line;
											while ((line = dis.read_line ()) != null) {
												if ("pkgname = " in line) {
													string srcinfo_pkgname = line.split (" = ", 2)[1];
													if (srcinfo_pkgname == pkgname) {
														// found, set the right clone_dir
														clone_dir = child_file;
														found = true;
														break;
													}
												}
											}
											if (found) {
												break;
											}
										}
									}
								}
								if (found) {
									break;
								}
							}
						}
					} catch (Error e) {
						var details = new GenericArray<string> (2);
						details.add (e.message);
						details.add (dgettext (null, "target not found: %s").printf (pkgname));
						emit_error (dgettext (null, "Failed to prepare transaction"), details);
						return false;
					}
					if (!found) {
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
						var global_checkdepends = new GenericArray<string> ();
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
							// makedepends and checkdepends will be added in depends
							} else if ("depends" in line) {
								if ("depends = " in line || "depends_%s = ".printf (arch) in line) {
									string depend = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase){
										if ("checkdepends" in line) {
											global_checkdepends.add ((owned) depend);
										} else if ("makedepends" in line) {
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
							// add checkdepends and makedepends in depends
							foreach (unowned string global_checkdepend in global_checkdepends) {
								aur_pkg_found.depends.add (global_checkdepend);
							}
							foreach (unowned string global_makedepend in global_makedepends) {
								aur_pkg_found.depends.add (global_makedepend);
							}
							// check deps
							foreach (unowned string dep_string in aur_pkg_found.depends) {
								if (!database.has_installed_satisfier (dep_string) &&
									!database.has_sync_satisfier (dep_string)) {
									string dep_name = database.get_alpm_dep_name (dep_string);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add (dep_name);
										if (pkgname in clone_deps_files) {
											clone_files.add (dep_name);
											clone_deps_files.add (dep_name);
										}
									}
								}
							}
							// write desc file
							string pkgdir = "%s-%s".printf (pkgname_found, aur_pkg_found.version);
							string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
							aur_desc_list.add (pkgdir);
							var file = GLib.File.new_for_path (pkgdir_path);
							if (!file.query_exists ()) {
								yield file.make_directory_async ();
							}
							file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
							FileOutputStream fos;
							// always recreate desc in case of .SRCINFO modifications
							if (file.query_exists ()) {
								fos = yield file.replace_async (null, false, FileCreateFlags.NONE);
							} else {
								fos = yield file.create_async (FileCreateFlags.NONE);
							}
							// creating a DataOutputStream to the file
							var dos = new DataOutputStream (fos);
							// fake filename
							dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar\n\n".printf (pkgname_found, aur_pkg_found.version));
							// name
							dos.put_string ("%NAME%\n%s\n\n".printf (pkgname_found));
							// version
							dos.put_string ("%VERSION%\n%s\n\n".printf (aur_pkg_found.version));
							// base (double %% before BASE to escape %B)
							dos.put_string ("%%BASE%\n%s\n\n".printf (aur_pkg_found.packagebase));
							// desc
							dos.put_string ("%DESC%\n%s\n\n".printf (aur_pkg_found.desc));
							// arch (double %% before ARCH to escape %A)
							dos.put_string ("%%ARCH%\n%s\n\n".printf (arch));
							// depends
							if (aur_pkg_found.depends.length != 0) {
								dos.put_string ("%DEPENDS%\n");
								foreach (unowned string name in aur_pkg_found.depends) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// conflicts
							if (aur_pkg_found.conflicts.length != 0) {
								dos.put_string ("%CONFLICTS%\n");
								foreach (unowned string name in aur_pkg_found.conflicts) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// provides
							if (aur_pkg_found.provides.length != 0) {
								dos.put_string ("%PROVIDES%\n");
								foreach (unowned string name in aur_pkg_found.provides) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// replaces
							if (aur_pkg_found.replaces.length != 0) {
								dos.put_string ("%REPLACES%\n");
								foreach (unowned string name in aur_pkg_found.replaces) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
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
					// write desc file
					try {
						string pkgdir = "%s-%s".printf (aur_pkg.name, aur_pkg.version);
						string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
						aur_desc_list.add (pkgdir);
						var file = GLib.File.new_for_path (pkgdir_path);
						if (!file.query_exists ()) {
							yield file.make_directory_async ();
						}
						file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
						FileOutputStream fos;
						// always recreate desc in case of .SRCINFO modifications
						if (file.query_exists ()) {
							fos = yield file.replace_async (null, false, FileCreateFlags.NONE);
						} else {
							fos = yield file.create_async (FileCreateFlags.NONE);
						}
						// creating a DataOutputStream to the file
						var dos = new DataOutputStream (fos);
						// fake filename
						dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar\n\n".printf (aur_pkg.name, aur_pkg.version));
						// name
						dos.put_string ("%NAME%\n%s\n\n".printf (aur_pkg.name));
						// version
						dos.put_string ("%VERSION%\n%s\n\n".printf (aur_pkg.version));
						// base (double %% before BASE to escape %B)
						dos.put_string ("%%BASE%\n%s\n\n".printf (aur_pkg.packagebase));
						// desc
						dos.put_string ("%DESC%\n%s\n\n".printf (aur_pkg.desc));
						// arch (double %% before ARCH to escape %A)
						dos.put_string ("%%ARCH%\n%s\n\n".printf (arch));
						// depends
						bool depends_created = false;
						if (aur_pkg.depends.length != 0) {
							dos.put_string ("%DEPENDS%\n");
							depends_created = true;
							foreach (unowned string name in aur_pkg.depends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add (dep_name);
										if (pkgname in clone_deps_files) {
											clone_files.add (dep_name);
											clone_deps_files.add (dep_name);
										}
									}
								}
							}
						}
						// add checkdepends and makedepends in depends
						if (aur_pkg.checkdepends.length != 0) {
							if (!depends_created) {
								dos.put_string ("%DEPENDS%\n");
								depends_created = true;
							}
							foreach (unowned string name in aur_pkg.checkdepends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add (dep_name);
										if (pkgname in clone_deps_files) {
											clone_files.add (dep_name);
											clone_deps_files.add (dep_name);
										}
									}
								}
							}
						}
						if (aur_pkg.makedepends.length != 0) {
							if (!depends_created) {
								dos.put_string ("%DEPENDS%\n");
								depends_created = true;
							}
							foreach (unowned string name in aur_pkg.makedepends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add (dep_name);
										if (pkgname in clone_deps_files) {
											clone_files.add (dep_name);
											clone_deps_files.add (dep_name);
										}
									}
								}
							}
						}
						// add after %DEPENDS new line
						if (depends_created) {
							dos.put_string ("\n");
						}
						// conflicts
						if (aur_pkg.conflicts.length != 0) {
							dos.put_string ("%CONFLICTS%\n");
							foreach (unowned string name in aur_pkg.conflicts) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// provides
						if (aur_pkg.provides.length != 0) {
							dos.put_string ("%PROVIDES%\n");
							foreach (unowned string name in aur_pkg.provides) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// replaces
						if (aur_pkg.replaces.length != 0) {
							dos.put_string ("%REPLACES%\n");
							foreach (unowned string name in aur_pkg.replaces) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
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

		async void check_signatures (string pkgdir, string pkgname) {
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
						yield check_signature (pkgname, global_validpgpkeys);
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		async void check_signature (string pkgname, GenericArray<string> keys) {
			foreach (unowned string key in keys) {
				var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
				try {
					var process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--list-keys", key});
					yield process.wait_async ();
					if (process.get_if_exited ()) {
						if (process.get_exit_status () != 0) {
							// key is not imported in keyring
							// try to get key infos
							bool success = false;
							launcher.set_flags (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
							process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--search-keys", key});
							yield process.wait_async ();
							if (process.get_if_exited ()) {
								if (process.get_exit_status () == 0) {
									var dis = new DataInputStream (process.get_stdout_pipe ());
									string? owner = null;
									// check if an owner is set
									string? line;
									while ((line = yield dis.read_line_async ()) != null) {
										// get first uid line
										if ("uid:" in line) {
											owner = line.split (":", 3)[1];
											break;
										}
									}
									if (yield ask_import_key (pkgname, key, owner)) {
										var cmdline = new GenericArray<string> (5);
										cmdline.add ("gpg");
										cmdline.add ("--with-colons");
										cmdline.add ("--batch");
										cmdline.add ("--recv-keys");
										cmdline.add (key);
										int status = yield run_cmd_line_async (cmdline, null, build_cancellable);
										emit_script_output ("");
										if (status == 0) {
											success = true;
										}
									}
								}
							}
							if (!success) {
								emit_error (dgettext (null, "key %s could not be imported").printf (key), new GenericArray<string> ());
							}
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public async bool run_async () {
			if (transaction_interface == null) {
				var details = new GenericArray<string> (1);
				details.add ("failed to connect to dbus daemon");
				emit_error ("Daemon Error", details);
				return false;
			}
			bool success = true;
			if (sysupgrading ||
				to_install.length > 0 ||
				to_remove.length > 0 ||
				to_load_local.length > 0 ||
				to_load_remote.length > 0 ||
				to_build.length > 0) {
				success = yield run_alpm_transaction ();
				if (!dry_run && success) {
					if (to_build_queue.get_length () != 0) {
						success = yield build_aur_packages ();
						build_cancellable.reset ();
					}
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
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
				} else {
					to_build_queue.clear ();
					snap_to_install.remove_all ();
					snap_to_remove.remove_all ();
					flatpak_to_install.remove_all ();
					flatpak_to_remove.remove_all ();
					flatpak_to_upgrade.remove_all ();
				}
				sysupgrading = false;
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
					// ask classic snaps
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					var not_install = new GenericArray<unowned string> ();
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
					stop_preparing ();
				}
				// ask confirmation
				var summary = new TransactionSummary ();
				if (snap_to_install.length > 0 ||
					snap_to_remove.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					SnapPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install.add (pkg);
					}
					iter = HashTableIter<string, SnapPackage> (snap_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove.add (pkg);
					}
					stop_preparing ();
				}
				if (flatpak_to_install.length > 0 ||
					flatpak_to_remove.length > 0 ||
					flatpak_to_upgrade.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
					FlatpakPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install.add (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove.add (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
					while (iter.next (null, out pkg)) {
						summary.to_upgrade.add (pkg);
					}
					stop_preparing ();
				}
				if (summary.to_install.length == 0 &&
					summary.to_remove.length == 0 &&
					summary.to_upgrade.length == 0) {
					emit_action (dgettext (null, "Nothing to do") + ".");
					return false;
				} else {
					success = yield ask_commit (summary);
					if (!success) {
						stop_preparing ();
						emit_action (dgettext (null, "Transaction cancelled") + ".");
					}
					if (dry_run) {
						return true;
					}
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
					if (success) {
						emit_action (dgettext (null, "Transaction successfully finished") + ".");
					}
					database.refresh ();
					if (!success) {
						snap_to_install.remove_all ();
						snap_to_remove.remove_all ();
						flatpak_to_install.remove_all ();
						flatpak_to_remove.remove_all ();
						flatpak_to_upgrade.remove_all ();
					}
				}
			}
			return success;
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
							unowned AlpmPackage? pkg = database.get_installed_pkg (name);
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
			bool success = false;
			if (!dry_run && !no_refresh && (sysupgrading || auto_sysupgrading)) {
				success = yield get_authorization_async ();
				if (!success) {
					return false;
				}
				bool enable_aur_copy = config.enable_aur;
				// don't refresh AUR db if sysupgrading is not explicitly requested
				if (auto_sysupgrading) {
					config.enable_aur = false;
				}
				success = yield refresh_dbs_async ();
				config.enable_aur = enable_aur_copy;
				if (!success) {
					return false;
				}
			}
			if (to_install.length > 0) {
				yield add_optdeps ();
			}
			if (sysupgrading) {
				if (config.check_aur_updates) {
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
					var details = new GenericArray<string> (1);
					details.add ("download_pkgs: %s".printf (e.message));
					emit_error ("Daemon Error", details);
					success = false;
				}
				if (!success) {
					return false;
				}
			}
			var new_summary = new TransactionSummary ();
			try {
				new Thread<int>.try ("trans_check_prepare", () => {
					success = alpm_utils.trans_check_prepare (sysupgrading,
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
															ref new_summary);
					context.invoke (trans_check_prepare.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			summary = new_summary;
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
			bool success = false;
			try {
				success = yield transaction_interface.trans_refresh (force_refresh);
				if (config.enable_aur) {
					bool aur_success = yield transaction_interface.trans_refresh_aur (force_refresh);
					if (!aur_success) {
						emit_warning (dgettext (null, "Failed to synchronize AUR database"));
					}
				}
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("trans_refresh: %s".printf (e.message));
				emit_error ("Daemon Error", details);
				success = false;
			}
			return success;
		}

		public async bool refresh_files_dbs_async () {
			bool success = false;
			try {
				success = yield transaction_interface.trans_refresh_files (force_refresh);
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("trans_refresh_files: %s".printf (e.message));
				emit_error ("Daemon Error", details);
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
							bool found = alpm_utils.unresolvables.find_with_equal_func (name, str_equal, null);
							if (!found) {
								alpm_utils.unresolvables.add (name);
							}
						}
						foreach (unowned string pkgname in alpm_utils.unresolvables) {
							unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
							string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
							success = yield clone_build_files_if_needed (pkgdir, pkgname);
							if (!success) {
								var details = new GenericArray<string> (1);
								details.add (dgettext (null, "Failed to clone %s build files").printf (pkgname));
								emit_error (dgettext (null, "Failed to prepare transaction"), details);
								alpm_utils.unresolvables = new GenericArray<string> ();
								return false;
							}
						}
						yield edit_build_files (alpm_utils.unresolvables);
						alpm_utils.unresolvables = new GenericArray<string> ();
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
					yield launch_subprocess ({"rm", "-f", "%s/pamac_aur.db".printf (tmp_path)});
				}
				if (dry_run) {
					return true;
				}
				if (success) {
					// clone build files and check signatures
					if (summary.aur_pkgbases_to_build.length != 0) {
						unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
						foreach (unowned string pkgname in summary.aur_pkgbases_to_build) {
							string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
							success = yield clone_build_files_if_needed (pkgdir, pkgname);
							if (success) {
								yield check_signatures (pkgdir, pkgname);
							} else {
								var details = new GenericArray<string> (1);
								details.add (dgettext (null, "Failed to clone %s build files").printf (pkgname));
								emit_error (dgettext (null, "Failed to prepare transaction"), details);
								return false;
							}
						}
					}
					var to_install_array = new GenericArray<string> (to_install.length);
					var to_remove_array = new GenericArray<string> (to_remove.length);
					var to_load_local_array = new GenericArray<string> (to_load_local.length);
					var to_load_remote_array = new GenericArray<string> (to_load_remote.length);
					var to_install_as_dep_array = new GenericArray<string> (to_install_as_dep.length);
					var ignorepkgs_array = new GenericArray<string> (ignorepkgs.length);
					var overwrite_files_array = new GenericArray<string> (overwrite_files.length);
					foreach (unowned string name in to_install) {
						to_install_array.add (name);
					}
					foreach (unowned string name in to_remove) {
						to_remove_array.add (name);
					}
					foreach (unowned string name in to_load_local) {
						to_load_local_array.add (name);
					}
					foreach (unowned string name in to_load_remote) {
						to_load_remote_array.add (name);
					}
					foreach (unowned string name in to_install_as_dep) {
						to_install_as_dep_array.add (name);
					}
					foreach (unowned string name in ignorepkgs) {
						ignorepkgs_array.add (name);
					}
					foreach (unowned string name in overwrite_files) {
						overwrite_files_array.add (name);
					}
					success = yield get_authorization_async ();
					if (!success) {
						return false;
					}
					try {
						success = yield transaction_interface.trans_run (sysupgrading,
																	config.enable_downgrade,
																	config.simple_install,
																	config.keep_built_pkgs,
																	trans_flags,
																	to_install_array,
																	to_remove_array,
																	to_load_local_array,
																	to_load_remote_array,
																	to_install_as_dep_array,
																	ignorepkgs_array,
																	overwrite_files_array);
					} catch (Error e) {
						var details = new GenericArray<string> (1);
						details.add ("trans_run: %s".printf (e.message));
						emit_error ("Daemon Error", details);
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
					yield launch_subprocess ({"rm", "-f", "%s/pamac_aur.db".printf (tmp_path)});
				}
				if (dry_run) {
					return true;
				}
				if (success) {
					// clone build files and check signatures
					unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
					foreach (unowned string pkgname in summary.aur_pkgbases_to_build) {
						string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
						success = yield clone_build_files_if_needed (pkgdir, pkgname);
						if (success) {
							yield check_signatures (pkgdir, pkgname);
						} else {
							var details = new GenericArray<string> (1);
							details.add (dgettext (null, "Failed to clone %s build files").printf (pkgname));
							emit_error (dgettext (null, "Failed to prepare transaction"), details);
							return false;
						}
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
			try {
				// emit download signal to allow cancellation
				start_downloading ();
				bool success = yield transaction_interface.snap_trans_run (snap_to_install_array, snap_to_remove_array);
				stop_downloading ();
				return success;
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("snap_trans_run: %s".printf (e.message));
				emit_error ("Daemon Error", details);
				return false;
			}
		}

		public async bool snap_switch_channel_async (string snap_name, string channel) {
			if (config.enable_snap) {
				try {
					return yield transaction_interface.snap_switch_channel (snap_name, channel);
				} catch (Error e) {
					var details = new GenericArray<string> (1);
					details.add ("snap_switch_channel: %s".printf (e.message));
					emit_error ("Daemon Error", details);
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
			try {
				// emit download signal to allow cancellation
				start_downloading ();
				bool success = yield transaction_interface.flatpak_trans_run (flatpak_to_install_array,
																flatpak_to_remove_array,
																flatpak_to_upgrade_array);
				stop_downloading ();
				return success;
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("flatpak_trans_run: %s".printf (e.message));
				emit_error ("Daemon Error", details);
				return false;
			}
		}

		string remove_bash_colors (string msg) {
			Regex regex = /\x1B\[[0-9;]*[JKmsu]/;
			try {
				return regex.replace (msg, -1, 0, "");
			} catch (Error e) {
				return msg;
			}
		}

		public async virtual int run_cmd_line_async (GenericArray<string> args, string? working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			try {
				// spawnv needs a null terminated array
				GenericArray<string> args_copy = args.copy (strdup);
				args_copy.length = args_copy.length + 1;
				Subprocess process = launcher.spawnv (args_copy.data);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					if (cancellable.is_cancelled ()) {
						break;
					}
					emit_script_output (remove_bash_colors (line));
				}
				if (cancellable.is_cancelled ()) {
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
				try {
					yield process.wait_async (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				warning (e.message);
			}
			return status;
		}

		async bool build_aur_packages () {
			bool success = true;
			// get a fake aur db to check deps
			unowned Alpm.DB? aur_db = null;
			var tmp_handle = database.get_tmp_handle ();
			if (tmp_handle != null) {
				try {
					var process = new Subprocess.newv ({"cp", "%s/pamac_aur.db".printf (tmp_path), "%ssync".printf (tmp_handle.dbpath)}, SubprocessFlags.NONE);
					yield process.wait_async ();
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
			while (to_build_queue.length > 0) {
				string pkgname = to_build_queue.pop_head ();
				build_cancellable.reset ();
				var built_pkgs_path = new GenericArray<string> ();
				unowned string real_aur_build_dir = database.get_real_aur_build_dir ();
				string pkgdir = Path.build_filename (real_aur_build_dir, pkgname);
				bool as_root = Posix.geteuid () == 0;
				// building
				building = true;
				start_building ();
				var cmdline = new GenericArray<string> ();
				if (as_root) {
					cmdline.add ("systemd-run");
					cmdline.add ("--service-type=oneshot");
					cmdline.add ("--pipe");
					cmdline.add ("--wait");
					cmdline.add ("--pty");
					cmdline.add ("--property=DynamicUser=yes");
					cmdline.add ("--property=CacheDirectory=pamac");
					cmdline.add ("--property=WorkingDirectory=/var/cache/pamac/%s".printf (pkgname));
				}
				cmdline.add ("makepkg");
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
				int status = yield run_cmd_line_async (cmdline, pkgdir, build_cancellable);
				if (build_cancellable.is_cancelled ()) {
					status = 1;
				} else if (status == 1) {
					emit_error (dgettext (null, "Failed to build %s").printf (pkgname), new GenericArray<string> ());
				}
				if (status == 0) {
					// get built pkgs path
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
					launcher.set_cwd (pkgdir);
					try {
						cmdline = new GenericArray<string> ();
						if (as_root) {
							cmdline.add ("systemd-run");
							cmdline.add ("--service-type=oneshot");
							cmdline.add ("--pipe");
							cmdline.add ("--wait");
							cmdline.add ("--pty");
							cmdline.add ("--property=DynamicUser=yes");
							cmdline.add ("--property=CacheDirectory=pamac");
							cmdline.add ("--property=WorkingDirectory=/var/cache/pamac/%s".printf (pkgname));
						}
						cmdline.add ("makepkg");
						cmdline.add ("--packagelist");
						if (!config.keep_built_pkgs) {
							cmdline.add ("PKGDEST=%s".printf (pkgdir));
							cmdline.add ("PKGEXT=.pkg.tar");
						}
						// spawnv needs a null terminated array
						cmdline.length = cmdline.length + 1;
						Subprocess process = launcher.spawnv (cmdline.data);
						yield process.wait_async ();
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
						if (status == 0) {
							var dis = new DataInputStream (process.get_stdout_pipe ());
							string? line = null;
							while ((line = yield dis.read_line_async ()) != null) {
								var file = GLib.File.new_for_path (line);
								string filename = file.get_basename ();
								string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
								if (name_version_release == null) {
									break;
								}
								string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
								if (name_version == null) {
									break;
								}
								string? name = name_version.slice (0, name_version.last_index_of_char ('-'));
								if (name == null) {
									break;
								}
								if (name in aur_pkgs_to_install) {
									built_pkgs_path.add (line);
									built_pkgs.insert (name, line);
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
			try {
				new Subprocess.newv ({"rm", "-f", "%s/pamac_aur.db".printf (tmp_path), "%ssync/pamac_aur.db".printf (tmp_handle.dbpath)}, SubprocessFlags.NONE);
			} catch (Error e) {
				warning (e.message);
			}
			return success;
		}

		async bool install_built_pkgs (GenericArray<string> to_load_array, GenericArray<string> to_install_as_dep_array) {
			bool success = false;
			try {
				emit_script_output ("");
				success = yield transaction_interface.trans_run (false, // sysupgrading,
															false, // enable_downgrade
															false, // simple_install
															config.keep_built_pkgs,
															0, // trans_flags,
															new GenericArray<string> (), // to_install
															new GenericArray<string> (), // to_remove
															to_load_array,
															new GenericArray<string> (), // to_load_remote
															to_install_as_dep_array,
															new GenericArray<string> (), // ignorepkgs
															new GenericArray<string> ()); // overwrite_files
			} catch (Error e) {
				var details = new GenericArray<string> (1);
				details.add ("trans_run: %s".printf (e.message));
				emit_error ("Daemon Error", details);
				success = false;
			}
			return success;
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else if (waiting) {
				waiting = false;
			} else {
				try {
					transaction_interface.trans_cancel ();
				} catch (Error e) {
					var details = new GenericArray<string> (1);
					details.add ("trans_cancel: %s".printf (e.message));
					emit_error ("Daemon Error", details);
				}
			}
		}

		int choose_provider_real (string depend, GenericArray<string> providers) {
			int index = 0;
			var loop = new MainLoop (context);
			context.invoke (() => {
				choose_provider.begin (depend, providers, (obj, res) => {
					index = choose_provider.end (res);
					loop.quit ();
				});
				return false;
			});
			loop.run ();
			return index;
		}

		async bool ask_commit_real (TransactionSummary summary) {
			if (build_cancellable.is_cancelled ()) {
				return false;
			} else {
				if (snap_to_install.length > 0) {
					// ask classic snaps
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					var not_install = new GenericArray<unowned string> ();
					unowned string snap_name;
					SnapPackage pkg;
					while (iter.next (out snap_name, out pkg)) {
						if (pkg.confined != dgettext (null, "Yes")) {
							bool answser = yield ask_snap_install_classic (pkg.app_name);
							if (!answser) {
								not_install.add (snap_name);
							}
						}
					}
					foreach (unowned string name in not_install) {
						snap_to_install.remove (name);
					}
				}
				// add snaps to summary
				var snap_iter = HashTableIter<string, SnapPackage> (snap_to_install);
				SnapPackage snap_pkg;
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_install.add (snap_pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage> (snap_to_remove);
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_remove.add (snap_pkg);
				}
				// add flatpaks to summary
				var flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
				FlatpakPackage flatpak_pkg;
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_install.add (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_remove.add (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_upgrade.add (flatpak_pkg);
				}
				return yield ask_commit (summary);
			}
		}

		async bool ask_edit_build_files_real (TransactionSummary summary) {
			if (dry_run) {
				return false;
			}
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			SnapPackage pkg;
			while (iter.next (null, out pkg)) {
				summary.to_install.add (pkg);
			}
			iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (iter.next (null, out pkg)) {
				summary.to_remove.add (pkg);
			}
			return yield ask_edit_build_files (summary);
		}

		void on_emit_action (string action) {
			emit_action (action);
		}

		void on_emit_action_progress (string action, string status, double progress) {
			emit_action_progress (action, status, progress);
		}

		void on_emit_download_progress (string action, string status, double progress) {
			emit_download_progress (action, status, progress);
		}

		void on_emit_hook_progress (string action, string details, string status, double progress) {
			emit_hook_progress (action, details, status, progress);
		}

		void on_emit_script_output (string message) {
			emit_script_output (message);
		}

		void on_emit_warning (string message) {
			emit_warning (message);
		}

		void on_emit_error (string message, GenericArray<string> details) {
			emit_error (message, details);
		}

		void on_important_details_outpout (bool must_show) {
			important_details_outpout (must_show);
		}

		void on_start_downloading () {
			start_downloading ();
		}

		void on_stop_downloading () {
			stop_downloading ();
		}

		void on_start_waiting () {
			start_waiting ();
		}

		void on_stop_waiting () {
			stop_waiting ();
		}

		void connecting_signals () {
			transaction_interface.emit_action.connect (on_emit_action);
			transaction_interface.emit_action_progress.connect (on_emit_action_progress);
			transaction_interface.emit_download_progress.connect (on_emit_download_progress);
			transaction_interface.emit_hook_progress.connect (on_emit_hook_progress);
			transaction_interface.emit_script_output.connect (on_emit_script_output);
			transaction_interface.emit_warning.connect (on_emit_warning);
			transaction_interface.emit_error.connect (on_emit_error);
			transaction_interface.important_details_outpout.connect (on_important_details_outpout);
			transaction_interface.start_downloading.connect (on_start_downloading);
			transaction_interface.stop_downloading.connect (on_stop_downloading);
			transaction_interface.start_waiting.connect (on_start_waiting);
			transaction_interface.stop_waiting.connect (on_stop_waiting);
		}
	}
}
