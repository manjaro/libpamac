/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	// runs the operations in this process, see AlpmRunner
	internal class TransactionInterfaceRoot: Object, TransactionInterface {
		AlpmRunner runner;
		AlpmClient client;

		public TransactionInterfaceRoot (AlpmUtils alpm_utils, MainContext context, TransactionSink sink) {
			runner = new AlpmRunner (alpm_utils, context);
			client = new AlpmClient (sink);
		}

		public async bool get_authorization () {
			// we are root
			return true;
		}

		public void remove_authorization () {
			// we are root
		}

		public async void generate_mirrors_list (string country) throws Error {
			yield runner.generate_mirrors_list (client, country);
		}

		public async bool clean_cache (GenericArray<string> filenames) throws Error {
			return yield runner.clean_cache (client, filenames.data);
		}

		public async bool clean_build_files (string aur_build_dir) throws Error {
			return yield runner.clean_build_files (client, aur_build_dir, Posix.geteuid ());
		}

		public async bool set_pkgreason (string pkgname, uint reason) throws Error {
			return yield runner.set_pkgreason (client, pkgname, reason);
		}

		public async bool download_updates () throws Error {
			return yield runner.download_updates (client);
		}

		public async string[] download_pkgs (GenericArray<string> urls) throws Error {
			return yield runner.download_pkgs (client, urls.data);
		}

		// the refreshes interrupt the download of updates
		public async bool trans_refresh (bool force) throws Error {
			return yield runner.trans_refresh (client, force, true);
		}

		public async bool trans_refresh_files (bool force) throws Error {
			return yield runner.trans_refresh_files (client, force, true);
		}

		public async bool trans_refresh_aur (bool force) throws Error {
			return yield runner.trans_refresh_aur (client, force, true);
		}

		public async bool trans_run (TransactionRequest request) throws Error {
			return yield runner.trans_run (client, request);
		}

		public async bool snap_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove) {
			// not implemented
			return false;
		}

		public async bool snap_switch_channel (string snap_name, string channel) {
			// not implemented
			return false;
		}

		public async bool flatpak_trans_run (GenericArray<string> to_install, GenericArray<string> to_remove, GenericArray<string> to_upgrade) {
			// not implemented
			return false;
		}

		public void trans_cancel () {
			client.cancellable.cancel ();
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
