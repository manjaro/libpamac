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
	internal interface SnapPlugin : Object {
		public abstract void search_snaps (string search_string, ref GenericArray<SnapPackage> pkgs);
		public abstract bool is_installed_snap (string name);
		public abstract SnapPackage? get_snap (string name);
		public abstract SnapPackage? get_snap_by_app_id (string app_id);
		public abstract void get_installed_snaps (ref GenericArray<SnapPackage> pkgs);
		public abstract string get_installed_snap_icon (string name) throws Error;
		public abstract void get_category_snaps (string category, ref GenericArray<SnapPackage> pkgs);
		public abstract bool trans_run (TransactionSink sink, string[] to_install, string[] to_remove);
		public abstract bool switch_channel (TransactionSink sink, string name, string channel);
		// cancel the transaction if it reports to sink
		public abstract void trans_cancel (TransactionSink sink);
		public abstract void refresh ();
	}

	public abstract class SnapPackage : Package {
		public abstract string? channel { get; }
		public abstract string? publisher { get; }
		public abstract string? confined { get; }
		public abstract GenericArray<string> channels { get; }

		internal SnapPackage () {}
	}
}
