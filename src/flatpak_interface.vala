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
	// the transactions report their progress to the given sink
	internal interface FlatpakPlugin : Object {
		public abstract uint64 refresh_period { get; set; }

		public abstract bool refresh_appstream_data ();
		public abstract void load_appstream_data ();
		public abstract void get_remotes_names (ref GenericArray<string> remotes_names);
		public abstract void search_flatpaks (string search_string, ref GenericArray<FlatpakPackage> pkgs);
		public abstract bool is_installed_flatpak (string name);
		public abstract FlatpakPackage? get_flatpak_by_app_id (string app_id);
		public abstract FlatpakPackage? get_flatpak (string id);
		public abstract void get_installed_flatpaks (ref GenericArray<FlatpakPackage> pkgs);
		public abstract void get_category_flatpaks (string category, ref GenericArray<FlatpakPackage> pkgs);
		public abstract void get_flatpak_updates (ref GenericArray<FlatpakPackage> pkgs);
		public abstract bool trans_run (TransactionSink sink, string[] to_install, string[] to_remove, string[] to_upgrade);
		// cancel the transaction if it reports to sink
		public abstract void trans_cancel (TransactionSink sink);
		public abstract void refresh ();
	}

	public abstract class FlatpakPackage : Package {
		public override PackageSource source { get { return PackageSource.FLATPAK; } }

		internal FlatpakPackage () {}
	}
}
