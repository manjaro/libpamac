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

namespace Pamac {
	internal interface AURPlugin : Object {
		public abstract void set_real_build_dir (string config_aur_build_dir);
		public abstract unowned string get_real_build_dir ();
		public abstract bool update_db (bool force_refresh, bool emit_signal);
		public abstract AURInfos? get_infos (string pkgname);
		public abstract GenericArray<unowned AURInfos> get_multi_infos (GenericArray<string> pkgnames);
		public abstract GenericArray<unowned AURInfos> get_providers (string depend);
		public abstract GenericArray<AURInfos> search (string search_string);

		public signal void emit_download_progress (string status, double progress);
		public signal void emit_download_error (string message);
	}

	internal abstract class AURInfos : Object {
		public abstract string name { get; }
		public abstract string version { get; }
		public abstract string? desc { get; }
		public abstract string? license { get; }
		public abstract string? url { get; }
		public abstract GenericArray<string> groups { get; }
		public abstract GenericArray<string> depends { get; }
		public abstract GenericArray<string> optdepends { get; }
		public abstract GenericArray<string> makedepends { get; }
		public abstract GenericArray<string> checkdepends { get; }
		public abstract GenericArray<string> provides { get; }
		public abstract GenericArray<string> replaces { get; }
		public abstract GenericArray<string> conflicts { get; }
		public abstract string? packagebase { get; }
		public abstract string? maintainer { get; }
		public abstract double popularity { get; }
		public abstract DateTime? lastmodified { get; }
		public abstract DateTime? outofdate { get; }
		public abstract DateTime? firstsubmitted { get; }
		public abstract uint64 numvotes { get; }
	}
}
