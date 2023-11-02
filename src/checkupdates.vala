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
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

	public int checkupdates () {
		var config = new Pamac.Config ("/etc/pamac.conf");
		config.enable_appstream = false;
		config.enable_snap = false;
		var database = new Pamac.Database (config);
		var updates = database.get_updates (true);
		uint updates_nb = updates.repos_updates.length + updates.aur_updates.length + updates.flatpak_updates.length;
		if (updates_nb == 0) {
			return 0;
		} else {
			// refresh tmp files dbs
			database.refresh_tmp_files_dbs ();
			// download updates
			if (config.download_updates) {
				var transaction = new Pamac.Transaction (database);
				var loop = new MainLoop ();
				transaction.download_updates_async.begin (() => {
					loop.quit ();
				});
				loop.run ();
			}
			foreach (unowned Pamac.AlpmPackage pkg in updates.repos_updates) {
				if (pkg.installed_version != null) {
					stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
				} else {
					// it's a replacer
					stdout.printf ("%s  %s\n", pkg.name, pkg.version);
				}
			}
			foreach (unowned Pamac.AURPackage pkg in updates.aur_updates) {
				stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
			}
			foreach (unowned Pamac.FlatpakPackage pkg in updates.flatpak_updates) {
				unowned string? app_name = pkg.app_name;
				if (app_name == null) {
					stdout.printf ("%s  %s\n", pkg.name, pkg.version);
				} else {
					stdout.printf ("%s  %s\n", app_name, pkg.version);
				}
			}
			// special status when updates are available
			return 100;
		}
	}

	public int main () {
		return checkupdates ();
	}
