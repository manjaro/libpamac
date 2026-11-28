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
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {
	public abstract class AlpmPackage : Package {
		public override PackageSource source {
			get {
				unowned string? pkg_repo = repo;
				if (pkg_repo == null) {
					return PackageSource.LOCAL;
				}
				// installed packages found in the AUR have the AUR as repo
				if (pkg_repo == dgettext (null, "AUR")) {
					return PackageSource.AUR;
				}
				return PackageSource.REPO;
			}
		}
		// AlpmPackage
		public abstract DateTime? build_date { get; }
		public abstract string? packager { get; }
		public abstract string? reason { get; }
		public abstract GenericArray<string> validations { get; }
		public abstract GenericArray<string> groups { get; }
		public abstract GenericArray<string> depends { get; internal set; }
		public abstract GenericArray<string> optdepends { get; }
		public abstract GenericArray<string> makedepends { get; }
		public abstract GenericArray<string> checkdepends { get; }
		public abstract GenericArray<string> requiredby { get; }
		public abstract GenericArray<string> optionalfor { get; }
		public abstract GenericArray<string> provides { get; internal set; }
		public abstract GenericArray<string> replaces { get; internal set; }
		public abstract GenericArray<string> conflicts { get; internal set; }
		public abstract GenericArray<string> backups { get; }

		internal AlpmPackage () {}

		public abstract unowned GenericArray<string> get_files ();

		public abstract async unowned GenericArray<string> get_files_async ();
	}

	// libalpm is not thread safe and loads data lazily: one recursive lock
	// for all the handles of a Database, also taken by the packages accessors
	internal class AlpmLock {
		RecMutex mutex;

		public AlpmLock () {
			mutex = RecMutex ();
		}

		public void acquire () {
			mutex.lock ();
		}

		public void release () {
			mutex.unlock ();
		}
	}

	// owns an alpm handle: packages created from it keep a reference,
	// so their alpm data stay valid after Database.refresh () replaced the handle
	internal class AlpmHandleRef {
		public Alpm.Handle handle;
		public AlpmLock alpm_lock;

		public AlpmHandleRef (owned Alpm.Handle handle, AlpmLock alpm_lock) {
			this.handle = (owned) handle;
			this.alpm_lock = alpm_lock;
		}

		// the lock must be held
		public unowned Alpm.Package? get_local_pkg (string pkgname) {
			return handle.localdb.get_pkg (pkgname);
		}

		// the lock must be held
		public unowned Alpm.Package? get_sync_pkg (string pkgname) {
			unowned Alpm.List<unowned Alpm.DB> syncdbs = handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.Package? pkg = syncdbs.data.get_pkg (pkgname);
				if (pkg != null) {
					return pkg;
				}
				syncdbs.next ();
			}
			return null;
		}

		// files of pkg, which comes from this handle
		public GenericArray<string> get_pkg_files (Alpm.Package pkg) {
			var files = new GenericArray<string> ();
			alpm_lock.acquire ();
			Database.add_pkg_files (handle.root, pkg, files);
			alpm_lock.release ();
			return files;
		}
	}

	internal class AlpmPackageLinked : AlpmPackage {
		// Package
		string _name;
		string _id;
		unowned string _version;
		unowned string? _installed_version;
		unowned string? _desc;
		unowned string? _repo;
		string? _license;
		unowned string? _url;
		uint64 _installed_size;
		uint64 _download_size;
		DateTime? _install_date;
		// App
		App? _app;
		unowned string? _app_name;
		unowned string? _app_id;
		unowned string? _long_desc;
		unowned string? _launchable;
		unowned string? _icon;
		GenericArray<string> _screenshots;
		// AlpmPackage
		WeakRef database;
		// the handle of alpm_pkg, local_pkg and sync_pkg, null for static packages
		AlpmHandleRef? handle_ref;
		unowned Alpm.Package? alpm_pkg;
		unowned Alpm.Package? local_pkg;
		unowned Alpm.Package? sync_pkg;
		bool local_pkg_set;
		bool sync_pkg_set;
		bool version_set;
		bool installed_version_set;
		bool repo_set;
		bool license_set;
		bool install_date_set;
		bool download_size_set;
		bool installed_size_set;
		bool reason_set;
		DateTime? _build_date;
		unowned string? _packager;
		unowned string? _reason;
		GenericArray<string> _validations;
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _requiredby;
		GenericArray<string> _optionalfor;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		GenericArray<string> _backups;
		GenericArray<string> _files;

		// Package
		public override string name {
			get {
				lock_alpm ();
				if (_name == null) {
					_name = alpm_pkg.name;
				}
				unlock_alpm ();
				return _name;
			}
			internal set { _name = value; }
		}
		public override string id {
			get {
				if (_id == null) {
					if (_app != null) {
						_id = app_id;
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
				lock_alpm ();
				if (!version_set) {
					version_set = true;
					found_sync_pkg ();
					if (sync_pkg != null) {
						_version = sync_pkg.version;
					} else {
						_version = alpm_pkg.version;
					}
				}
				unlock_alpm ();
				return _version;
			}
			internal set { _version = value; }
		}
		public override string? installed_version {
			get {
				lock_alpm ();
				if (!installed_version_set) {
					installed_version_set = true;
					found_local_pkg ();
					_installed_version = local_pkg.version;
				}
				unlock_alpm ();
				return _installed_version;
			}
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get {
				lock_alpm ();
				if (_desc == null) {
					if (_app != null) {
						unowned string? summary = _app.desc;
						if (summary != null) {
							_desc = summary;
						} else {
							_desc = alpm_pkg.desc;
						}
					} else {
						_desc = alpm_pkg.desc;
					}
				}
				unlock_alpm ();
				return _desc;
			}
			internal set { _desc = value; }
		}
		public override string? repo {
			get {
				lock_alpm ();
				if (!repo_set) {
					repo_set = true;
					found_sync_pkg ();
					unowned Alpm.DB? db = sync_pkg.db;
					if (db != null) {
						_repo = db.name;
					}
				}
				unlock_alpm ();
				return _repo;
			}
			internal set { _repo = value; }
		}
		public override string? license {
			get {
				lock_alpm ();
				if (!license_set) {
					license_set = true;
					unowned Alpm.List<unowned string>? list = alpm_pkg.licenses;
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
				unlock_alpm ();
				return _license;
			}
		}
		public override string? url {
			get {
				lock_alpm ();
				if (_url == null) {
					_url = alpm_pkg.url;
				}
				unlock_alpm ();
				return _url;
			}
		}
		public override uint64 installed_size {
			get {
				lock_alpm ();
				if (_installed_size == 0 && !installed_size_set) {
					installed_size_set = true;
					_installed_size = alpm_pkg.isize;
				}
				unlock_alpm ();
				return _installed_size;
			}
		}
		public override uint64 download_size {
			get {
				lock_alpm ();
				if (!download_size_set) {
					download_size_set = true;
					_download_size = alpm_pkg.download_size;
				}
				unlock_alpm ();
				return _download_size;
			}
		}
		public override DateTime? install_date {
			get {
				lock_alpm ();
				if (!install_date_set) {
					install_date_set = true;
					found_local_pkg ();
					if (local_pkg != null) {
						_install_date = new DateTime.from_unix_local (local_pkg.installdate);
					}
				}
				unlock_alpm ();
				return _install_date;
			}
		}
		// App
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
		public override DateTime? build_date {
			get {
				lock_alpm ();
				if (_build_date == null) {
					_build_date = new DateTime.from_unix_local (alpm_pkg.builddate);
				}
				unlock_alpm ();
				return _build_date;
			}
		}
		public override string? packager {
			get {
				lock_alpm ();
				if (_packager == null) {
					_packager = alpm_pkg.packager;
				}
				unlock_alpm ();
				return _packager;
			}
		}
		public override string? reason {
			get {
				lock_alpm ();
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
				unlock_alpm ();
				return _reason;
			}
		}
		public override GenericArray<string> validations {
			get {
				lock_alpm ();
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
				unlock_alpm ();
				return _validations;
			}
		}
		public override GenericArray<string> groups {
			get {
				lock_alpm ();
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					unowned Alpm.List<unowned string> list = alpm_pkg.groups;
					while (list != null) {
						_groups.add (list.data);
						list.next ();
					}
				}
				unlock_alpm ();
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				lock_alpm ();
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.depends;
					while (list != null) {
						_depends.add (list.data.compute_string ());
						list.next ();
					}
				}
				unlock_alpm ();
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				lock_alpm ();
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.optdepends;
					while (list != null) {
						_optdepends.add (list.data.compute_string ());
						list.next ();
					}
				}
				unlock_alpm ();
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				lock_alpm ();
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = sync_pkg.makedepends;
						while (list != null) {
							_makedepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				unlock_alpm ();
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				lock_alpm ();
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = sync_pkg.checkdepends;
						while (list != null) {
							_checkdepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				unlock_alpm ();
				return _checkdepends;
			}
		}
		public override GenericArray<string> requiredby {
			get {
				lock_alpm ();
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
				unlock_alpm ();
				return _requiredby;
			}
		}
		public override GenericArray<string> optionalfor {
			get {
				lock_alpm ();
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
				unlock_alpm ();
				return _optionalfor;
			}
		}
		public override GenericArray<string> provides {
			get {
				lock_alpm ();
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.provides;
					while (list != null) {
						_provides.add (list.data.compute_string ());
						list.next ();
					}
				}
				unlock_alpm ();
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				lock_alpm ();
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.replaces;
					while (list != null) {
						_replaces.add (list.data.compute_string ());
						list.next ();
					}
				}
				unlock_alpm ();
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				lock_alpm ();
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.conflicts;
					while (list != null) {
						_conflicts.add (list.data.compute_string ());
						list.next ();
					}
				}
				unlock_alpm ();
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}
		public override GenericArray<string> backups {
			get {
				lock_alpm ();
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
				unlock_alpm ();
				return _backups;
			}
		}

		internal AlpmPackageLinked () {}

		internal AlpmPackageLinked.from_alpm (Alpm.Package? alpm_pkg, Database database, AlpmHandleRef handle_ref) {
			this.alpm_pkg = alpm_pkg;
			this.database = WeakRef (database);
			this.handle_ref = handle_ref;
		}

		internal void set_alpm_pkg (Alpm.Package? alpm_pkg) {
			this.alpm_pkg = alpm_pkg;
		}

		internal void set_local_pkg (Alpm.Package? local_pkg) {
			this.local_pkg = local_pkg;
			local_pkg_set = true;
		}

		internal void set_sync_pkg (Alpm.Package? sync_pkg) {
			this.sync_pkg = sync_pkg;
			sync_pkg_set = true;
		}

		// static packages have no handle, their data are already computed
		void lock_alpm () {
			if (handle_ref != null) {
				handle_ref.alpm_lock.acquire ();
			}
		}

		void unlock_alpm () {
			if (handle_ref != null) {
				handle_ref.alpm_lock.release ();
			}
		}

		void found_local_pkg () {
			lock_alpm ();
			if (!local_pkg_set) {
				local_pkg_set = true;
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					local_pkg = alpm_pkg;
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					local_pkg = handle_ref.get_local_pkg (alpm_pkg.name);
				}
			}
			unlock_alpm ();
		}

		void found_sync_pkg () {
			lock_alpm ();
			if (!sync_pkg_set) {
				sync_pkg_set = true;
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					sync_pkg = handle_ref.get_sync_pkg (alpm_pkg.name);
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					sync_pkg = alpm_pkg;
				}
			}
			unlock_alpm ();
		}

		public override unowned GenericArray<string> get_files () {
			if (_files == null) {
				found_local_pkg ();
				var db = database.get () as Database;
				if (db != null) {
					_files = db.get_pkg_files (name, local_pkg);
				} else if (local_pkg != null) {
					_files = handle_ref.get_pkg_files (local_pkg);
				} else {
					_files = new GenericArray<string> ();
				}
			}
			return _files;
		}

		public override async unowned GenericArray<string> get_files_async () {
			if (_files == null) {
				found_local_pkg ();
				var db = database.get () as Database;
				if (db != null) {
					_files = yield db.get_pkg_files_async (name, local_pkg);
				} else if (local_pkg != null) {
					_files = handle_ref.get_pkg_files (local_pkg);
				} else {
					_files = new GenericArray<string> ();
				}
			}
			return _files;
		}

		internal void set_app (App? app) {
			_app = app;
		}
	}

	internal class AlpmPackageStatic : AlpmPackageLinked {
		// Package
		string _version;
		string? _installed_version;
		string? _desc;
		string? _repo;
		string? _url;
		// AlpmPackage
		string? _packager;

		// Package
		public override string version {
			get { return _version; }
			internal set { _version = value; }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get { return _desc; }
			internal set { _desc = value; }
		}
		public override string? repo {
			get { return _repo; }
			internal set { _repo = value; }
		}
		public override string? url { get { return _url; } }
		// AlpmPackage
		public override string? packager { get { return _packager; } }

		internal AlpmPackageStatic (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// version
			_version = alpm_pkg.version;
			// desc
			_desc = alpm_pkg.desc;
			// url
			_url = alpm_pkg.url;
			// packager
			_packager = alpm_pkg.packager;
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			// id
			str = id;
			// license
			str = license;
			// installed size
			uint64 val = installed_size;
			// download size
			val = download_size;
			// build date
			DateTime date = build_date;
			if (local_pkg != null) {
				// installed version
				_installed_version = local_pkg.version;
				// installed date
				date = install_date;
				// reason
				str = reason;
				// requiredby
				unowned GenericArray<string> list = requiredby;
				// optionalfor
				list = optionalfor;
				// backups
				list = backups;
			}
			if (sync_pkg != null) {
				// overwrite version
				_version = sync_pkg.version;
				// repo
				_repo = sync_pkg.db.name;
				// makedepends
				unowned GenericArray<string> list = makedepends;
				// checkdepends
				list = checkdepends;
			}
			// groups
			unowned GenericArray<string> list = groups;
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

		internal AlpmPackageStatic.transaction (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			str = null;
			// version
			_version = alpm_pkg.version;
			// desc
			_desc = alpm_pkg.desc;
			// url
			_url = alpm_pkg.url;
			uint64 val = installed_size;
			val = download_size;
			if (local_pkg != null) {
				// installed version
				_installed_version = local_pkg.version;
				// installed date
				DateTime date = install_date;
				date = null;
			}
			if (sync_pkg != null) {
				// repo
				// transaction pkg
				if (sync_pkg.db.name == "pamac_aur") {
					_repo = dgettext (null, "AUR");
				} else {
					_repo = sync_pkg.db.name;
				}
			}
			// provides
			unowned GenericArray<string> list = provides;
			list = null;
			// unset pkgs
			set_alpm_pkg (null);
			set_local_pkg (null);
			set_sync_pkg (null);
		}
	}

	public abstract class AURPackage : AlpmPackage {
		public override PackageSource source { get { return PackageSource.AUR; } }
		public abstract string? packagebase { get; internal set; }
		public abstract string? maintainer { get; }
		public abstract double popularity { get; }
		public abstract DateTime? lastmodified { get; }
		public abstract DateTime? outofdate { get; }
		public abstract DateTime? firstsubmitted { get; }
		public abstract uint64 numvotes  { get; }

		internal AURPackage () {}
	}

	internal class AURPackageLinked : AURPackage {
		// Package
		bool installed_version_set;
		bool install_date_set;
		bool installed_size_set;
		bool download_size_set;
		bool license_set;
		bool reason_set;
		bool packager_set;
		bool build_date_set;
		string _name;
		string _id;
		string _version;
		unowned string? _installed_version;
		unowned string? _desc;
		unowned string? _repo;
		string? _license;
		unowned string? _url;
		uint64 _installed_size;
		uint64 _download_size;
		DateTime? _install_date;
		// AlpmPackage
		unowned Alpm.Package? local_pkg;
		// the handle of local_pkg
		AlpmHandleRef? handle_ref;
		WeakRef database;
		DateTime? _build_date;
		unowned string? _packager;
		unowned string? _reason;
		GenericArray<string> _validations;
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _requiredby;
		GenericArray<string> _optionalfor;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		GenericArray<string> _backups;
		GenericArray<string> _files;
		// App
		GenericArray<string> _screenshots;
		// AURInfos
		AURInfos? aur_infos;
		bool is_update;
		unowned string? _packagebase;
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
		public override string? installed_version {
			get {
				lock_alpm ();
				if (!installed_version_set) {
					installed_version_set = true;
					if (local_pkg != null) {
						_installed_version = local_pkg.version;
					}
				}
				unlock_alpm ();
				return _installed_version;
			}
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get {
				lock_alpm ();
				if (_desc == null) {
					if (!is_update && local_pkg != null) {
						_desc = local_pkg.desc;
					} else if (aur_infos != null) {
						_desc = aur_infos.desc;
					}
				}
				unlock_alpm ();
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
				lock_alpm ();
				if (_license == null && !license_set) {
					license_set = true;
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
				unlock_alpm ();
				return _license;
			}
		}
		public override string? url {
			get {
				lock_alpm ();
				if (_url == null) {
					if (!is_update && local_pkg != null) {
						_url = local_pkg.url;
					} else if (aur_infos != null) {
						_url = aur_infos.url;
					}
				}
				unlock_alpm ();
				return _url;
			}
		}
		public override uint64 installed_size {
			get {
				lock_alpm ();
				if (!installed_size_set) {
					installed_size_set = true;
					if (local_pkg != null) {
						_installed_size = local_pkg.isize;
					}
				}
				unlock_alpm ();
				return _installed_size;
			}
		}
		public override uint64 download_size {
			get {
				lock_alpm ();
				if (!download_size_set) {
					download_size_set = true;
					if (local_pkg != null) {
						_download_size = local_pkg.download_size;
					}
				}
				unlock_alpm ();
				return _download_size;
			}
		}
		public override DateTime? install_date {
			get {
				lock_alpm ();
				if (!install_date_set) {
					install_date_set = true;
					if (local_pkg != null) {
						_install_date = new DateTime.from_unix_local (local_pkg.installdate);
					}
				}
				unlock_alpm ();
				return _install_date;
			}
		}
		// App
		public override string? app_name { get { return null; } }
		public override string? app_id { get { return null; } }
		public override string? long_desc { get { return null; } }
		public override string? launchable { get { return null; } }
		public override string? icon { get { return null; } }
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
				}
				return _screenshots;
			}
		}
		// AlpmPackage
		public override DateTime? build_date {
			get {
				lock_alpm ();
				if (!build_date_set) {
					build_date_set = true;
					if (local_pkg != null) {
						_build_date = new DateTime.from_unix_local (local_pkg.builddate);
					}
				}
				unlock_alpm ();
				return _build_date;
			}
		}
		public override string? packager {
			get {
				lock_alpm ();
				if (!packager_set) {
					packager_set = true;
					if (local_pkg != null) {
						_packager = local_pkg.packager;
					}
				}
				unlock_alpm ();
				return _packager;
			}
		}
		public override string? reason {
			get {
				lock_alpm ();
				if (!reason_set) {
					reason_set = true;
					if (local_pkg != null) {
						if (local_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
							_reason = dgettext (null, "Explicitly installed");
						} else if (local_pkg.reason == Alpm.Package.Reason.DEPEND) {
							_reason = dgettext (null, "Installed as a dependency for another package");
						}
					}
				}
				unlock_alpm ();
				return _reason;
			}
		}
		public override GenericArray<string> validations {
			get {
				lock_alpm ();
				if (_validations == null) {
					_validations = new GenericArray<string> ();
					if (local_pkg != null) {
						Alpm.Package.Validation validation = local_pkg.validation;
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
					} else {
						_validations.add (dgettext (null, "Unknown"));
					}
				}
				unlock_alpm ();
				return _validations;
			}
		}
		public override GenericArray<string> groups {
			get {
				lock_alpm ();
				if (_groups == null) {
					_groups = new GenericArray<string> ();
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
				unlock_alpm ();
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				lock_alpm ();
				if (_depends == null) {
					_depends = new GenericArray<string> ();
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
				unlock_alpm ();
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				lock_alpm ();
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
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
				unlock_alpm ();
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
		public override GenericArray<string> requiredby {
			get {
				lock_alpm ();
				if (_requiredby == null) {
					_requiredby = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_requiredby ();
						unowned Alpm.List<string*> list = owned_list;
						while (list != null) {
							_requiredby.add ((owned) list.data);
							list.next ();
						}
					}
				}
				unlock_alpm ();
				return _requiredby;
			}
		}
		public override GenericArray<string> optionalfor {
			get {
				lock_alpm ();
				if (_optionalfor == null) {
					_optionalfor = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_optionalfor ();
						unowned Alpm.List<string*> list = owned_list;
						while (list != null) {
							_optionalfor.add ((owned) list.data);
							list.next ();
						}
					}
				}
				unlock_alpm ();
				return _optionalfor;
			}
		}
		public override GenericArray<string> provides {
			get {
				lock_alpm ();
				if (_provides == null) {
					_provides = new GenericArray<string> ();
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
				unlock_alpm ();
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				lock_alpm ();
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
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
				unlock_alpm ();
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				lock_alpm ();
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
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
				unlock_alpm ();
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}
		public override GenericArray<string> backups {
			get {
				lock_alpm ();
				if (_backups == null) {
					_backups = new GenericArray<string> ();
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
				unlock_alpm ();
				return _backups;
			}
		}
		// AURInfos
		public override string? packagebase {
			get {
				if (_packagebase == null && aur_infos != null) {
					_packagebase = aur_infos.packagebase;
				}
				return _packagebase;
			}
			internal set { _packagebase = value; }
		}
		public override string? maintainer {
			get {
				if (_maintainer == null && aur_infos != null) {
					_maintainer = aur_infos.maintainer;
				}
				return _maintainer;
			}
		}
		public override double popularity {
			get {
				if (_popularity == 0 && aur_infos != null) {
					_popularity = aur_infos.popularity;
				}
				return _popularity;
			}
		}
		public override DateTime? lastmodified {
			get {
				if (_lastmodified == null && aur_infos != null) {
					_lastmodified = aur_infos.lastmodified;
				}
				return _lastmodified;
			}
		}
		public override DateTime? outofdate {
			get {
				if (_outofdate == null && aur_infos != null) {
					_outofdate = aur_infos.outofdate;
				}
				return _outofdate;
			}
		}
		public override DateTime? firstsubmitted {
			get {
				if (_firstsubmitted == null && aur_infos != null) {
					_firstsubmitted = aur_infos.firstsubmitted;
				}
				return _firstsubmitted;
			}
		}
		public override uint64 numvotes {
			get {
				if (_numvotes == 0) {
					_numvotes = aur_infos.numvotes;
				}
				return _numvotes;
			}
		}

		internal AURPackageLinked () {}

		internal void initialise_from_aur_infos (AURInfos? aur_infos, Alpm.Package? local_pkg, Database database, AlpmHandleRef handle_ref, bool is_update = false) {
			this.aur_infos = aur_infos;
			this.local_pkg = local_pkg;
			this.database = WeakRef (database);
			this.handle_ref = handle_ref;
			this.is_update = is_update;
		}

		void lock_alpm () {
			if (handle_ref != null) {
				handle_ref.alpm_lock.acquire ();
			}
		}

		void unlock_alpm () {
			if (handle_ref != null) {
				handle_ref.alpm_lock.release ();
			}
		}

		public override unowned GenericArray<string> get_files () {
			if (_files == null) {
				if (local_pkg == null) {
					_files = new GenericArray<string> ();
				} else {
					_files = handle_ref.get_pkg_files (local_pkg);
				}
			}
			return _files;
		}

		public override async unowned GenericArray<string> get_files_async () {
			if (_files == null) {
				if (local_pkg == null) {
					_files = new GenericArray<string> ();
				} else {
					// reading the files list can be slow
					var db = database.get () as Database;
					if (db != null) {
						_files = yield db.get_pkg_files_async (local_pkg.name, local_pkg);
					} else {
						_files = handle_ref.get_pkg_files (local_pkg);
					}
				}
			}
			return _files;
		}
	}

	internal class AURPackageStatic : AURPackageLinked {
		// Package
		string? _desc;
		// AURPackage
		string? _packagebase;

		// Package
		public override string? desc {
			get { return _desc; }
			internal set { _desc = value; }
		}
		// AURPackage
		public override string? packagebase {
			get { return _packagebase; }
			internal set { _packagebase = value; }
		}

		internal AURPackageStatic () {}
	}

	// why a package is in a transaction summary
	public enum SummaryReason {
		// explicitly requested, or part of a system upgrade
		REQUESTED,
		// new dependency of the related package
		DEPENDENCY,
		// replaces the related package
		REPLACE,
		// removed because it conflicts with the related package
		CONFLICT,
		// removed because it depends on the related package which is removed
		DEPENDS_ON_REMOVED,
		// removed because it is no longer required since the related package is removed
		ORPHAN
	}

	public class SummaryItem : Object {
		public Package pkg { get; internal set; }
		public SummaryReason reason { get; internal set; default = SummaryReason.REQUESTED; }
		// the package which explains the reason, null for REQUESTED
		public string? related { get; internal set; }
		// installed size of the version currently installed, 0 if it is not installed
		public uint64 old_installed_size { get; internal set; }

		internal SummaryItem (Package pkg, SummaryReason reason, string? related, uint64 old_installed_size) {
			Object (pkg: pkg, reason: reason, related: related, old_installed_size: old_installed_size);
		}
	}

	public class TransactionSummary : Object {
		HashTable<string, SummaryItem> items = new HashTable<string, SummaryItem> (str_hash, str_equal);
		public GenericArray<Package> to_install { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_upgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_downgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_reinstall { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> conflicts_to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_build { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<string> aur_pkgbases_to_build { internal get; internal set; default = new GenericArray<string> (); }
		public GenericArray<string> to_load { internal get; internal set; default = new GenericArray<string> (); }
		// sum of the download sizes of the packages to install, upgrade, downgrade and reinstall
		public uint64 download_size { get; internal set; }
		// change of the disk space used by the alpm packages, the packages to build are not counted
		public int64 installed_size_delta { get; internal set; }
		// a package which needs a restart to be used, like a kernel, will be installed or upgraded
		public bool requires_reboot { get; internal set; }

		internal TransactionSummary () {}

		// details about a package of the summary, null if the package is not in the summary
		public SummaryItem? get_item (Package pkg) {
			return items.lookup (pkg.id);
		}

		internal void add_item (Package pkg, SummaryReason reason, string? related, uint64 old_installed_size) {
			items.replace (pkg.id, new SummaryItem (pkg, reason, related, old_installed_size));
		}
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
