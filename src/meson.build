gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
gthread = dependency('gthread-2.0')
libalpm = dependency('libalpm', version : '>=16.0')
json = dependency('json-glib-1.0')
libsoup = dependency('libsoup-3.0')
polkit = dependency('polkit-gobject-1')

gmodule = dependency('gmodule-2.0')

posix = meson.get_compiler('vala').find_library('posix')
math = meson.get_compiler('c').find_library('m')

alpm_deps = [libalpm, gio, posix]

alpm_c_args = ['-D_FILE_OFFSET_BITS=64']

common_vala_args = ['--pkg=posix', '--vapidir=' + join_paths(meson.global_source_root(), 'vapi')]
common_c_args = ['-DGETTEXT_PACKAGE="pamac"']

if get_option('enable-aur')
	libpamac_aur = library('pamac-aur',
		sources: ['aur_interface.vala', 'aur_plugin.vala', 'alpm_config.vala', 'utils.vala', 'version.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [alpm_deps, math, json, libsoup, gmodule],
		version: '12.0',
		install: true,
		install_dir: [true])

	common_vala_args += '--define=ENABLE_AUR'
endif

if get_option('enable-appstream')
	appstream = dependency('appstream', version : '>=1.0')

	libpamac_appstream = library('pamac-appstream',
		sources: ['appstream_interface.vala', 'appstream_utils.vala', 'appstream_plugin.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [gio, appstream, gmodule],
		version: '12.0',
		install: true,
		install_dir: [true])

	common_vala_args += '--define=ENABLE_APPSTREAM'
endif

if get_option('enable-snap')
	snapd = dependency('snapd-glib-2')

	libpamac_snap = library('pamac-snap',
		sources: ['snap_interface.vala', 'snap_plugin.vala', 'package.vala', 'transaction_sink.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [gio, math, snapd, gmodule],
		version: '12.0',
		install: true,
		install_dir: [true])

	common_vala_args += '--define=ENABLE_SNAP'
endif

if get_option('enable-flatpak')
	flatpak = dependency('flatpak')

	libpamac_flatpak = library('pamac-flatpak',
		sources: ['flatpak_interface.vala', 'appstream_utils.vala', 'flatpak_plugin.vala', 'package.vala', 'transaction_sink.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [gio, math, flatpak, appstream, gmodule],
		version: '12.0',
		install: true,
		install_dir: [true])

	common_vala_args += '--define=ENABLE_FLATPAK'
endif

# the source lists are also used by the tests, which need the internal symbols
libpamac_sources = files('package.vala', 'alpm_package.vala', 'utils.vala',
			'plugin_loader.vala', 'alpm_config.vala', 'pamac_config.vala', 'version.vala',
			'aur_interface.vala', 'database.vala', 'transaction.vala', 'alpm_utils.vala',
			'transaction_request.vala', 'transaction_sink.vala', 'alpm_runner.vala', 'transaction_interface.vala', 'transaction_interface_root.vala', 'daemon_interface.vala',
			'transaction_interface_daemon.vala', 'snap_interface.vala', 'flatpak_interface.vala', 'pgp_key.vala',
			'appstream_interface.vala', 'updates_checker.vala')
libpamac_deps = [alpm_deps, math, libsoup, gmodule]
# for the unit tests
utils_test_sources = files('utils.vala', 'version.vala', 'transaction_request.vala', 'transaction_sink.vala')

libpamac = library('pamac',
	sources: libpamac_sources,
	dependencies: libpamac_deps,
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	version: '12.0',
	vala_gir: 'Pamac-12.gir',
	install: true,
	install_dir: [true, true, true, false])
				# lib, header, vapi, gir (the fixed one is installed by gir/meson.build)

# create pkg-config file
pkg = import('pkgconfig')
pkg.generate(libpamac,
	description: 'Pamac Library')

# fix the gir and create typelib files
subdir('gir')

# the daemon sources without its D-Bus service and main
daemon_common_sources = files('version.vala', 'package.vala', 'alpm_package.vala', 'aur_interface.vala', 'utils.vala',
				'alpm_utils.vala', 'transaction_request.vala', 'transaction_sink.vala', 'alpm_runner.vala', 'alpm_config.vala', 'pamac_config_daemon.vala', 'plugin_loader.vala',
				'database.vala', 'appstream_interface.vala', 'snap_interface.vala', 'flatpak_interface.vala')
daemon_deps = [alpm_deps, math, libsoup, polkit, gmodule]

pamac_daemon = executable('pamac-daemon',
	sources: [daemon_common_sources, 'daemon.vala'],
	dependencies: daemon_deps,
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)

libpamac_dep = declare_dependency(link_with: libpamac)

executable('pamac-checkupdates',
	sources: ['checkupdates.vala'],
	dependencies: [gio, libpamac_dep],
	install : true)

executable('dependency-checker',
	sources: ['alpm_config.vala', 'dependency_checker.vala'],
	dependencies: [alpm_deps],
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)

executable('outdated-checker',
	sources: ['alpm_config.vala', 'outdated_checker.vala'],
	dependencies: [alpm_deps],
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)
