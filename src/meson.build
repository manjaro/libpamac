gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
gthread = dependency('gthread-2.0')
libalpm = dependency('libalpm')
json = dependency('json-glib-1.0')
libsoup = dependency('libsoup-3.0')
polkit = dependency('polkit-gobject-1')
appstream = dependency('appstream-glib')

gmodule = dependency('gmodule-2.0')

posix = meson.get_compiler('vala').find_library('posix')
math = meson.get_compiler('c').find_library('m')

vala_deps = [gobject]
alpm_deps = [libalpm, gio, posix]

alpm_c_args = ['-D_FILE_OFFSET_BITS=64']

common_vala_args = ['--pkg=posix', '--target-glib=2.38', '--vapidir=' + join_paths(meson.source_root(), 'vapi')]
common_c_args = ['-DGETTEXT_PACKAGE="pamac"']

libpamac_sources = ['package.vala', 'alpm_package.vala',
					'plugin_loader.vala', 'alpm_config.vala', 'pamac_config.vala', 'version.vala',
					'aur.vala', 'database.vala', 'transaction.vala', 'transaction_interface.vala',
					'alpm_utils.vala', 'transaction_interface_root.vala', 'daemon_interface.vala',
					'transaction_interface_daemon.vala', 'snap_interface.vala', 'flatpak_interface.vala',
					'updates_checker.vala']

libpamac_dependencies = [alpm_deps, math, json, appstream, libsoup, gmodule]

if get_option('enable-snap')
	snapd = dependency('snapd-glib-2')

	libpamac_snap = library('pamac-snap',
		sources: ['snap_interface.vala', 'snap_plugin.vala', 'package.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [gio, math, snapd, gmodule],
		version: '11.4',
		install: true,
		install_dir: [true, true, true])

	common_vala_args += '--define=ENABLE_SNAP'
endif

if get_option('enable-flatpak')
	flatpak = dependency('flatpak')

	libpamac_flatpak = library('pamac-flatpak',
		sources: ['flatpak_interface.vala', 'flatpak_plugin.vala', 'package.vala'],
		vala_args: common_vala_args,
		c_args: common_c_args,
		dependencies: [gio, math, flatpak, appstream, gmodule],
		version: '11.4',
		install: true,
		install_dir: [true, true, true])

	common_vala_args += '--define=ENABLE_FLATPAK'
endif

libpamac = library('pamac',
	sources: libpamac_sources,
	dependencies: libpamac_dependencies,
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	version: '11.4',
	vala_gir: 'Pamac-11.gir',
	install: true,
	install_dir: [true, true, true, true])

# create pkg-config file
pkg = import('pkgconfig')
pkg.generate(libpamac,
	description: 'Pamac Library')

# create typelib files
g_ir_compiler = find_program('g-ir-compiler')
custom_target('pamac typelib', command: [g_ir_compiler, '--shared-library', 'libpamac', '--output', '@OUTPUT@', join_paths(meson.current_build_dir(), 'Pamac-11.gir')],
	output: 'Pamac-11.typelib',
	depends: libpamac,
	install: true,
	install_dir: join_paths(get_option('libdir'), 'girepository-1.0'))

daemon_sources = ['version.vala', 'package.vala', 'alpm_package.vala', 'aur.vala', 'alpm_utils.vala',
				'alpm_config.vala', 'pamac_config_daemon.vala', 'daemon.vala', 'plugin_loader.vala',
				'database.vala', 'snap_interface.vala', 'flatpak_interface.vala']
daemon_dependencies = [vala_deps, alpm_deps, json, math, libsoup, polkit, appstream, gmodule]

executable('pamac-daemon',
	sources: daemon_sources,
	dependencies: daemon_dependencies,
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)

executable('dependency-checker',
	sources: ['alpm_config.vala', 'dependency_checker.vala'],
	dependencies: [vala_deps, alpm_deps],
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)

executable('outdated-checker',
	sources: ['alpm_config.vala', 'outdated_checker.vala'],
	dependencies: [vala_deps, alpm_deps],
	vala_args: common_vala_args,
	c_args: [common_c_args, alpm_c_args],
	install : true)
