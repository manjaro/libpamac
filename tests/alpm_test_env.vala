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
	// a pacman installation in a temporary directory: root, databases, cache, hooks
	// and a repository "testrepo" of the packages made by add_package.
	// Nothing outside of it is modified, except by AlpmUtils itself which removes
	// the lock file of the system if it is older than the boot (see check_old_lock)
	internal class AlpmTestEnv : Object {
		public string path { get; private set; }
		public string root_dir { get; private set; }
		public string db_dir { get; private set; }
		public string cache_dir { get; private set; }
		public string hooks_dir { get; private set; }
		public string repo_dir { get; private set; }
		public string conf_path { get; private set; }
		string build_dir;
		Subprocess? server;

		public string lockfile_path {
			owned get {
				return Path.build_filename (db_dir, "db.lck");
			}
		}

		public AlpmTestEnv () throws Error {
			path = DirUtils.make_tmp ("pamac-test-XXXXXX");
			// as root, libalpm downloads in a sandbox as the DownloadUser (alpm):
			// it must reach the cache and the repository
			FileUtils.chmod (path, 0755);
			root_dir = Path.build_filename (path, "root");
			db_dir = Path.build_filename (path, "db");
			cache_dir = Path.build_filename (path, "cache");
			hooks_dir = Path.build_filename (path, "hooks");
			repo_dir = Path.build_filename (path, "repo");
			build_dir = Path.build_filename (path, "build");
			conf_path = Path.build_filename (path, "pacman.conf");
			foreach (unowned string dir in new string[] {root_dir, db_dir, cache_dir, hooks_dir, repo_dir, build_dir}) {
				DirUtils.create_with_parents (dir, 0755);
			}
			// libalpm extracts the scriptlets in the tmp dir of the root
			string root_tmp = Path.build_filename (root_dir, "tmp");
			DirUtils.create_with_parents (root_tmp, 0755);
			FileUtils.chmod (root_tmp, 01777);
		}

		// the first program not found in PATH, or null
		public static string? find_missing_program (string[] programs) {
			foreach (unowned string program in programs) {
				if (Environment.find_program_in_path (program) == null) {
					return program;
				}
			}
			return null;
		}

		public static void run (string[] argv) throws Error {
			var process = new Subprocess.newv (argv, SubprocessFlags.STDOUT_SILENCE);
			process.wait_check ();
		}

		// make name-version-1-any.pkg.tar in the repository dir, returns its path.
		// It installs /opt/test/<name>.bin of size_kb random KiB,
		// install_script is the content of its .INSTALL file
		public string add_package (string name, string version, uint size_kb, string? install_script = null, string[] depends = {}) throws Error {
			string pkgdir = Path.build_filename (build_dir, "%s-%s".printf (name, version));
			string optdir = Path.build_filename (pkgdir, "opt", "test");
			DirUtils.create_with_parents (optdir, 0755);
			string data_path = Path.build_filename (optdir, name + ".bin");
			run ({"sh", "-c", "head -c %uK /dev/urandom > \"$1\"".printf (size_kb), "sh", data_path});
			var pkginfo = new StringBuilder ();
			pkginfo.append ("pkgname = %s\n".printf (name));
			pkginfo.append ("pkgbase = %s\n".printf (name));
			pkginfo.append ("pkgver = %s-1\n".printf (version));
			pkginfo.append ("pkgdesc = pamac test package\n");
			pkginfo.append ("builddate = %s\n".printf ((get_real_time () / TimeSpan.SECOND).to_string ()));
			pkginfo.append ("packager = pamac tests\n");
			pkginfo.append ("size = %s\n".printf (((uint64) size_kb * 1024).to_string ()));
			pkginfo.append ("arch = any\n");
			foreach (unowned string depend in depends) {
				pkginfo.append ("depend = %s\n".printf (depend));
			}
			FileUtils.set_contents (Path.build_filename (pkgdir, ".PKGINFO"), pkginfo.str);
			string pkg_path = Path.build_filename (repo_dir, "%s-%s-1-any.pkg.tar".printf (name, version));
			// .PKGINFO first, libalpm reads it first
			string[] argv = {"bsdtar", "-cf", pkg_path, "-C", pkgdir, ".PKGINFO"};
			if (install_script != null) {
				FileUtils.set_contents (Path.build_filename (pkgdir, ".INSTALL"), install_script);
				argv += ".INSTALL";
			}
			argv += "opt";
			run (argv);
			return pkg_path;
		}

		// add packages to testrepo, a newer version replaces the previous one
		public void repo_add (string[] pkg_paths) throws Error {
			string[] argv = {"repo-add", "-q", Path.build_filename (repo_dir, "testrepo.db.tar.gz")};
			foreach (unowned string pkg_path in pkg_paths) {
				argv += pkg_path;
			}
			run (argv);
		}

		// serve the repository with slow_server.py, returns its url
		public string start_slow_server (string script) throws Error {
			string port_file = Path.build_filename (path, "port");
			// not the outputs of the test: meson waits for them to be closed
			server = new Subprocess.newv ({"python3", "-I", script, repo_dir, port_file},
										SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
			int64 deadline = get_monotonic_time () + 10 * TimeSpan.SECOND;
			while (!FileUtils.test (port_file, FileTest.EXISTS)) {
				if (get_monotonic_time () > deadline) {
					throw new IOError.TIMED_OUT ("the test server did not start");
				}
				Thread.usleep (50000);
			}
			string port;
			FileUtils.get_contents (port_file, out port);
			return "http://127.0.0.1:%s".printf (port.strip ());
		}

		public void write_pacman_conf (string server_url) throws Error {
			var conf = new StringBuilder ();
			conf.append ("[options]\n");
			conf.append ("RootDir = %s/\n".printf (root_dir));
			conf.append ("DBPath = %s/\n".printf (db_dir));
			conf.append ("CacheDir = %s/\n".printf (cache_dir));
			conf.append ("LogFile = %s\n".printf (Path.build_filename (path, "pacman.log")));
			conf.append ("GPGDir = %s/\n".printf (Path.build_filename (path, "gnupg")));
			// never the hooks of the system
			conf.append ("HookDir = %s/\n".printf (hooks_dir));
			conf.append ("Architecture = auto\n");
			conf.append ("SigLevel = Never\n");
			conf.append ("LocalFileSigLevel = Never\n");
			conf.append ("ParallelDownloads = 1\n\n");
			conf.append ("[testrepo]\n");
			conf.append ("Server = %s\n".printf (server_url));
			FileUtils.set_contents (conf_path, conf.str);
		}

		// an AlpmUtils using this installation instead of the one of the system
		public AlpmUtils create_alpm_utils () {
			var alpm_utils = new AlpmUtils (new Config ("/etc/pamac.conf"));
			alpm_utils.alpm_config = new AlpmConfig (conf_path);
			alpm_utils.lockfile = File.new_for_path (lockfile_path);
			return alpm_utils;
		}

		// a new handle on the databases, to check their content
		public Alpm.Handle? get_handle () {
			var alpm_config = new AlpmConfig (conf_path);
			return alpm_config.get_handle (false, false);
		}

		public bool root_file_exists (string relative_path) {
			return FileUtils.test (Path.build_filename (root_dir, relative_path), FileTest.EXISTS);
		}

		// libalpm resumes a partial download, the test server does not support byte ranges
		public void remove_partial_downloads () {
			try {
				var dir = Dir.open (cache_dir);
				unowned string? name;
				while ((name = dir.read_name ()) != null) {
					if (name.has_suffix (".part")) {
						FileUtils.unlink (Path.build_filename (cache_dir, name));
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void cleanup () {
			if (server != null) {
				server.force_exit ();
			}
			try {
				run ({"rm", "-rf", "--", path});
			} catch (Error e) {
				warning (e.message);
			}
		}
	}
}
