/*
 *  pamac-vala
 *
 *  Copyright (C) 2023 Guillaume Benoit <guillaume@manjaro.org>
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

	// with details, print the lines parsed by UpdatesChecker, see parse_update_details in utils.vala
	void print_update (bool details, string source, string name, string? installed_version, string version, uint64 download_size) {
		if (details) {
			stdout.printf ("%s\t%s\t%s\t%s\t%s\n", source, name, installed_version ?? "", version, download_size.to_string ());
		} else if (installed_version != null) {
			stdout.printf ("%s  %s -> %s\n", name, installed_version, version);
		} else {
			stdout.printf ("%s  %s\n", name, version);
		}
	}

	public int checkupdates (bool details) {
		var config = new Pamac.Config ("/etc/pamac.conf");
		config.enable_appstream = false;
		config.enable_snap = false;
		var database = new Pamac.Database (config);
		var transaction = new Pamac.Transaction (database);
		var loop = new MainLoop ();
		if (database.need_refresh ()) {
			transaction.refresh_dbs_async.begin (() => {
				loop.quit ();
			});
			loop.run ();
		}
		var updates = database.get_updates ();
		uint updates_nb = updates.repos_updates.length + updates.aur_updates.length + updates.flatpak_updates.length;
		if (updates_nb == 0) {
			return 0;
		} else {
			// refresh files dbs
			transaction.refresh_files_dbs_async.begin (() => {
				loop.quit ();
			});
			loop.run ();
			// download updates
			if (config.download_updates) {
				transaction.download_updates_async.begin (() => {
					loop.quit ();
				});
				loop.run ();
			}
			foreach (unowned Pamac.AlpmPackage pkg in updates.repos_updates) {
				// a replacer has no installed version
				print_update (details, "repo", pkg.name, pkg.installed_version, pkg.version, pkg.download_size);
			}
			foreach (unowned Pamac.AURPackage pkg in updates.aur_updates) {
				print_update (details, "aur", pkg.name, pkg.installed_version, pkg.version, 0);
			}
			foreach (unowned Pamac.FlatpakPackage pkg in updates.flatpak_updates) {
				unowned string? app_name = pkg.app_name;
				// the installed version is not printed for flatpaks
				print_update (details, "flatpak", app_name ?? pkg.name, null, pkg.version, pkg.download_size);
			}
			// special status when updates are available
			return 100;
		}
	}

	public int main (string[] args) {
		// --details: machine readable output for UpdatesChecker
		bool details = args.length > 1 && args[1] == "--details";
		return checkupdates (details);
	}
