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
	public class Database : Object {
		AlpmConfig alpm_config;
		// protects alpm_config, the handles and the caches,
		// shared with the packages which use the handles
		AlpmLock alpm_lock;
		// the current handle, packages created from it keep a reference
		AlpmHandleRef? handle_ref;
		unowned Alpm.Handle? alpm_handle;
		Alpm.Handle? files_handle;
		HashTable<string, AURPackageLinked> aur_vcs_pkgs;
		HashTable<unowned string, AlpmPackageLinked> pkgs_cache;
		HashTable<unowned string, AURPackageLinked> aur_pkgs_cache;
		GenericArray<string> mirrors_countries;
		GenericArray<string> groups_names;
		GenericArray<string> repos_names;
		GenericArray<string> categories_names;
		AURPlugin aur_plugin;
		AppstreamPlugin appstream_plugin;
		SnapPlugin snap_plugin;
		FlatpakPlugin flatpak_plugin;
		Soup.Session soup_session;

		public Config config { get; construct set; }
		internal unowned MainContext context { get; private set; }
		internal bool dbs_missing { get; private set; }

		public signal void get_updates_progress (uint percent);
		public signal void emit_warning (string message);

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			alpm_lock = new AlpmLock ();
			alpm_config = config.alpm_config;
			context = MainContext.default ();
			aur_vcs_pkgs = new HashTable<string, AURPackageLinked> (str_hash, str_equal);
			pkgs_cache = new HashTable<unowned string, AlpmPackageLinked> (str_hash, str_equal);
			aur_pkgs_cache = new HashTable<unowned string, AURPackageLinked> (str_hash, str_equal);
			// get_user_agent defined in utils.vala
			string user_agent = get_user_agent ();
			soup_session = new Soup.Session ();
			soup_session.user_agent = user_agent;
			soup_session.timeout = 10;
			// set HTTP_USER_AGENT needed when downloading using libalpm like refreshing dbs
			Environment.set_variable ("HTTP_USER_AGENT", user_agent, true);
			// init dbs
			alpm_lock.acquire ();
			try {
				Alpm.Handle? new_handle = alpm_config.get_handle ();
				// plugins are loaded anyway, so their config is consistent
				if (new_handle != null) {
					handle_ref = new AlpmHandleRef ((owned) new_handle, alpm_lock);
					alpm_handle = handle_ref.handle;
					// add ignorepkgs
					foreach (unowned string name in config.ignorepkgs) {
						alpm_handle.add_ignorepkg (name);
					}
					// register syncdbs with a callback if database file is missing
					alpm_handle.set_eventcb (cb_evt, this);
					alpm_config.register_syncdbs (alpm_handle);
					// files handle
					files_handle = alpm_config.get_handle (true);
					alpm_config.register_syncdbs (files_handle);
				}
				aur_vcs_pkgs.remove_all ();
				pkgs_cache.remove_all ();
				aur_pkgs_cache.remove_all ();
			} finally {
				alpm_lock.release ();
			}
			// load aur plugin
			if (config.support_aur) {
				aur_plugin = config.get_aur_plugin ();
				if (aur_plugin == null) {
					config.enable_aur = false;
				} else {
					aur_plugin.set_real_build_dir (config.aur_build_dir);
					config.notify["aur-build-dir"].connect (() => {
						aur_plugin.set_real_build_dir (config.aur_build_dir);
					});
				}
			}
			// load appstream plugin
			if (config.support_appstream) {
				appstream_plugin = config.get_appstream_plugin ();
				if (appstream_plugin == null) {
					config.enable_appstream = false;
				} else {
					if (config.enable_appstream) {
						appstream_plugin.load (get_repos_names ());
					}
				}
			}
			// load snap plugin
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
				if (snap_plugin == null) {
					config.enable_snap = false;
				}
			}
			// load flatpak plugin
			if (config.support_flatpak) {
				flatpak_plugin = config.get_flatpak_plugin ();
				if (flatpak_plugin == null) {
					config.enable_flatpak = false;
				} else {
					flatpak_plugin.refresh_period = config.refresh_period;
					if (config.enable_flatpak) {
						flatpak_plugin.load_appstream_data ();
					}
				}
			}
		}

		internal void refresh () {
			alpm_lock.acquire ();
			try {
				alpm_config.reload ();
				Alpm.Handle? new_handle = alpm_config.get_handle ();
				if (new_handle == null) {
					// keep the current handle
					return;
				} else {
					// the previous handle is released with the last package created from it
					handle_ref = new AlpmHandleRef ((owned) new_handle, alpm_lock);
					alpm_handle = handle_ref.handle;
					// add ignorepkgs
					foreach (unowned string name in config.ignorepkgs) {
						alpm_handle.add_ignorepkg (name);
					}
					// dbs may have been synchronized since: check again if one is missing
					dbs_missing = false;
					alpm_handle.set_eventcb (cb_evt, this);
					alpm_config.register_syncdbs (alpm_handle);
					// files handle
					files_handle = alpm_config.get_handle (true);
					alpm_config.register_syncdbs (files_handle);
				}
				aur_vcs_pkgs.remove_all ();
				pkgs_cache.remove_all ();
				aur_pkgs_cache.remove_all ();
				// repos or groups may have changed
				repos_names = null;
				groups_names = null;
			} finally {
				alpm_lock.release ();
			}
			if (config.enable_snap) {
				snap_plugin.refresh ();
			}
			if (config.enable_flatpak) {
				flatpak_plugin.refresh ();
			}
		}

		internal Alpm.Handle? get_tmp_handle () {
			alpm_lock.acquire ();
			try {
				var tmp_handle = alpm_config.get_handle (false, true);
				if (tmp_handle != null) {
					alpm_config.register_syncdbs (tmp_handle);
				}
				return tmp_handle;
			} finally {
				alpm_lock.release ();
			}
		}

		// empty if pacman-mirrors is not available
		public async unowned GenericArray<string> get_mirrors_countries_async () {
			if (mirrors_countries != null) {
				return mirrors_countries;
			}
			try {
				new Thread<int>.try ("get_mirrors_countries", () => {
					var countries = new GenericArray<string> ();
					try {
						string countries_str;
						int status;
						Process.spawn_command_line_sync ("pacman-mirrors -l",
													out countries_str,
													null,
													out status);
						if (status == 0) {
							foreach (unowned string country in countries_str.split ("\n")) {
								if (country != "") {
									countries.add (country);
								}
							}
						}
					} catch (SpawnError e) {
						warning (e.message);
					}
					// also kept on failure to not run the command again
					mirrors_countries = countries;
					context.invoke (get_mirrors_countries_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			if (mirrors_countries == null) {
				mirrors_countries = new GenericArray<string> ();
			}
			return mirrors_countries;
		}

		// a copy: concurrent calls do not share the result
		public async string get_mirrors_choosen_country_async () {
			string mirrors_choosen_country = "";
			try {
				new Thread<int>.try ("get_mirrors_choosen_country", () => {
					try {
						string countries_str;
						int status;
						Process.spawn_command_line_sync ("pacman-mirrors -lc",
													out countries_str,
													null,
													out status);
						if (status == 0) {
							// only take first country
							mirrors_choosen_country = countries_str.split ("\n", 2)[0];
						}
					} catch (SpawnError e) {
						warning (e.message);
					}
					context.invoke (get_mirrors_choosen_country_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return mirrors_choosen_country;
		}

		public string get_alpm_dep_name (string dep_string) {
			return Alpm.Depend.from_string (dep_string).name;
		}

		public CompareFunc<string> vercmp = Alpm.pkg_vercmp;

		// split a package file name like name-version-release-arch.pkg.tar.zst(.sig),
		// false if it is not a package file
		static bool split_cache_filename (string filename, out string name, out string name_version_release, out string version_release) {
			name = "";
			name_version_release = "";
			version_release = "";
			if (!(".pkg.tar" in filename)) {
				return false;
			}
			int arch_index = filename.last_index_of_char ('-');
			if (arch_index <= 0) {
				return false;
			}
			name_version_release = filename.substring (0, arch_index);
			int release_index = name_version_release.last_index_of_char ('-');
			if (release_index <= 0) {
				return false;
			}
			int version_index = name_version_release.substring (0, release_index).last_index_of_char ('-');
			if (version_index <= 0) {
				return false;
			}
			name = name_version_release.substring (0, version_index);
			version_release = name_version_release.substring (version_index + 1);
			return true;
		}

		void get_clean_cache_details_real (ref HashTable<string, uint64?> filenames_size) {
			var pkg_version_filenames = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			var pkg_versions = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			alpm_lock.acquire ();
			try {
				unowned Alpm.List<unowned string> cachedirs_names = alpm_handle.cachedirs;
				while (cachedirs_names != null) {
					unowned string cachedir_name = cachedirs_names.data;
					var cachedir = File.new_for_path (cachedir_name);
					try {
						FileEnumerator enumerator = cachedir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
						FileInfo info;
						while ((info = enumerator.next_file (null)) != null) {
							if (info.get_file_type () != FileType.REGULAR) {
								continue;
							}
							unowned string filename = info.get_name ();
							string name;
							string name_version_release;
							string version_release;
							// only packages and their signatures, like paccache
							if (!split_cache_filename (filename, out name, out name_version_release, out version_release)) {
								continue;
							}
							string absolute_filename = Path.build_filename (cachedir_name, filename);
							if (config.clean_rm_only_uninstalled && is_installed_pkg (name)) {
								continue;
							}
							filenames_size.insert (absolute_filename, info.get_size ());
							if (pkg_versions.contains (name)) {
								if (pkg_version_filenames.contains (name_version_release)) {
									// case of .sig file
									unowned GenericArray<string> filenames = pkg_version_filenames.lookup (name_version_release);
									filenames.add ((owned) absolute_filename);
								} else {
									unowned GenericArray<string> versions = pkg_versions.lookup (name);
									versions.add ((owned) version_release);
									var filenames = new GenericArray<string> ();
									filenames.add ((owned) absolute_filename);
									pkg_version_filenames.insert ((owned) name_version_release, (owned) filenames);
								}
							} else {
								var versions = new GenericArray<string> ();
								versions.add ((owned) version_release);
								pkg_versions.insert (name, (owned) versions);
								var filenames = new GenericArray<string> ();
								filenames.add ((owned) absolute_filename);
								pkg_version_filenames.insert ((owned) name_version_release, (owned) filenames);
							}
						}
					} catch (Error e) {
						warning (e.message);
					}
					cachedirs_names.next ();
				}
			} finally {
				alpm_lock.release ();
			}
			if (config.clean_keep_num_pkgs == 0) {
				return;
			}
			// filter candidates
			var iter = HashTableIter<string, GenericArray<string>> (pkg_versions);
			unowned string name;
			unowned GenericArray<string> versions;
			while (iter.next (out name, out versions)) {
				// sort versions
				if (versions.length > config.clean_keep_num_pkgs) {
					versions.sort ((version1, version2) => {
						// reverse version 1 and version2 to have higher versions first
						return Alpm.pkg_vercmp (version2, version1);
					});
				}
				uint i;
				uint length = versions.length;
				for (i = 0; i < length; i++) {
					if (i == config.clean_keep_num_pkgs) {
						break;
					}
					unowned GenericArray<string>? filenames = pkg_version_filenames.lookup ("%s-%s".printf (name, versions[i]));
					if (filenames != null) {
						foreach (unowned string filename in filenames) {
							filenames_size.remove (filename);
						}
					}
				}
			}
		}

		public HashTable<string, uint64?> get_clean_cache_details () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			get_clean_cache_details_real (ref filenames_size);
			return filenames_size;
		}

		public async HashTable<string, uint64?> get_clean_cache_details_async () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			try {
				new Thread<int>.try ("get_clean_cache_details", () => {
					get_clean_cache_details_real (ref filenames_size);
					context.invoke (get_clean_cache_details_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return filenames_size;
		}

		public unowned string get_real_aur_build_dir () {
			return aur_plugin.get_real_build_dir ();
		}

		internal GenericArray<AURInfos> get_aur_providers (string pkgname) {
			return aur_plugin.get_providers (pkgname);
		}

		void get_build_files_details_real (ref HashTable<string, uint64?> filenames_size) {
			unowned string real_aur_build_dir = get_real_aur_build_dir ();
			var build_directory = File.new_for_path (real_aur_build_dir);
			if (!build_directory.query_exists ()) {
				return;
			}
			try {
				FileEnumerator enumerator = build_directory.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					if (info.get_name () == "packages-meta-ext-v1.json.gz") {
						continue;
					}
					string absolute_filename = Path.build_filename (build_directory.get_path (), info.get_name ());
					var child = GLib.File.new_for_path (absolute_filename);
					uint64 disk_usage;
					child.measure_disk_usage (FileMeasureFlags.NONE, null, null, out disk_usage, null, null);
					filenames_size.insert (absolute_filename, disk_usage);
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public HashTable<string, uint64?> get_build_files_details () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			get_build_files_details_real (ref filenames_size);
			return filenames_size;
		}

		public async HashTable<string, uint64?> get_build_files_details_async () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			try {
				new Thread<int>.try ("get_build_files_details", () => {
					get_build_files_details_real (ref filenames_size);
					context.invoke (get_build_files_details_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return filenames_size;
		}

		public bool is_installed_pkg (string pkgname) {
			alpm_lock.acquire ();
			try {
				return alpm_handle.localdb.get_pkg (pkgname) != null;
			} finally {
				alpm_lock.release ();
			}
		}

		public AlpmPackage? get_installed_pkg (string pkgname) {
			alpm_lock.acquire ();
			try {
				return initialise_pkg (alpm_handle.localdb.get_pkg (pkgname), null);
			} finally {
				alpm_lock.release ();
			}
		}

		public bool has_installed_satisfier (string depstring) {
			alpm_lock.acquire ();
			try {
				return Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring) != null;
			} finally {
				alpm_lock.release ();
			}
		}

		public AlpmPackage? get_installed_satisfier (string depstring) {
			alpm_lock.acquire ();
			try {
				return initialise_pkg (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring), null);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_installed_pkgs_by_glob (string glob) {
			var pkgs = new GenericArray<AlpmPackage> ();
			alpm_lock.acquire ();
			try {
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package local_pkg = pkgcache.data;
					// only check by name
					if (Posix.fnmatch (glob, local_pkg.name) == 0) {
						pkgs.add (initialise_pkg (local_pkg, null));
					}
					pkgcache.next ();
				}
			} finally {
				alpm_lock.release ();
			}
			return pkgs;
		}

		// the repository is one of the distribution, see OfficialRepos in pamac.conf
		public bool is_official_repo (string repo) {
			return repo in config.official_repos;
		}

		public bool should_hold (string pkgname) {
			alpm_lock.acquire ();
			try {
				return pkgname in alpm_config.holdpkgs;
			} finally {
				alpm_lock.release ();
			}
		}

		internal async GenericArray<string> get_uninstalled_optdeps_async (string pkgname) {
			var optdeps = new GenericArray<string> ();
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("get_uninstalled_optdeps", () => {
					alpm_lock.acquire ();
					try {
						unowned Alpm.Package? pkg = get_syncpkg (alpm_handle, pkgname_copy);
						if (pkg != null) {
							unowned Alpm.List<unowned Alpm.Depend> optdepends = pkg.optdepends;
							while (optdepends != null) {
								string optdep = optdepends.data.compute_string ();
								unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep);
								if (satisfier == null) {
									optdeps.add ((owned) optdep);
								}
								optdepends.next ();
							}
						}
					} finally {
						alpm_lock.release ();
					}
					context.invoke (get_uninstalled_optdeps_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return optdeps;
		}

		AlpmPackageStatic initialise_pkg_data (Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// only use for updates so it is a sync_pkg
			var pkg = new AlpmPackageStatic (sync_pkg, local_pkg, sync_pkg);
			if (config.enable_appstream) {
				// find if pkgname provides only one app
				GenericArray<unowned App> matching_apps = appstream_plugin.get_pkgname_apps (sync_pkg.name);
				if (matching_apps.length == 1) {
					pkg.set_app (matching_apps[0]);
				}
			}
			return pkg;
		}

		AlpmPackage? initialise_pkg (Alpm.Package? alpm_pkg, Alpm.Package? sync_pkg) {
			if (alpm_pkg == null) {
				return null;
			}
			AlpmPackageLinked? pkg = null;
			// first search in cache only with pkgname
			unowned string pkgname = alpm_pkg.name;
			pkg = pkgs_cache.lookup (pkgname);
			if (pkg != null) {
				return pkg;
			}
			var new_pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, this, handle_ref);
			if (sync_pkg != null) {
				new_pkg.set_sync_pkg (sync_pkg);
			} else if (config.enable_aur && alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
				unowned Alpm.Package? found_sync_pkg = get_syncpkg (alpm_handle, pkgname);
				new_pkg.set_sync_pkg (found_sync_pkg);
				new_pkg.set_local_pkg (alpm_pkg);
				if (found_sync_pkg == null) {
					if (aur_plugin.get_infos (alpm_pkg.name) != null) {
						new_pkg.repo = dgettext (null, "AUR");
					}
				}
			}
			if (config.enable_appstream) {
				// find if pkgname provides only one app
				GenericArray<unowned App> matching_apps = appstream_plugin.get_pkgname_apps (pkgname);
				if (matching_apps.length == 1) {
					new_pkg.set_app (matching_apps[0]);
				}
			}
			if (pkgs_cache.contains (new_pkg.id)) {
				return pkgs_cache.lookup (new_pkg.id);
			}
			pkg = new_pkg;
			pkgs_cache.replace (new_pkg.id, new_pkg);
			return pkg;
		}

		void initialise_pkgs (Alpm.List<unowned Alpm.Package>? alpm_pkgs, ref GenericArray<AlpmPackage> pkgs) {
			var data = new HashTable<unowned string, AlpmPackageLinked> (str_hash, str_equal);
			var foreign_pkgnames = new GenericArray<string> ();
			while (alpm_pkgs != null) {
				unowned Alpm.Package alpm_pkg = alpm_pkgs.data;
				unowned string pkgname = alpm_pkg.name;
				// first search in cache only with pkgname
				AlpmPackageLinked? pkg = pkgs_cache.lookup (pkgname);
				if (pkg != null) {
					pkgs.add (pkg);
					alpm_pkgs.next ();
					continue;
				}
				pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, this, handle_ref);
				if (config.enable_aur && alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
					pkg.set_sync_pkg (sync_pkg);
					pkg.set_local_pkg (alpm_pkg);
					if (sync_pkg == null) {
						foreign_pkgnames.add (pkgname);
						data.insert (pkgname, pkg);
					}
				}
				if (config.enable_appstream) {
					GenericArray<unowned App> apps = appstream_plugin.get_pkgname_apps (pkgname);
					uint apps_length = apps.length;
					if (apps_length > 0) {
						// alpm_pkg provide some apps
						unowned App app = apps[0];
						pkg.set_app (app);
						// check if pkg with app exists in cache
						AlpmPackageLinked? cached_pkg = pkgs_cache.lookup (pkg.id);
						if (cached_pkg == null) {
							// add in cache
							pkgs_cache.replace (pkg.id, pkg);
						} else {
							// keep cached pkg
							pkg = cached_pkg;
						}
						for (uint i = 1; i < apps_length; i++) {
							app = apps[i];
							cached_pkg = pkgs_cache.lookup (app.id);
							if (cached_pkg == null) {
								var pkg_dup = new AlpmPackageLinked.from_alpm (alpm_pkg, this, handle_ref);
								pkg_dup.set_app (apps[i]);
								pkgs.add (pkg_dup);
								// add in cache
								pkgs_cache.replace (pkg_dup.id, pkg_dup);
							} else {
								// add cached pkg
								pkgs.add (cached_pkg);
							}
						}
					} else {
						// add in cache
						pkgs_cache.replace (pkg.id, pkg);
					}
				} else {
					// add in cache
					pkgs_cache.replace (pkg.id, pkg);
				}
				pkgs.add (pkg);
				alpm_pkgs.next ();
			}
			// get aur infos
			if (foreign_pkgnames.length > 0) {
				var aur_infos_list = aur_plugin.get_multi_infos (foreign_pkgnames);
				foreach (unowned AURInfos aur_infos in aur_infos_list) {
					AlpmPackageLinked? pkg = data.lookup (aur_infos.name);
					if (pkg != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
			}
		}

		public GenericArray<AlpmPackage> get_installed_pkgs () {
			var pkgs = new GenericArray<AlpmPackage> ();
			alpm_lock.acquire ();
			try {
				initialise_pkgs (alpm_handle.localdb.pkgcache, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_installed_pkgs_async () {
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_installed_pkgs", () => {
					alpm_lock.acquire ();
					try {
						initialise_pkgs (alpm_handle.localdb.pkgcache, ref pkgs);
					} finally {
						alpm_lock.release ();
					}
					context.invoke (get_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_installed_apps_async () {
			var pkgs = new GenericArray<AlpmPackage> ();
			if (config.enable_appstream) {
				try {
					new Thread<int>.try ("get_installed_apps", () => {
						alpm_lock.acquire ();
						try {
							foreach (unowned HashTable<unowned string, App> apps in appstream_plugin.get_apps ()) {
								var iter = HashTableIter<unowned string, App> (apps);
								unowned App app;
								while (iter.next (null, out app)) {
									unowned string pkgname = app.pkgname;
									unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
									if (local_pkg != null) {
										AlpmPackageLinked? pkg = pkgs_cache.lookup (app.id);
										if (pkg == null) {
											pkg = new AlpmPackageLinked.from_alpm (local_pkg, this, handle_ref);
											pkg.set_local_pkg (local_pkg);
											pkg.set_app (app);
											pkgs_cache.replace (pkg.id, pkg);
										}
										pkgs.add (pkg);
									}
								}
							}
						} finally {
							alpm_lock.release ();
						}
						context.invoke (get_installed_apps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		void get_explicitly_installed_pkgs_real (ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						alpm_pkgs.add (alpm_pkg);
					}
					pkgcache.next ();
				}
				initialise_pkgs (alpm_pkgs, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_explicitly_installed_pkgs () {
			var pkgs = new GenericArray<AlpmPackage> ();
			get_explicitly_installed_pkgs_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_explicitly_installed_pkgs_async () {
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_explicitly_installed_pkgs", () => {
					get_explicitly_installed_pkgs_real (ref pkgs);
					context.invoke (get_explicitly_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void get_foreign_pkgs_real (ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					if (!is_syncpkg (alpm_pkg.name)) {
						alpm_pkgs.add (alpm_pkg);
					}
					pkgcache.next ();
				}
				initialise_pkgs (alpm_pkgs, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_foreign_pkgs () {
			var pkgs = new GenericArray<AlpmPackage> ();
			get_foreign_pkgs_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_foreign_pkgs_async () {
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_foreign_pkgs", () => {
					get_foreign_pkgs_real (ref pkgs);
					context.invoke (get_foreign_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void get_orphans_real (ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
						if (requiredby == null) {
							Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
							if (optionalfor == null) {
								alpm_pkgs.add (alpm_pkg);
							} else {
								optionalfor.free_inner (GLib.free);
							}
						} else {
							requiredby.free_inner (GLib.free);
						}
					}
					pkgcache.next ();
				}
				initialise_pkgs (alpm_pkgs, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_orphans () {
			var pkgs = new GenericArray<AlpmPackage> ();
			get_orphans_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_orphans_async () {
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_orphans", () => {
					get_orphans_real (ref pkgs);
					context.invoke (get_orphans_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		unowned Alpm.Package? get_syncpkg (Alpm.Handle? handle, string pkgname) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (pkgname);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		bool is_syncpkg (string pkgname) {
			unowned Alpm.Package? pkg = get_syncpkg (alpm_handle, pkgname);
			if (pkg != null) {
				return true;
			}
			return false;
		}

		public bool is_sync_pkg (string pkgname) {
			alpm_lock.acquire ();
			try {
				return is_syncpkg (pkgname);
			} finally {
				alpm_lock.release ();
			}
		}

		public AlpmPackage? get_sync_pkg (string pkgname) {
			alpm_lock.acquire ();
			try {
				unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
				return initialise_pkg (sync_pkg, sync_pkg);
			} finally {
				alpm_lock.release ();
			}
		}

		unowned Alpm.Package? find_dbs_satisfier (string depstring) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = Alpm.find_satisfier (db.pkgcache, depstring);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		public bool has_sync_satisfier (string depstring) {
			alpm_lock.acquire ();
			try {
				return find_dbs_satisfier (depstring) != null;
			} finally {
				alpm_lock.release ();
			}
		}

		public AlpmPackage? get_sync_satisfier (string depstring) {
			alpm_lock.acquire ();
			try {
				unowned Alpm.Package? sync_pkg = find_dbs_satisfier (depstring);
				return initialise_pkg (sync_pkg, sync_pkg);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_sync_pkgs_by_glob (string glob) {
			var pkgs = new GenericArray<AlpmPackage> ();
			alpm_lock.acquire ();
			try {
				// dbs in reverse order, alpm_list_reverse would return a new list
				var dbs = new GenericArray<unowned Alpm.DB> ();
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					dbs.add (syncdbs.data);
					syncdbs.next ();
				}
				for (int i = (int) dbs.length - 1; i >= 0; i--) {
					unowned Alpm.DB db = dbs[i];
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						// only check by name
						if (Posix.fnmatch (glob, sync_pkg.name) == 0) {
							pkgs.add (initialise_pkg (sync_pkg, sync_pkg));
						}
						pkgcache.next ();
					}
				}
			} finally {
				alpm_lock.release ();
			}
			return pkgs;
		}

		public Package? get_app_by_id (string app_id) {
			Package? pkg = null;
			alpm_lock.acquire ();
			try {
				// fast search, the cache is modified by other threads
				pkg = pkgs_cache.lookup (app_id);
				if (pkg == null && config.enable_appstream) {
					foreach (unowned HashTable<unowned string, App> apps in appstream_plugin.get_apps ()) {
						var iter = HashTableIter<unowned string, App> (apps);
						unowned string current_app_id;
						unowned App app;
						while (iter.next (out current_app_id, out app)) {
							if (current_app_id == app_id) {
								unowned string pkgname = app.pkgname;
								unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
								if (local_pkg != null) {
									var new_pkg = new AlpmPackageLinked.from_alpm (local_pkg, this, handle_ref);
									new_pkg.set_local_pkg (local_pkg);
									new_pkg.set_app (app);
									pkgs_cache.replace (new_pkg.id, new_pkg);
									pkg = new_pkg;
								} else {
									unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
									if (sync_pkg != null) {
										var new_pkg = new AlpmPackageLinked.from_alpm (sync_pkg, this, handle_ref);
										new_pkg.set_local_pkg (local_pkg);
										new_pkg.set_sync_pkg (sync_pkg);
										new_pkg.set_app (app);
										pkgs_cache.replace (new_pkg.id, new_pkg);
										pkg = new_pkg;
									}
								}
								break;
							}
						}
					}
				}
			} finally {
				alpm_lock.release ();
			}
			if (pkg == null && config.enable_flatpak) {
				pkg = flatpak_plugin.get_flatpak_by_app_id (app_id);
			}
			if (pkg == null && config.enable_snap) {
				pkg = snap_plugin.get_snap_by_app_id (app_id);
			}
			return pkg;
		}

		public async InputStream get_url_stream (string url) throws Error {
			// get sure url is valid
			Uri uri = Uri.parse (url, Soup.HTTP_URI_FLAGS);
			var message = new Soup.Message.from_uri ("GET", uri);
			return yield soup_session.send_async (message, Priority.DEFAULT, null);
		}

		// search terms are case insensitive regexes, like with pacman -Ss,
		// a term which is not a valid regex is searched as plain text
		class SearchTerms {
			public string[] terms = {};
			public Regex?[] regexes = {};

			public SearchTerms (string search_string) {
				foreach (unowned string term in search_string.split (" ")) {
					if (term == "") {
						continue;
					}
					Regex? regex = null;
					try {
						regex = new Regex (term, RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE);
					} catch (Error e) {
						// searched as plain text
					}
					terms += term.down ();
					regexes += (owned) regex;
				}
			}

			public bool match (string? str, int index) {
				if (str == null) {
					return false;
				}
				unowned Regex? regex = regexes[index];
				if (regex != null) {
					return regex.match (str);
				}
				return terms[index] in str.down ();
			}

			// a package matches if each term matches its name, description, provides or groups
			public bool match_pkg (Alpm.Package pkg) {
				for (int i = 0; i < terms.length; i++) {
					if (match (pkg.name, i) || match (pkg.desc, i)) {
						continue;
					}
					bool matched = false;
					unowned Alpm.List<unowned Alpm.Depend> provides = pkg.provides;
					while (provides != null) {
						if (match (provides.data.name, i)) {
							matched = true;
							break;
						}
						provides.next ();
					}
					if (!matched) {
						unowned Alpm.List<unowned string> groups = pkg.groups;
						while (groups != null) {
							if (match (groups.data, i)) {
								matched = true;
								break;
							}
							groups.next ();
						}
					}
					if (!matched) {
						return false;
					}
				}
				return true;
			}
		}

		Alpm.List<unowned Alpm.Package> custom_db_search (Alpm.DB db, SearchTerms search_terms) {
			Alpm.List<unowned Alpm.Package> result = null;
			if (search_terms.terms.length == 0) {
				return result;
			}
			unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package pkg = pkgcache.data;
				if (search_terms.match_pkg (pkg)) {
					result.add (pkg);
				}
				pkgcache.next ();
			}
			return result;
		}

		// packages found in sync dbs, without duplicates
		Alpm.List<unowned Alpm.Package> search_sync_dbs_only (SearchTerms search_terms) {
			Alpm.List<unowned Alpm.Package> syncpkgs = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (syncpkgs == null) {
					syncpkgs = custom_db_search (db, search_terms);
				} else {
					syncpkgs.join (custom_db_search (db, search_terms).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
				}
				syncdbs.next ();
			}
			return syncpkgs;
		}

		Alpm.List<unowned Alpm.Package> search_local_db (string search_string) {
			return custom_db_search (alpm_handle.localdb, new SearchTerms (search_string));
		}

		Alpm.List<unowned Alpm.Package> search_sync_dbs (string search_string) {
			var search_terms = new SearchTerms (search_string);
			// add local pkgs found
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, search_terms);
			Alpm.List<unowned Alpm.Package> syncpkgs = search_sync_dbs_only (search_terms);
			// remove foreign pkgs from local pkgs found
			Alpm.List<unowned Alpm.Package> foreigns = result.diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			result = result.diff (foreigns, (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			// add sync pkgs not already found in localdb
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			return result;
		}

		Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
			var search_terms = new SearchTerms (search_string);
			// add local pkgs found
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, search_terms);
			Alpm.List<unowned Alpm.Package> syncpkgs = search_sync_dbs_only (search_terms);
			// add sync pkgs not already found in localdb
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			return result;
		}

		// add packages of the apps found in appstream data:
		// installed ones if use_local, else or if not installed the sync ones if use_sync
		void add_appstream_results (ref Alpm.List<unowned Alpm.Package>? result, string[] search_tokens, bool use_local, bool use_sync) {
			if (!config.enable_appstream) {
				return;
			}
			foreach (unowned App app in appstream_plugin.search (search_tokens)) {
				unowned string pkgname = app.pkgname;
				unowned Alpm.Package? alpm_pkg = null;
				if (use_local) {
					alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
				}
				if (alpm_pkg == null && use_sync) {
					alpm_pkg = get_syncpkg (alpm_handle, pkgname);
				}
				if (alpm_pkg != null && result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
					result.add (alpm_pkg);
				}
			}
		}

		void search_installed_pkgs_real (string search_string, ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> result = search_local_db (search_string);
				add_appstream_results (ref result, search_string.split (" "), true, false);
				initialise_pkgs (result, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> search_installed_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			search_installed_pkgs_real (search_string_down, ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> search_installed_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_installed_pkgs", () => {
					search_installed_pkgs_real (search_string_down, ref pkgs);
					context.invoke (search_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void search_repos_pkgs_real (string search_string, ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> result = search_sync_dbs (search_string);
				add_appstream_results (ref result, search_string.split (" "), false, true);
				initialise_pkgs (result, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> search_repos_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			search_repos_pkgs_real (search_string_down, ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> search_repos_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_repos_pkgs", () => {
					search_repos_pkgs_real (search_string_down, ref pkgs);
					context.invoke (search_repos_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public GenericArray<AlpmPackage> search_uninstalled_apps (GenericArray<string> search_terms) {
			var pkgs = new GenericArray<AlpmPackage> ();
			// search only in appstream
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				if (config.enable_appstream) {
					string[] data = search_terms.data;
					foreach (unowned App app in appstream_plugin.search (data)) {
						unowned string pkgname = app.pkgname;
						unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
						if (alpm_pkg == null) {
							alpm_pkg = get_syncpkg (alpm_handle, pkgname);
							if (alpm_pkg != null) {
								if (appstream_result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
									appstream_result.add (alpm_pkg);
								}
							}
						}
					}
				}
				initialise_pkgs (appstream_result, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
			return pkgs;
		}

		void search_pkgs_real (string search_string, ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> result = search_all_dbs (search_string);
				add_appstream_results (ref result, search_string.split (" "), true, true);
				initialise_pkgs (result, ref pkgs);
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> search_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			search_pkgs_real (search_string_down, ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> search_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_pkgs", () => {
					search_pkgs_real (search_string_down, ref pkgs);
					context.invoke (search_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void search_aur_pkgs_real (string search_string, ref GenericArray<AURPackage> pkgs) {
			var aur_infos_list = aur_plugin.search (search_string);
			alpm_lock.acquire ();
			try {
				foreach (unowned AURInfos aur_infos in aur_infos_list) {
					unowned string name = aur_infos.name;
					AURPackageLinked pkg = aur_pkgs_cache.lookup (name);
					if (pkg == null) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
						pkg = new AURPackageLinked ();
						pkg.initialise_from_aur_infos (aur_infos, local_pkg, this, handle_ref);
						aur_pkgs_cache.replace (pkg.id, pkg);
					}
					pkgs.add (pkg);
				}
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AURPackage> search_aur_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AURPackage> ();
			if (config.enable_aur) {
				search_aur_pkgs_real (search_string_down, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<AURPackage> search_aur_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<AURPackage> ();
			if (config.enable_aur) {
				try {
					new Thread<int>.try ("search_aur_pkgs", () => {
						search_aur_pkgs_real (search_string_down, ref pkgs);
						context.invoke (search_aur_pkgs_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		// a searched string matches a file if it is in its full path: root + file name,
		// the full path is only built for matching files
		class FileSearch {
			string root;
			string query;
			// query parts after a suffix of root, to compare with the start of file names
			string[] name_prefixes = {};

			public FileSearch (string root, string query) {
				this.root = root;
				this.query = query;
				int max = int.min (root.length, query.length);
				for (int k = 1; k <= max; k++) {
					if (root.has_suffix (query.substring (0, k))) {
						name_prefixes += query.substring (k);
					}
				}
			}

			public bool match (string filename) {
				if (query in filename) {
					return true;
				}
				foreach (unowned string prefix in name_prefixes) {
					if (filename.has_prefix (prefix)) {
						return true;
					}
				}
				return root.length > 0 && query in root;
			}
		}

		// add files of pkgs matching one of the searches, a pkg can be found several times
		void search_files_in_pkgs (Alpm.List<unowned Alpm.Package> pkgcache, FileSearch[] searches, HashTable<string, GenericArray<string>> result) {
			unowned string root = alpm_handle.root;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				unowned GenericArray<string>? found_files = result.lookup (alpm_pkg.name);
				// files already found for this pkg in another db, e.g. in localdb
				GenericSet<string>? previous_files = null;
				if (found_files != null) {
					previous_files = new GenericSet<string> (str_hash, str_equal);
					foreach (unowned string path in found_files) {
						previous_files.add (path);
					}
				}
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					unowned string filename = file_ptr->name;
					// exclude directory name
					if (filename.has_suffix ("/")) {
						continue;
					}
					foreach (unowned FileSearch search in searches) {
						if (search.match (filename)) {
							string path = root + filename;
							if (found_files == null) {
								var new_found_files = new GenericArray<string> ();
								found_files = new_found_files;
								result.insert (alpm_pkg.name, (owned) new_found_files);
							} else if (previous_files != null && path in previous_files) {
								break;
							}
							found_files.add ((owned) path);
							break;
						}
					}
				}
				pkgcache.next ();
			}
		}

		public HashTable<string, GenericArray<string>> search_files (GenericArray<string> files) {
			var result = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			alpm_lock.acquire ();
			try {
				FileSearch[] searches = {};
				foreach (unowned string file in files) {
					searches += new FileSearch (alpm_handle.root, file);
				}
				if (searches.length == 0) {
					return result;
				}
				// search in localdb
				search_files_in_pkgs (alpm_handle.localdb.pkgcache, searches, result);
				// search in syncdbs
				unowned Alpm.List<unowned Alpm.DB> syncdbs = files_handle.syncdbs;
				while (syncdbs != null) {
					search_files_in_pkgs (syncdbs.data.pkgcache, searches, result);
					syncdbs.next ();
				}
			} finally {
				alpm_lock.release ();
			}
			return result;
		}

		const string[] CATEGORIES = {
			"Featured",
			"Photo & Video",
			"Music & Audio",
			"Productivity",
			"Communication & News",
			"Education & Science",
			"Games",
			"Utilities",
			"Development"
		};

		public unowned GenericArray<string> get_categories_names () {
			if (categories_names != null) {
				return categories_names;
			}
			categories_names = new GenericArray<string> ();
			foreach (unowned string category in CATEGORIES) {
				categories_names.add (category);
			}
			return categories_names;
		}

		GenericArray<AlpmPackage> get_apps_pkgs (HashTable<unowned string, unowned App> apps) {
			var pkgs = new GenericArray<AlpmPackage> ();
			var iter = HashTableIter<unowned string, unowned App> (apps);
			unowned App app;
			while (iter.next (null, out app)) {
				unowned string pkgname = app.pkgname;
				AlpmPackageLinked? pkg = pkgs_cache.lookup (app.id);
				if (pkg != null) {
					pkgs.add (pkg);
					continue;
				}
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
				if (local_pkg != null) {
					pkg = new AlpmPackageLinked.from_alpm (local_pkg, this, handle_ref);
					pkg.set_local_pkg (local_pkg);
					pkg.set_app (app);
					pkgs.add (pkg);
					pkgs_cache.replace (pkg.id, pkg);
				} else {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
					if (sync_pkg != null) {
						pkg = new AlpmPackageLinked.from_alpm (sync_pkg, this, handle_ref);
						pkg.set_local_pkg (local_pkg);
						pkg.set_sync_pkg (sync_pkg);
						pkg.set_app (app);
						pkgs.add (pkg);
						pkgs_cache.replace (pkg.id, pkg);
					}
				}
			}
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_category_pkgs_async (string category) {
			var pkgs = new GenericArray<AlpmPackage> ();
			if (config.enable_appstream) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_pkgs", () => {
						alpm_lock.acquire ();
						try {
							if (category_copy in CATEGORIES) {
								pkgs = get_apps_pkgs (appstream_plugin.get_category_apps (category_copy));
							}
						} finally {
							alpm_lock.release ();
						}
						context.invoke (get_category_pkgs_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		// a copy that callers can modify, updated by refresh ()
		public GenericArray<string> get_repos_names () {
			alpm_lock.acquire ();
			try {
				if (repos_names == null) {
					repos_names = new GenericArray<string> ();
					if (alpm_handle == null) {
						return repos_names.copy (strdup);
					}
					unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
					while (syncdbs != null) {
						unowned Alpm.DB db = syncdbs.data;
						repos_names.add (db.name);
						syncdbs.next ();
					}
				}
				return repos_names.copy (strdup);
			} finally {
				alpm_lock.release ();
			}
		}

		void get_repo_pkgs_real (string repo, ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					if (db.name == repo) {
						unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package sync_pkg = pkgcache.data;
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (sync_pkg.name);
							if (local_pkg != null) {
								AlpmPackage? new_pkg = initialise_pkg (local_pkg, sync_pkg);
								pkgs.add (new_pkg);
							} else {
								AlpmPackage? new_pkg = initialise_pkg (sync_pkg, sync_pkg);
								pkgs.add (new_pkg);
							}
							pkgcache.next ();
						}
						break;
					}
					syncdbs.next ();
				}
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_repo_pkgs (string repo) {
			var pkgs = new GenericArray<AlpmPackage> ();
			get_repo_pkgs_real (repo, ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_repo_pkgs_async (string repo) {
			var pkgs = new GenericArray<AlpmPackage> ();
			string repo_copy = repo;
			try {
				new Thread<int>.try ("get_repo_pkgs", () => {
					get_repo_pkgs_real (repo_copy, ref pkgs);
					context.invoke (get_repo_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		// a copy that callers can modify, updated by refresh ()
		public GenericArray<string> get_groups_names () {
			alpm_lock.acquire ();
			try {
				if (groups_names != null) {
					return groups_names.copy (strdup);
				}
				groups_names = new GenericArray<string> ();
				unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
				while (groupcache != null) {
					unowned Alpm.Group group = groupcache.data;
					groups_names.add (group.name);
					groupcache.next ();
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					groupcache = db.groupcache;
					while (groupcache != null) {
						unowned Alpm.Group group = groupcache.data;
						if (!groups_names.find_with_equal_func (group.name, str_equal)) {
							groups_names.add (group.name);
						}
						groupcache.next ();
					}
					syncdbs.next ();
				}
				groups_names.sort (strcmp);
				return groups_names.copy (strdup);
			} finally {
				alpm_lock.release ();
			}
		}

		void get_group_pkgs_real (string group_name, ref GenericArray<AlpmPackage> pkgs) {
			alpm_lock.acquire ();
			try {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				int dbs_found = 0;
				unowned Alpm.Group? grp = alpm_handle.localdb.get_group (group_name);
				if (grp != null) {
					dbs_found++;
					unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
					while (packages != null) {
						unowned Alpm.Package local_pkg = packages.data;
						alpm_pkgs.add (local_pkg);
						packages.next ();
					}
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					grp = db.get_group (group_name);
					if (grp != null) {
						dbs_found++;
						unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
						while (packages != null) {
							unowned Alpm.Package pkg = packages.data;
							if (alpm_pkgs.find (pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
								alpm_pkgs.add (pkg);
							}
							packages.next ();
						}
					}
					syncdbs.next ();
				}
				initialise_pkgs (alpm_pkgs, ref pkgs);
				if (dbs_found > 1) {
					pkgs.sort (pkg_compare_name);
				}
			} finally {
				alpm_lock.release ();
			}
		}

		public GenericArray<AlpmPackage> get_group_pkgs (string group_name) {
			var pkgs = new GenericArray<AlpmPackage> ();
			get_group_pkgs_real (group_name, ref pkgs);
			return pkgs;
		}

		public async GenericArray<AlpmPackage> get_group_pkgs_async (string group_name) {
			var pkgs = new GenericArray<AlpmPackage> ();
			string group_name_copy = group_name;
			try {
				new Thread<int>.try ("get_group_pkgs", () => {
					get_group_pkgs_real (group_name_copy, ref pkgs);
					context.invoke (get_group_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public AlpmPackage? get_pkg (string pkgname) {
			if (is_installed_pkg (pkgname)) {
				return get_installed_pkg (pkgname);
			}
			return get_sync_pkg (pkgname);
		}

		// files of pkg with their full path, the alpm lock must be held
		internal static void add_pkg_files (string root, Alpm.Package pkg, GenericArray<string> files) {
			unowned Alpm.FileList filelist = pkg.files;
			Alpm.File* file_ptr = filelist.files;
			for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
				if (!file_ptr->name.has_suffix ("/")) {
					var filename = new StringBuilder (root);
					filename.append (file_ptr->name);
					files.add ((owned) filename.str);
				}
			}
		}

		void get_pkg_files_real (string pkgname, Alpm.Package? local_pkg, ref GenericArray<string> files) {
			alpm_lock.acquire ();
			try {
				if (local_pkg != null) {
					add_pkg_files (alpm_handle.root, local_pkg, files);
				} else {
					unowned Alpm.List<unowned Alpm.DB> syncdbs = files_handle.syncdbs;
					while (syncdbs != null) {
						unowned Alpm.DB db = syncdbs.data;
						unowned Alpm.Package? files_pkg = db.get_pkg (pkgname);
						if (files_pkg != null) {
							add_pkg_files (alpm_handle.root, files_pkg, files);
							break;
						}
						syncdbs.next ();
					}
				}
			} finally {
				alpm_lock.release ();
			}
		}

		internal GenericArray<string> get_pkg_files (string pkgname, Alpm.Package? local_pkg) {
			var files = new GenericArray<string> ();
			get_pkg_files_real (pkgname, local_pkg, ref files);
			return files;
		}

		internal async GenericArray<string> get_pkg_files_async (string pkgname, Alpm.Package? local_pkg) {
			var files = new GenericArray<string> ();
			try {
				new Thread<int>.try ("get_pkg_files", () => {
					get_pkg_files_real (pkgname, local_pkg, ref files);
					context.invoke (get_pkg_files_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return files;
		}

		int launch_subprocess (SubprocessLauncher launcher, GenericArray<string> cmdline, Cancellable? cancellable = null) {
			int status = 1;
			try {
				// spawnv needs a null terminated array
				cmdline.length = cmdline.length + 1;
				Subprocess process = launcher.spawnv (cmdline.data);
				try {
					process.wait (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
					return 1;
				}
			} catch (Error e) {
				warning (e.message);
			}
			return status;
		}

		// files of an old clone can be removed by systemd-tmpfiles,
		// checkout the tracked files missing in the working tree,
		// local modifications of other files are kept
		int restore_deleted_build_files (string cwd, GenericArray<string> dynamic_user_cmdline, Cancellable? cancellable) {
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
			launcher.set_cwd (cwd);
			var cmdline = dynamic_user_cmdline.copy (strdup);
			cmdline.add ("git");
			cmdline.add ("ls-files");
			cmdline.add ("--deleted");
			cmdline.add ("-z");
			// spawnv needs a null terminated array
			cmdline.length = cmdline.length + 1;
			var deleted_files = new GenericArray<string> ();
			try {
				Subprocess process = launcher.spawnv (cmdline.data);
				Bytes? stdout_buf;
				process.communicate (null, cancellable, out stdout_buf, null);
				if (!process.get_if_exited () || process.get_exit_status () != 0) {
					return 1;
				}
				if (stdout_buf != null) {
					unowned uint8[] data = stdout_buf.get_data ();
					unowned string output = (string) data;
					int start = 0;
					for (int i = 0; i < data.length; i++) {
						// each file name is terminated by a nul byte
						if (data[i] == '\0') {
							if (i > start) {
								deleted_files.add (output.offset (start).substring (0, i - start));
							}
							start = i + 1;
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
				return 1;
			}
			if (deleted_files.length == 0) {
				return 0;
			}
			launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
			launcher.set_cwd (cwd);
			cmdline = dynamic_user_cmdline.copy (strdup);
			cmdline.add ("git");
			cmdline.add ("checkout");
			cmdline.add ("-q");
			// file names from the AUR repository must not be read as options
			cmdline.add ("--");
			foreach (unowned string filename in deleted_files) {
				cmdline.add (filename);
			}
			return launch_subprocess (launcher, cmdline, cancellable);
		}

		public File? clone_build_files (string pkgname, bool overwrite_files, Cancellable? cancellable = null) {
			int status = 1;
			GenericArray<string> cmdline;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			// check again the build directory: it may have been removed
			// since startup (e.g. by systemd-tmpfiles) and recreated by another user
			aur_plugin.set_real_build_dir (config.aur_build_dir);
			unowned string real_aur_build_dir = get_real_aur_build_dir ();
			var builddir = File.new_for_path (real_aur_build_dir);
			if (!builddir.query_exists ()) {
				try {
					builddir.make_directory_with_parents ();
				} catch (Error e) {
					warning (e.message);
					return null;
				}
			}
			GenericArray<string> dynamic_user_cmdline = get_dynamic_user_cmdline (real_aur_build_dir);
			var pkgdir = builddir.get_child (pkgname);
			if (pkgdir.query_exists ()) {
				if (overwrite_files) {
					launcher.set_cwd (real_aur_build_dir);
					cmdline = dynamic_user_cmdline.copy (strdup);
					cmdline.add ("rm");
					cmdline.add ("-rf");
					cmdline.add ("--");
					cmdline.add (pkgdir.get_path ());
					launch_subprocess (launcher, cmdline);
					cmdline = dynamic_user_cmdline;
					cmdline.add ("git");
					cmdline.add ("clone");
					cmdline.add ("-q");
					cmdline.add ("--depth=1");
					cmdline.add ("https://aur.archlinux.org/%s.git".printf (pkgname));
				} else {
					// fetch modifications
					string cwd = pkgdir.get_path ();
					launcher.set_cwd (cwd);
					cmdline = dynamic_user_cmdline.copy (strdup);
					cmdline.add ("git");
					cmdline.add ("fetch");
					cmdline.add ("-q");
					status = launch_subprocess (launcher, cmdline, cancellable);
					if (cancellable.is_cancelled ()) {
						return null;
					}
					// restore tracked files removed from the build directory,
					// git merge would not bring them back
					if (status == 0) {
						status = restore_deleted_build_files (cwd, dynamic_user_cmdline, cancellable);
						if (cancellable.is_cancelled ()) {
							return null;
						}
					}
					// write diff file
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_PIPE);
						try {
							var file = File.new_for_path (Path.build_filename (cwd, "diff"));
							if (file.query_exists ()) {
								// delete the file before rewrite it
								file.delete ();
							}
							cmdline = dynamic_user_cmdline.copy (strdup);
							cmdline.add ("git");
							cmdline.add ("diff");
							cmdline.add ("--exit-code");
							cmdline.add ("origin/master");
							// file names from the AUR repository must not be read as options
							cmdline.add ("--");
							FileEnumerator enumerator = pkgdir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
							FileInfo info;
							// don't show .SRCINFO diff
							while ((info = enumerator.next_file (null)) != null) {
								unowned string filename = info.get_name ();
								if (filename != ".SRCINFO" && filename != ".git") {
									cmdline.add (filename);
								}
							}
							// spawnv needs a null terminated array
							cmdline.length = cmdline.length + 1;
							Subprocess process = launcher.spawnv (cmdline.data);
							// read the output while waiting,
							// git would block on a full pipe
							Bytes? stdout_buf;
							process.communicate (null, null, out stdout_buf, null);
							if (process.get_if_exited ()) {
								status = process.get_exit_status ();
							}
							if (status == 1) {
								// there is a diff
								if (stdout_buf != null) {
									var dos = new DataOutputStream (file.create (FileCreateFlags.NONE));
									// writing output to diff
									dos.splice (new MemoryInputStream.from_bytes (stdout_buf), OutputStreamSpliceFlags.CLOSE_TARGET);
								}
								status = 0;
							}
						} catch (Error e) {
							warning (e.message);
						}
						launcher.set_flags (SubprocessFlags.NONE);
					}
					// merge modifications
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
						cmdline = dynamic_user_cmdline.copy (strdup);
						cmdline.add ("git");
						cmdline.add ("merge");
						cmdline.add ("-q");
						status = launch_subprocess (launcher, cmdline);
					}
					if (status == 0) {
						return pkgdir;
					} else {
						launcher.set_cwd (real_aur_build_dir);
						cmdline = dynamic_user_cmdline.copy (strdup);
						cmdline.add ("rm");
						cmdline.add ("-rf");
						cmdline.add ("--");
						cmdline.add (pkgdir.get_path ());
						launch_subprocess (launcher, cmdline);
						cmdline = dynamic_user_cmdline;
						cmdline.add ("git");
						cmdline.add ("clone");
						cmdline.add ("-q");
						cmdline.add ("--depth=1");
						cmdline.add ("https://aur.archlinux.org/%s.git".printf (pkgname));
					}
				}
			} else {
				launcher.set_cwd (real_aur_build_dir);
				cmdline = dynamic_user_cmdline;
				cmdline.add ("git");
				cmdline.add ("clone");
				cmdline.add ("-q");
				cmdline.add ("--depth=1");
				cmdline.add ("https://aur.archlinux.org/%s.git".printf (pkgname));
			}
			status = launch_subprocess (launcher, cmdline, cancellable);
			if (status == 0) {
				return pkgdir;
			}
			return null;
		}

		public async File? clone_build_files_async (string pkgname, bool overwrite_files, Cancellable? cancellable = null) {
			File? file = null;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("clone_build_files", () => {
					file = clone_build_files (pkgname_copy, overwrite_files, cancellable);
					context.invoke (clone_build_files_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return file;
		}

		GenericArray<string> get_dynamic_user_cmdline (string cwd) {
			var cmdline = new GenericArray<string> ();
			if (Posix.geteuid () == 0) {
				cmdline.add ("systemd-run");
				cmdline.add ("--service-type=oneshot");
				cmdline.add ("--pipe");
				cmdline.add ("--wait");
				cmdline.add ("--pty");
				cmdline.add ("--property=DynamicUser=yes");
				cmdline.add ("--property=CacheDirectory=pamac");
				cmdline.add ("--property=WorkingDirectory=%s".printf (cwd));
			}
			return cmdline;
		}

		public bool regenerate_srcinfo (string pkgname, Cancellable? cancellable = null) {
			unowned string real_aur_build_dir = get_real_aur_build_dir ();
			string pkgdir_name = Path.build_filename (real_aur_build_dir, pkgname);
			var srcinfo = File.new_for_path (Path.build_filename (pkgdir_name, ".SRCINFO"));
			var pkgbuild = File.new_for_path (Path.build_filename (pkgdir_name, "PKGBUILD"));
			if (srcinfo.query_exists ()) {
				// check if PKGBUILD was modified after .SRCINFO
				try {
					FileInfo info = srcinfo.query_info ("time::modified", 0);
					DateTime srcinfo_time = info.get_modification_date_time ();
					info = pkgbuild.query_info ("time::modified", 0);
					DateTime pkgbuild_time = info.get_modification_date_time ();
					if (srcinfo_time.compare (pkgbuild_time) == 1) {
						// no need to regenerate
						return true;
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			// generate .SRCINFO
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
			launcher.set_cwd (pkgdir_name);
			try {
				GenericArray<string> cmdline = get_dynamic_user_cmdline (pkgdir_name);
				cmdline.add ("makepkg");
				cmdline.add ("--printsrcinfo");
				// spawnv needs a null terminated array
				cmdline.length = cmdline.length + 1;
				Subprocess process = launcher.spawnv (cmdline.data);
				try {
					// read the output while waiting,
					// makepkg would block on a full pipe
					Bytes? stdout_buf;
					process.communicate (null, cancellable, out stdout_buf, null);
					if (process.get_if_exited ()) {
						if (process.get_exit_status () == 0 && stdout_buf != null) {
							try {
								var dis = new MemoryInputStream.from_bytes (stdout_buf);
								FileOutputStream fos;
								if (srcinfo.query_exists ()) {
									fos = srcinfo.replace (null, false, FileCreateFlags.NONE);
								} else {
									fos = srcinfo.create (FileCreateFlags.NONE);
								}
								// creating a DataOutputStream to the file
								var dos = new DataOutputStream (fos);
								// writing makepkg output to .SRCINFO
								dos.splice (dis, OutputStreamSpliceFlags.NONE);
								return true;
							} catch (Error e) {
								warning (e.message);
							}
						}
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				warning (e.message);
			}
			return false;
		}

		public async bool regenerate_srcinfo_async (string pkgname, Cancellable? cancellable = null) {
			bool success = false;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("regenerate_srcinfo", () => {
					success = regenerate_srcinfo (pkgname_copy, cancellable);
					context.invoke (regenerate_srcinfo_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return success;
		}

		public AURPackage? get_aur_pkg (string pkgname) {
			AURPackageLinked? pkg = null;
			if (config.enable_aur) {
				alpm_lock.acquire ();
				pkg = aur_pkgs_cache.lookup (pkgname);
				alpm_lock.release ();
				if (pkg != null) {
					return pkg;
				}
				// can reload the AUR data, do not hold the lock
				AURInfos? aur_infos = aur_plugin.get_infos (pkgname);
				if (aur_infos == null) {
					return null;
				}
				alpm_lock.acquire ();
				try {
					// may have been added meanwhile
					pkg = aur_pkgs_cache.lookup (pkgname);
					if (pkg == null) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
						pkg = new AURPackageLinked ();
						pkg.initialise_from_aur_infos (aur_infos, local_pkg, this, handle_ref);
						aur_pkgs_cache.replace (pkg.id, pkg);
					}
				} finally {
					alpm_lock.release ();
				}
			}
			return pkg;
		}

		public async AURPackage? get_aur_pkg_async (string pkgname) {
			AURPackage? pkg = null;
			if (config.enable_aur) {
				string pkgname_copy = pkgname;
				try {
					new Thread<int>.try ("get_aur_pkg", () => {
						pkg = get_aur_pkg (pkgname_copy);
						context.invoke (get_aur_pkg_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		void get_aur_pkgs_real (GenericArray<string> pkgnames, ref HashTable<string, AURPackage?> data) {
			// prepare data with all keys
			foreach (unowned string pkgname in pkgnames) {
				data.insert (pkgname, null);
			}
			var aur_infos_list = aur_plugin.get_multi_infos (pkgnames);
			alpm_lock.acquire ();
			try {
				foreach (unowned AURInfos aur_infos in aur_infos_list) {
					unowned string name = aur_infos.name;
					AURPackageLinked pkg = aur_pkgs_cache.lookup (name);
					if (pkg == null) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
						pkg = new AURPackageLinked ();
						pkg.initialise_from_aur_infos (aur_infos, local_pkg, this, handle_ref);
						aur_pkgs_cache.replace (pkg.id, pkg);
					}
					data.insert (name, pkg);
				}
			} finally {
				alpm_lock.release ();
			}
		}

		public HashTable<string, AURPackage?> get_aur_pkgs (GenericArray<string> pkgnames) {
			var data = new HashTable<string, AURPackage?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			get_aur_pkgs_real (pkgnames, ref data);
			return data;
		}

		public async HashTable<string, AURPackage?> get_aur_pkgs_async (GenericArray<string> pkgnames) {
			var data = new HashTable<string, AURPackage?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			try {
				new Thread<int>.try ("get_aur_pkgs", () => {
					get_aur_pkgs_real (pkgnames, ref data);
					context.invoke (get_aur_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return data;
		}

		public async void refresh_tmp_files_dbs_async () {
			try {
				new Thread<int>.try ("refresh_tmp_files_dbs", () => {
					refresh_tmp_files_dbs ();
					context.invoke (refresh_tmp_files_dbs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void refresh_tmp_files_dbs () {
			Alpm.Handle? tmp_files_handle;
			alpm_lock.acquire ();
			tmp_files_handle = alpm_config.get_handle (true, true);
			if (tmp_files_handle != null) {
				alpm_config.register_syncdbs (tmp_files_handle);
			}
			alpm_lock.release ();
			// the download uses only this private handle, do not hold the lock
			if (tmp_files_handle != null) {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_files_handle.syncdbs;
				tmp_files_handle.update_dbs (syncdbs, 0);
			}
		}

		public DateTime? get_last_refresh_time () {
			string timestamp_path = Path.build_filename (alpm_handle.dbpath, "sync", "refresh_timestamp");
			// check if last refresh is older than config.refresh_period
			try {
				var timestamp_file = File.new_for_path (timestamp_path);
				if (timestamp_file.query_exists ()) {
					FileInfo info = timestamp_file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
					return info.get_modification_date_time ().to_local ();
				}
			} catch (Error e) {
				warning (e.message);
			}
			return null;
		}

		int64 get_last_refresh_age () {
			DateTime? last_modifed = get_last_refresh_time ();
			if (last_modifed == null) {
				return int64.MAX;
			}
			var now = new DateTime.now_local ();
			TimeSpan elapsed_time = now.difference (last_modifed);
			return elapsed_time;
		}

		public bool need_refresh () {
			bool need_refresh = true;
			int64 elapsed_time = get_last_refresh_age ();
			if (elapsed_time < TimeSpan.HOUR) {
				need_refresh = false;
			} else {
				int64 elapsed_hours = elapsed_time / TimeSpan.HOUR;
				if (elapsed_hours < config.refresh_period) {
					need_refresh = false;
				}
			}
			return need_refresh;
		}

		// installed pkgs not found in sync dbs, which can be AUR pkgs,
		// VCS pkgs are also added to vcs_local_pkgs if their updates are checked
		void get_aur_local_pkgs (GenericArray<string> local_pkgs, GenericArray<string> vcs_local_pkgs) {
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				unowned string name = installed_pkg.name;
				if (get_syncpkg (alpm_handle, name) == null) {
					if (config.check_aur_vcs_updates &&
						(name.has_suffix ("-git")
						|| name.has_suffix ("-svn")
						|| name.has_suffix ("-bzr")
						|| name.has_suffix ("-hg"))) {
						// for speed reason, do not check vcs update for ignored packages
						if (alpm_handle.should_ignore (installed_pkg) == 0) {
							local_pkgs.add (name);
							vcs_local_pkgs.add (name);
						}
					} else {
						// check for ignorepkgs done in get_aur_updates_real
						local_pkgs.add (name);
					}
				}
				pkgcache.next ();
			}
		}

		void emit_get_updates_progress (uint percent) {
			context.invoke (() => {
				get_updates_progress (percent);
				return false;
			});
		}

		// the lock is not held during network operations (flatpak updates, VCS sources)
		// to not block other requests
		void get_updates_real (ref Updates updates) {
			var local_pkgs = new GenericArray<string> ();
			var vcs_local_pkgs = new GenericArray<string> ();
			alpm_lock.acquire ();
			try {
				unowned GenericArray<AlpmPackage> repos_updates = updates.repos_updates;
				unowned GenericArray<AlpmPackage> ignored_repos_updates = updates.ignored_repos_updates;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package installed_pkg = pkgcache.data;
					unowned Alpm.Package? candidate = installed_pkg.get_new_version (alpm_handle.syncdbs);
					if (candidate != null) {
						var pkg = initialise_pkg_data (installed_pkg, candidate);
						// check if installed_pkg is in IgnorePkg or IgnoreGroup
						// check if candidate is in IgnorePkg or IgnoreGroup in case of replacer
						if (alpm_handle.should_ignore (installed_pkg) == 1 ||
							alpm_handle.should_ignore (candidate) == 1) {
							ignored_repos_updates.add (pkg);
						} else {
							repos_updates.add (pkg);
						}
					}
					pkgcache.next ();
				}
				if (config.check_aur_updates) {
					get_aur_local_pkgs (local_pkgs, vcs_local_pkgs);
				}
			} finally {
				alpm_lock.release ();
			}
			GenericArray<FlatpakPackage> flatpak_updates = updates.flatpak_updates;
			if (config.check_flatpak_updates) {
				flatpak_plugin.get_flatpak_updates (ref flatpak_updates);
			}
			if (config.check_aur_updates) {
				GenericArray<AURInfos> aur_infos_list = aur_plugin.get_multi_infos (local_pkgs);
				HashTable<string, string>? vcs_versions = null;
				if (config.check_aur_vcs_updates) {
					refresh_vcs_sources (aur_infos_list, vcs_local_pkgs);
					vcs_versions = get_vcs_last_version (aur_infos_list, vcs_local_pkgs);
				}
				// count this step as 5% of the total
				emit_get_updates_progress (95);
				alpm_lock.acquire ();
				try {
					get_aur_updates_real (aur_infos_list, vcs_versions, ref updates);
				} finally {
					alpm_lock.release ();
				}
			}
			emit_get_updates_progress (100);
		}

		public Updates get_updates () {
			var updates = new Updates ();
			get_updates_real (ref updates);
			return updates;
		}

		public async Updates get_updates_async () {
			var updates = new Updates ();
			try {
				new Thread<int>.try ("get_updates", () => {
					get_updates_real (ref updates);
					context.invoke (get_updates_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return updates;
		}

		// infos of the given VCS pkgs, build files are stored by pkgbase
		static GenericArray<AURInfos> get_vcs_infos (GenericArray<AURInfos> aur_infos_list, GenericArray<string> vcs_local_pkgs) {
			var vcs_infos = new GenericArray<AURInfos> ();
			foreach (unowned AURInfos aur_infos in aur_infos_list) {
				if (vcs_local_pkgs.find_with_equal_func (aur_infos.name, str_equal)) {
					vcs_infos.add (aur_infos);
				}
			}
			return vcs_infos;
		}

		void refresh_vcs_sources (GenericArray<AURInfos> aur_infos_list, GenericArray<string> vcs_local_pkgs) {
			// split pkgs share the same build files
			var done_pkgbases = new GenericSet<string> (str_hash, str_equal);
			foreach (unowned AURInfos aur_infos in get_vcs_infos (aur_infos_list, vcs_local_pkgs)) {
				unowned string? pkgbase = aur_infos.packagebase;
				if (pkgbase == null || pkgbase in done_pkgbases) {
					continue;
				}
				done_pkgbases.add (pkgbase);
				// get last build files
				File? clone_dir = clone_build_files (pkgbase, false, null);
				if (clone_dir != null) {
					// get last sources
					// no output to not pollute checkupdates output
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
					string cwd = clone_dir.get_path ();
					launcher.set_cwd (cwd);
					GenericArray<string> cmdline = get_dynamic_user_cmdline (cwd);
					cmdline.add ("makepkg");
					cmdline.add ("--nobuild");
					cmdline.add ("--noprepare");
					cmdline.add ("--nodeps");
					cmdline.add ("--skipinteg");
					int status = launch_subprocess (launcher, cmdline);
					if (status == 0) {
						regenerate_srcinfo (clone_dir.get_basename (), null);
					}
				}
			}
		}

		// versions in .SRCINFO of the build files of the given VCS pkgs
		HashTable<string, string> get_vcs_last_version (GenericArray<AURInfos> aur_infos_list, GenericArray<string> vcs_local_pkgs) {
			var pkgnames_table = new HashTable<string, string> (str_hash, str_equal);
			unowned string real_aur_build_dir = get_real_aur_build_dir ();
			var done_pkgbases = new GenericSet<string> (str_hash, str_equal);
			foreach (unowned AURInfos aur_infos in get_vcs_infos (aur_infos_list, vcs_local_pkgs)) {
				unowned string? pkgbase = aur_infos.packagebase;
				if (pkgbase == null || pkgbase in done_pkgbases) {
					continue;
				}
				done_pkgbases.add (pkgbase);
				var srcinfo = File.new_for_path (Path.build_filename (real_aur_build_dir, pkgbase, ".SRCINFO"));
				if (!srcinfo.query_exists ()) {
					continue;
				}
				try {
					// read .SRCINFO
					var dis = new DataInputStream (srcinfo.read ());
					string? line;
					var version = new StringBuilder ("");
					while ((line = dis.read_line ()) != null) {
						if ("pkgver = " in line) {
							version.append (line.split (" = ", 2)[1]);
						} else if ("pkgrel = " in line) {
							version.append ("-");
							version.append (line.split (" = ", 2)[1]);
						} else if ("epoch = " in line) {
							version.prepend (":");
							version.prepend (line.split (" = ", 2)[1]);
						} else if ("pkgname = " in line) {
							string pkgname_found = line.split (" = ", 2)[1];
							if (vcs_local_pkgs.find_with_equal_func (pkgname_found, str_equal)) {
								pkgnames_table.insert ((owned) pkgname_found, version.str);
							}
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgnames_table;
		}

		// vcs_versions: versions of VCS pkgs from their build files, null if VCS updates are not checked
		void get_aur_updates_real (GenericArray<AURInfos> aur_infos_list, HashTable<string, string>? vcs_versions, ref Updates updates) {
			unowned GenericArray<AURPackage> aur_updates = updates.aur_updates;
			unowned GenericArray<AURPackage> outofdate = updates.outofdate;
			unowned GenericArray<AURPackage> ignored_aur_updates = updates.ignored_aur_updates;
			foreach (unowned AURInfos aur_infos in aur_infos_list) {
				unowned string name = aur_infos.name;
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
				if (local_pkg == null) {
					// removed since the list was computed
					continue;
				}
				unowned string old_version = local_pkg.version;
				unowned string new_version;
				AURPackageLinked? aur_pkg;
				if (vcs_versions != null) {
					aur_pkg = aur_vcs_pkgs.lookup (name);
					if (aur_pkg == null) {
						unowned string? vcs_version = vcs_versions.lookup (name);
						if (vcs_version != null) {
							new_version = vcs_version;
						} else {
							new_version = aur_infos.version;
						}
						aur_pkg = new AURPackageLinked ();
						aur_pkg.initialise_from_aur_infos (aur_infos, local_pkg, this, handle_ref, true);
						// set aur_pkg.version
						aur_pkg.version = new_version;
						aur_vcs_pkgs.insert (name, aur_pkg);
					} else {
						new_version = aur_pkg.version;
					}
				} else {
					new_version = aur_infos.version;
					aur_pkg = new AURPackageLinked ();
					aur_pkg.initialise_from_aur_infos (aur_infos, local_pkg, this, handle_ref, true);
					// set aur_pkg.version
					aur_pkg.version = new_version;
				}
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					if (alpm_handle.should_ignore (local_pkg) == 1) {
						ignored_aur_updates.add (aur_pkg);
					} else {
						aur_updates.add (aur_pkg);
					}
				} else if (aur_infos.outofdate != null) {
					// get out of date packages
					outofdate.add (aur_pkg);
				}
			}
		}

		internal async Updates get_aur_updates_async (GenericSet<string?> ignorepkgs) {
			var updates = new Updates ();
			try {
				new Thread<int>.try ("get_aur_updates", () => {
					alpm_lock.acquire ();
					try {
						// get local pkgs
						var local_pkgs = new GenericArray<string> ();
						var vcs_local_pkgs = new GenericArray<string> ();
						// use only the given ignorepkgs: the handle also contains
						// the config ignorepkgs added when it was created, and
						// a package removed from them since (e.g. an ignored update
						// explicitly selected) must not be ignored
						var handle_ignorepkgs = new GenericArray<string> ();
						unowned Alpm.List<unowned string> handle_ignorepkgs_list = alpm_handle.ignorepkgs;
						while (handle_ignorepkgs_list != null) {
							handle_ignorepkgs.add (handle_ignorepkgs_list.data);
							handle_ignorepkgs_list.next ();
						}
						foreach (unowned string name in handle_ignorepkgs) {
							alpm_handle.remove_ignorepkg (name);
						}
						foreach (unowned string name in ignorepkgs) {
							alpm_handle.add_ignorepkg (name);
						}
						get_aur_local_pkgs (local_pkgs, vcs_local_pkgs);
						GenericArray<AURInfos> aur_infos_list = aur_plugin.get_multi_infos (local_pkgs);
						HashTable<string, string>? vcs_versions = null;
						if (config.check_aur_vcs_updates) {
							vcs_versions = get_vcs_last_version (aur_infos_list, vcs_local_pkgs);
						}
						get_aur_updates_real (aur_infos_list, vcs_versions, ref updates);
						// restore the handle ignorepkgs
						foreach (unowned string name in ignorepkgs) {
							alpm_handle.remove_ignorepkg (name);
						}
						foreach (unowned string name in handle_ignorepkgs) {
							alpm_handle.add_ignorepkg (name);
						}
					} finally {
						alpm_lock.release ();
					}
					context.invoke (get_aur_updates_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return updates;
		}

		public async GenericArray<SnapPackage> search_snaps_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("search_snaps", () => {
						snap_plugin.search_snaps (search_string_down, ref pkgs);
						context.invoke (search_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public bool is_installed_snap (string name) {
			if (config.enable_snap) {
				return snap_plugin.is_installed_snap (name);
			}
			return false;
		}

		public async SnapPackage? get_snap_async (string name) {
			SnapPackage? pkg = null;
			if (config.enable_snap) {
				string name_copy = name;
				try {
					new Thread<int>.try ("get_snap", () => {
						pkg = snap_plugin.get_snap (name_copy);
						context.invoke (get_snap_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public async GenericArray<SnapPackage> get_installed_snaps_async () {
			var pkgs = new GenericArray<SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("get_installed_snaps", () => {
						snap_plugin.get_installed_snaps (ref pkgs);
						context.invoke (get_installed_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public async string get_installed_snap_icon_async (string name) {
			string icon = "";
			if (config.enable_snap) {
				string name_copy = name;
				try {
					new Thread<int>.try ("get_installed_snap_icon", () => {
						try {
							icon = snap_plugin.get_installed_snap_icon (name_copy);
						} catch (Error e) {
							warning ("%s: %s", name_copy, e.message);
						}
						context.invoke (get_installed_snap_icon_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return icon;
		}

		public async GenericArray<SnapPackage> get_category_snaps_async (string category) {
			var pkgs = new GenericArray<SnapPackage> ();
			if (config.enable_snap) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_snaps", () => {
						snap_plugin.get_category_snaps (category_copy, ref pkgs);
						context.invoke (get_category_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public void refresh_flatpak_appstream_data () {
			if (config.enable_flatpak) {
				flatpak_plugin.refresh_appstream_data ();
			}
		}

		public async void refresh_flatpak_appstream_data_async () {
			if (config.enable_flatpak) {
				try {
					new Thread<int>.try ("refresh_flatpak_appstream_data", () => {
						flatpak_plugin.refresh_appstream_data ();
						context.invoke (refresh_flatpak_appstream_data_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public GenericArray<string> get_flatpak_remotes_names () {
			var list = new GenericArray<string> ();
			if (config.enable_flatpak) {
				flatpak_plugin.get_remotes_names (ref list);
			}
			return list;
		}

		public async GenericArray<FlatpakPackage> get_installed_flatpaks_async () {
			var pkgs = new GenericArray<FlatpakPackage> ();
			if (config.enable_flatpak) {
				try {
					new Thread<int>.try ("get_installed_flatpak", () => {
						flatpak_plugin.get_installed_flatpaks (ref pkgs);
						context.invoke (get_installed_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public async GenericArray<FlatpakPackage> search_flatpaks_async (string search_string) {
			var pkgs = new GenericArray<FlatpakPackage> ();
			if (config.enable_flatpak) {
				string search_string_down = search_string.down ();
				try {
					new Thread<int>.try ("search_flatpaks", () => {
						flatpak_plugin.search_flatpaks (search_string_down, ref pkgs);
						context.invoke (search_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public bool is_installed_flatpak (string name) {
			if (config.enable_flatpak) {
				return flatpak_plugin.is_installed_flatpak (name);
			}
			return false;
		}

		public async FlatpakPackage? get_flatpak_async (string id) {
			FlatpakPackage? pkg = null;
			if (config.enable_flatpak) {
				string id_copy = id;
				try {
					new Thread<int>.try ("get_flatpak", () => {
						pkg = flatpak_plugin.get_flatpak (id_copy);
						context.invoke (get_flatpak_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public async GenericArray<FlatpakPackage> get_category_flatpaks_async (string category) {
			var pkgs = new GenericArray<FlatpakPackage> ();
			if (config.enable_flatpak) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_flatpaks", () => {
						flatpak_plugin.get_category_flatpaks (category_copy, ref pkgs);
						context.invoke (get_category_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (GLib.Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}
	}
}

int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

int pkg_compare_name (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

void cb_evt (void* ctx, Alpm.Event.Data data) {
	switch (data.type) {
		case Alpm.Event.Type.DATABASE_MISSING:
			Pamac.Database database = (Pamac.Database) ctx;
			database.dbs_missing = true;
			break;
		default:
			break;
	}
}
