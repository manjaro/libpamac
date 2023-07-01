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
	public abstract class AlpmPackage : Package {
		// common
		unowned Database database;
		unowned Alpm.Package? alpm_pkg;
		unowned Alpm.Package? local_pkg;
		unowned Alpm.Package? sync_pkg;
		bool local_pkg_set;
		bool sync_pkg_set;
		bool installed_version_set;
		bool installed_size_set;
		bool download_size_set;
		bool install_date_set;
		bool reason_set;
		// Package
		App? _app;
		unowned string? _app_name;
		unowned string? _app_id;
		string? _installed_version;
		unowned string? _long_desc;
		uint64 _installed_size;
		uint64 _download_size;
		DateTime? _install_date;
		unowned string? _launchable;
		unowned string? _icon;
		GenericArray<string> _screenshots;
		// AlpmPackage
		DateTime? _build_date;
		string? _packager;
		unowned string? _reason;
		GenericArray<string> _validations;
		GenericArray<string> _requiredby;
		GenericArray<string> _optionalfor;
		GenericArray<string> _backups;
		GenericArray<string> _files;

		// Package
		public override string? app_name {
			get {
				if (_app_name == null && _app != null) {
					_app_name = _app.name;
				}
				return _app_name;
			}
		}
		public override string? app_id {
			get {
				if (_app_id == null && _app != null) {
					_app_id = _app.id;
				}
				return _app_id;
			}
		}
		public override string? installed_version {
			get {
				if (!installed_version_set) {
					installed_version_set = true;
					found_local_pkg ();
				_installed_version = local_pkg.version;
				}
				return _installed_version;
			}
			internal set { _installed_version = value; }
		}
		public override string? long_desc {
			get {
				if (_long_desc == null && _app != null) {
					_long_desc = _app.long_desc;
				}
				return _long_desc;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && _app != null) {
					_launchable = _app.launchable;
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null && _app != null) {
					_icon = _app.icon;
				}
				return _icon;
			}
		}
		public override uint64 installed_size {
			get {
				if (!installed_size_set) {
					installed_size_set = true;
					if (local_pkg != null) {
						_installed_size = local_pkg.isize;
					}
				}
				return _installed_size;
			}
		}
		public override uint64 download_size {
			get {
				if (!download_size_set) {
					download_size_set = true;
					if (alpm_pkg != null) {
						_download_size = alpm_pkg.download_size;
					}
				}
				return _download_size;
			}
		}
		public override DateTime? install_date {
			get {
				if (!install_date_set) {
					install_date_set = true;
					found_local_pkg ();
					if (local_pkg != null) {
						_install_date = new DateTime.from_unix_local (local_pkg.installdate);
					}
				}
				return _install_date;
			}
		}
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					if (_app != null) {
						_screenshots = _app.screenshots;
					} else {
						_screenshots = new GenericArray<string> ();
					}
				}
				return _screenshots;
			}
		}
		// AlpmPackage
		public DateTime? build_date {
			get {
				if (_build_date == null) {
					if (alpm_pkg != null) {
						_build_date = new DateTime.from_unix_local (alpm_pkg.builddate);
					}
				}
				return _build_date;
			}
		}
		public string? packager {
			get {
				if (_packager == null) {
					_packager = alpm_pkg.packager;
				}
				return _packager;
			}
			internal set { _packager = value; }
		}
		public string? reason {
			get {
				if (!reason_set) {
					reason_set = true;
					found_local_pkg ();
					if (local_pkg != null) {
						if (local_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
							_reason = dgettext (null, "Explicitly installed");
						} else if (local_pkg.reason == Alpm.Package.Reason.DEPEND) {
							_reason = dgettext (null, "Installed as a dependency for another package");
						}
					}
				}
				return _reason;
			}
		}
		public GenericArray<string> validations {
			get {
				if (_validations == null) {
					_validations = new GenericArray<string> ();
					Alpm.Package.Validation validation = alpm_pkg.validation;
					if (validation != 0) {
						if ((validation & Alpm.Package.Validation.NONE) != 0) {
							_validations.add (dgettext (null, "None"));
						} else {
							if ((validation & Alpm.Package.Validation.MD5SUM) != 0) {
								_validations.add (dgettext (null, "MD5 Sum"));
							}
							if ((validation & Alpm.Package.Validation.SHA256SUM) != 0) {
								_validations.add (dgettext (null, "SHA-256 Sum"));
							}
							if ((validation & Alpm.Package.Validation.SIGNATURE) != 0) {
								_validations.add (dgettext (null, "Signature"));
							}
						}
					} else {
						_validations.add (dgettext (null, "Unknown"));
					}
				}
				return _validations;
			}
		}
		public abstract GenericArray<string> groups { get; }
		public abstract GenericArray<string> depends { get; internal set; }
		public abstract GenericArray<string> optdepends { get; }
		public abstract GenericArray<string> makedepends { get; }
		public abstract GenericArray<string> checkdepends { get; }
		public GenericArray<string> requiredby {
			get {
				if (_requiredby == null) {
					_requiredby = new GenericArray<string> ();
					found_local_pkg ();
					if (local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_requiredby ();
						unowned Alpm.List<string*> list = owned_list;
						while (list != null) {
							_requiredby.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _requiredby;
			}
		}
		public GenericArray<string> optionalfor {
			get {
				if (_optionalfor == null) {
					_optionalfor = new GenericArray<string> ();
					found_local_pkg ();
					if (local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_optionalfor ();
						unowned Alpm.List<string*> list = owned_list;
						while (list != null) {
							_optionalfor.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _optionalfor;
			}
		}
		public abstract GenericArray<string> provides { get; internal set; }
		public abstract GenericArray<string> replaces { get; internal set; }
		public abstract GenericArray<string> conflicts { get; internal set; }
		public GenericArray<string> backups {
			get {
				if (_backups == null) {
					_backups = new GenericArray<string> ();
					found_local_pkg ();
					if (local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Backup> list = local_pkg.backups;
						while (list != null) {
							var builder = new StringBuilder ("/");
							builder.append (list.data.name);
							_backups.add ((owned) builder.str);
							list.next ();
						}
					}
				}
				return _backups;
			}
		}

		internal AlpmPackage () {}

		public unowned GenericArray<string> get_files () {
			if (_files == null) {
				found_local_pkg ();
				_files = database.get_pkg_files (name, local_pkg);
			}
			return _files;
		}

		public async unowned GenericArray<string> get_files_async () {
			if (_files == null) {
				found_local_pkg ();
				_files = yield database.get_pkg_files_async (name, local_pkg);
			}
			return _files;
		}


		internal void set_app (App? app) {
			_app = app;
		}

		internal unowned App? get_app () {
			return _app;
		}

		internal void set_database (Database database) {
			this.database = database;
		}

		internal void set_alpm_pkg (Alpm.Package? alpm_pkg) {
			this.alpm_pkg = alpm_pkg;
		}

		internal unowned Alpm.Package? get_alpm_pkg () {
			return alpm_pkg;
		}

		internal void set_local_pkg (Alpm.Package? local_pkg) {
			this.local_pkg = local_pkg;
			local_pkg_set = true;
		}

		internal unowned Alpm.Package? get_local_pkg () {
			return local_pkg;
		}

		internal void set_sync_pkg (Alpm.Package? sync_pkg) {
			this.sync_pkg = sync_pkg;
			sync_pkg_set = true;
		}

		internal unowned Alpm.Package? get_sync_pkg () {
			return sync_pkg;
		}

		internal void found_local_pkg () {
			if  (!local_pkg_set) {
				local_pkg_set = true;
				if (alpm_pkg != null) {
					if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
						local_pkg = alpm_pkg;
					} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
						local_pkg = database.intern_get_local_pkg (alpm_pkg.name);
					}
				}
			}
		}

		internal void found_sync_pkg () {
			if  (!sync_pkg_set) {
				sync_pkg_set = true;
				if (alpm_pkg != null) {
					if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
						sync_pkg = database.intern_get_syncpkg (alpm_pkg.name);
					} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
						sync_pkg = alpm_pkg;
					}
				}
			}
		}
	}

	internal class AlpmPackageLinked : AlpmPackage {
		// common
		bool version_set;
		bool repo_set;
		bool license_set;
		// Package
		string _name;
		string _id;
		string _version;
		string? _desc;
		string? _repo;
		string? _license;
		unowned string? _url;
		// AlpmPackage
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;

		// Package
		public override string name {
			get {
				if (_name == null) {
					_name = get_alpm_pkg ().name;
				}
				return _name;
			}
			internal set { _name = value; }
		}
		public override string id {
			get {
				if (_id == null) {
					unowned App? app = get_app ();
					if (app != null) {
						_id = "%s/%s".printf (name, app_name);
					} else {
						_id = name;
					}
				}
				return _id;
			}
			internal set { _id = value; }
		}
		public override string version {
			get {
				if (!version_set) {
					version_set = true;
					found_sync_pkg ();
					unowned Alpm.Package? sync_pkg = get_sync_pkg ();
					if (sync_pkg != null) {
						_version = sync_pkg.version;
					} else {
						_version = get_alpm_pkg ().version;
					}
				}
				return _version;
			}
			internal set { _version = value; }
		}
		public override string? desc {
			get {
				if (_desc == null) {
					unowned App? app = get_app ();
					if (app != null) {
						unowned string? summary = app.desc;
						if (summary != null) {
							_desc = summary;
						}
					} else {
						_desc = get_alpm_pkg ().desc;
					}
				}
				return _desc;
			}
			internal set { _desc = value; }
		}
		public override string? repo {
			get {
				if (!repo_set) {
					repo_set = true;
					found_sync_pkg ();
					unowned Alpm.Package? sync_pkg = get_sync_pkg ();
					if (sync_pkg != null) {
						unowned Alpm.DB? db = get_sync_pkg ().db;
						if (db != null) {
							_repo = db.name;
						}
					}
				}
				return _repo;
			}
			internal set { _repo = value; }
		}
		public override string? license {
			get {
				if (!license_set) {
					license_set = true;
					unowned Alpm.List<unowned string>? list = get_alpm_pkg ().licenses;
					if (list != null) {
						var license_str = new StringBuilder (list.data);
						list.next ();
						while (list != null) {
							license_str.append (" ");
							license_str.append (list.data);
							list.next ();
						}
						_license = (owned) license_str.str;
					} else {
						_license = dgettext (null, "Unknown");
					}
				}
				return _license;
			}
		}
		public override string? url {
			get {
				if (_url == null) {
					_url = get_alpm_pkg ().url;
				}
				return _url;
			}
		}
		public override GenericArray<string> groups {
			get {
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					unowned Alpm.List<unowned string> list = get_alpm_pkg ().groups;
					while (list != null) {
						_groups.add (list.data);
						list.next ();
					}
				}
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = get_alpm_pkg ().depends;
					while (list != null) {
						_depends.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = get_alpm_pkg ().optdepends;
					while (list != null) {
						_optdepends.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					unowned Alpm.Package? sync_pkg = get_sync_pkg ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = get_sync_pkg ().makedepends;
						while (list != null) {
							_makedepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					unowned Alpm.Package? sync_pkg = get_sync_pkg ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = get_sync_pkg ().checkdepends;
						while (list != null) {
							_checkdepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				return _checkdepends;
			}
		}
		public override GenericArray<string> provides {
			get {
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = get_alpm_pkg ().provides;
					while (list != null) {
						_provides.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = get_alpm_pkg ().replaces;
					while (list != null) {
						_replaces.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = get_alpm_pkg ().conflicts;
					while (list != null) {
						_conflicts.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}

		internal AlpmPackageLinked () {}

		internal AlpmPackageLinked.from_alpm (Alpm.Package? alpm_pkg, Database database) {
			set_alpm_pkg (alpm_pkg);
			set_database (database);
		}

		internal AlpmPackageLinked.populate_data (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			// id
			str = id;
			// desc
			str = desc;
			// version
			str = version;
			// repo
			str = repo;
			// license
			str = license;
			// packager
			str = packager;
			// installed size
			uint64 val = installed_size;
			// download size
			val = download_size;
			// build date
			DateTime date = build_date;
			unowned GenericArray<string> list;
			if (local_pkg != null) {
				// installed version
				str = installed_version;
				// installed date
				date = install_date;
				// reason
				str = reason;
				// requiredby
				list = requiredby;
				// optionalfor
				list = optionalfor;
				// backups
				list = backups;
			}
			if (sync_pkg != null) {
				// makedepends
				list =  makedepends;
				// checkdepends
				list = checkdepends;
			}
			// groups
			list = groups;
			// validations
			list = validations;
			// depends
			list = depends;
			// optdepends
			list = optdepends;
			// provides
			list = provides;
			// replaces
			list = replaces;
			// conflicts
			list = conflicts;
			// unset pkgs
			set_alpm_pkg (null);
			set_local_pkg (null);
			set_sync_pkg (null);
		}

		internal AlpmPackageLinked.transaction (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			// version
			str = version;
			// desc
			str = desc;
			uint64 val = installed_size;
			val = download_size;
			if (local_pkg != null) {
				// installed version
				str = installed_version;
				// installed date
				DateTime date = install_date;
			}
			if (sync_pkg != null) {
				// repo
				// transaction pkg
				if (get_sync_pkg ().db.name == "pamac_aur") {
					repo = dgettext (null, "AUR");
				} else {
					str = repo;
				}
			}
			// provides
			unowned GenericArray<string> list = provides;
			// unset pkgs
			set_alpm_pkg (null);
			set_local_pkg (null);
			set_sync_pkg (null);
		}
	}

	public class AURPackage : AlpmPackage {
		// common
		AURInfos? aur_infos;
		bool is_update;
		bool license_set;
		// Package
		string _name;
		string _id;
		string _version;
		string? _desc;
		unowned string? _repo;
		string? _license;
		unowned string? _url;
		// AlpmPackage
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		// AURInfos
		string? _packagebase;
		unowned string? _maintainer;
		double _popularity;
		DateTime _lastmodified;
		DateTime? _outofdate;
		DateTime _firstsubmitted;
		uint64 _numvotes;

		// Package
		public override string name {
			get {
				if (_name == null && aur_infos != null) {
					_name = aur_infos.name;
				}
				return _name;
			}
			internal set { _name = value; }
		}
		public override string id {
			get {
				if (_id == null && aur_infos != null) {
					_id = aur_infos.name;
				}
				return _id;
			}
			internal set { _id = value; }
		}
		public override string version {
			get {
				if (_version == null && aur_infos != null) {
					_version = aur_infos.version;
				}
				return _version;
			}
			internal set { _version = value; }
		}
		public override string? desc {
			get {
				if (_desc == null) {
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						_desc = local_pkg.desc;
					} else if (aur_infos != null) {
						_desc = aur_infos.desc;
					}
				}
				return _desc;
			}
			internal set { _desc = value; }
		}
		public override string? repo {
			get {
				if (_repo == null) {
					_repo = dgettext (null, "AUR");
				}
				return _repo;
			}
			internal set { _repo = value; }
		}
		public override string? license {
			get {
				if (_license == null && !license_set) {
					license_set = true;
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned string>? list = local_pkg.licenses;
						if (list != null) {
							var license_str = new StringBuilder (list.data);
							list.next ();
							while (list != null) {
								license_str.append (" ");
								license_str.append (list.data);
								list.next ();
							}
							_license = (owned) license_str.str;
						} else {
							_license = dgettext (null, "Unknown");
						}
					} else if (aur_infos != null) {
						_license = aur_infos.license;
					}
				}
				return _license;
			}
		}
		public override string? url {
			get {
				if (_url == null) {
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						_url = local_pkg.url;
					} else if (aur_infos != null) {
						_url = aur_infos.url;
					}
				}
				return _url;
			}
		}
		public override GenericArray<string> groups {
			get {
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned string> list = local_pkg.groups;
						while (list != null) {
							_groups.add (list.data);
							list.next ();
						}
					} else if (aur_infos != null) {
						_groups = aur_infos.groups;
					}
				}
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.depends;
						while (list != null) {
							_depends.add (list.data.compute_string ());
							list.next ();
						}
					} else if (aur_infos != null) {
						_depends = aur_infos.depends;
					}
				}
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.optdepends;
						while (list != null) {
							_optdepends.add (list.data.compute_string ());
							list.next ();
						}
					} else if (aur_infos != null) {
						_optdepends = aur_infos.optdepends;
					}
				}
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					if (aur_infos != null) {
						_makedepends = aur_infos.makedepends;
					}
				}
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					if (aur_infos != null) {
						_checkdepends = aur_infos.checkdepends;
					}
				}
				return _checkdepends;
			}
		}
		public override GenericArray<string> provides {
			get {
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.provides;
						while (list != null) {
							_provides.add (list.data.compute_string ());
							list.next ();
						}
					} else if (aur_infos != null) {
						_provides = aur_infos.provides;
					}
				}
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.replaces;
						while (list != null) {
							_replaces.add (list.data.compute_string ());
							list.next ();
						}
					} else if (aur_infos != null) {
						_replaces = aur_infos.replaces;
					}
				}
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					unowned Alpm.Package? local_pkg = get_local_pkg ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.conflicts;
						while (list != null) {
							_conflicts.add (list.data.compute_string ());
							list.next ();
						}
					} else if (aur_infos != null) {
						_conflicts = aur_infos.conflicts;
					}
				}
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}
		// AURInfos
		public string? packagebase {
			get {
				if (_packagebase == null && aur_infos != null) {
					_packagebase = aur_infos.packagebase;
				}
				return _packagebase;
			}
			internal set { _packagebase = value; }
		}
		public string? maintainer {
			get {
				if (_maintainer == null && aur_infos != null) {
					_maintainer = aur_infos.maintainer;
				}
				return _maintainer;
			}
		}
		public double popularity {
			get {
				if (_popularity == 0 && aur_infos != null) {
					_popularity = aur_infos.popularity;
				}
				return _popularity;
			}
		}
		public DateTime? lastmodified {
			get {
				if (_lastmodified == null && aur_infos != null) {
					_lastmodified = aur_infos.lastmodified;
				}
				return _lastmodified;
			}
		}
		public DateTime? outofdate {
			get {
				if (_outofdate == null && aur_infos != null) {
					_outofdate =aur_infos.outofdate;
				}
				return _outofdate;
			}
		}
		public DateTime? firstsubmitted {
			get {
				if (_firstsubmitted == null && aur_infos != null) {
					_firstsubmitted = aur_infos.firstsubmitted;
				}
				return _firstsubmitted;
			}
		}
		public uint64 numvotes {
			get {
				if (_numvotes == 0) {
					_numvotes = aur_infos.numvotes;
				}
				return _numvotes;
			}
		}

		internal AURPackage () {}

		internal void initialise_from_aur_infos (AURInfos? aur_infos, Alpm.Package? local_pkg, bool is_update = false) {
			this.aur_infos = aur_infos;
			set_alpm_pkg (local_pkg);
			set_local_pkg (local_pkg);
			this.is_update = is_update;
		}
	}

	public class TransactionSummary : Object {
		public GenericArray<Package> to_install { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_upgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_downgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_reinstall { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> conflicts_to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_build { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<string> aur_pkgbases_to_build { internal get; internal set; default = new GenericArray<string> (); }
		public GenericArray<string> to_load { internal get; internal set; default = new GenericArray<string> (); }

		internal TransactionSummary () {}
	}

	public class Updates : Object {
		public GenericArray<AlpmPackage> repos_updates { get; internal set; default = new GenericArray<AlpmPackage> (); }
		public GenericArray<AlpmPackage> ignored_repos_updates { get; internal set; default = new GenericArray<AlpmPackage> (); }
		public GenericArray<AURPackage> aur_updates { get; internal set; default = new GenericArray<AURPackage> (); }
		public GenericArray<AURPackage> ignored_aur_updates { get; internal set; default = new GenericArray<AURPackage> (); }
		public GenericArray<AURPackage> outofdate { get; internal set; default = new GenericArray<AURPackage> (); }
		public GenericArray<FlatpakPackage> flatpak_updates { get; internal set; default = new GenericArray<FlatpakPackage> (); }

		internal Updates () {}
	}
}
