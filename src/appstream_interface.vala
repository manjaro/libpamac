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
	internal interface AppstreamPlugin : Object {
		public abstract void load (GenericArray<string> repos_names);
		public abstract unowned GenericArray<HashTable<unowned string, App>> get_apps ();
		public abstract GenericArray<unowned App> search (string[] search_tokens);
		public abstract GenericArray<unowned App> get_pkgname_apps (string pkgname);
		public abstract HashTable<unowned string, unowned App> get_category_apps (string category);
	}

	internal abstract class App : Object {
		public abstract string? name { get; }
		public abstract string? id { get; }
		public abstract string? pkgname { get; }
		public abstract string? desc { get; }
		public abstract string? long_desc { get; }
		public abstract string? repo { get; }
		public abstract string? launchable { get; }
		public abstract string? icon { get; }
		public abstract GenericArray<string> screenshots { get; }
	}
}
