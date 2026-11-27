# tests: meson test -C builddir
# the suite "root" is skipped unless run as root, see README.md

test_vala_args = common_vala_args
test_c_args = [common_c_args, alpm_c_args]

test_env = environment()
# the tests check some messages: not translated
test_env.set('LC_ALL', 'C')
test_env.set('LANGUAGE', 'C')
test_env.set('PAMAC_TEST_SRCDIR', meson.current_source_dir())
# load the plugins built here, not the installed ones
test_env.prepend('LD_LIBRARY_PATH', meson.project_build_root() / 'src')
test_env.set('PAMAC_DAEMON', pamac_daemon.full_path())

# the tests are built with the sources to reach the internal symbols,
# the source lists are defined in src/meson.build: meson places the generated C
# of a vala file according to the directory of its files() call

test_utils = executable('test-utils',
	sources: ['test_utils.vala', 'test_helpers.vala', utils_test_sources],
	dependencies: [gio],
	vala_args: test_vala_args,
	c_args: test_c_args,
	build_by_default: false)
test('utils', test_utils, env: test_env, suite: 'unit')

alpm_test_sources = ['test_helpers.vala', 'alpm_test_env.vala', daemon_common_sources]

test_alpm_runner = executable('test-alpm-runner',
	sources: ['test_alpm_runner.vala', alpm_test_sources],
	dependencies: daemon_deps,
	vala_args: test_vala_args,
	c_args: test_c_args,
	build_by_default: false)
test('alpm-runner', test_alpm_runner, env: test_env, suite: 'alpm', timeout: 180, is_parallel: false)

test_alpm_runner_root = executable('test-alpm-runner-root',
	sources: ['test_alpm_runner_root.vala', alpm_test_sources],
	dependencies: daemon_deps,
	vala_args: test_vala_args,
	c_args: test_c_args,
	build_by_default: false)
test('alpm-runner-root', test_alpm_runner_root, env: test_env, suite: 'root', timeout: 180, is_parallel: false)

test_daemon_dbus = executable('test-daemon-dbus',
	sources: ['test_daemon_dbus.vala', 'test_helpers.vala', libpamac_sources],
	dependencies: libpamac_deps,
	vala_args: test_vala_args,
	c_args: test_c_args,
	build_by_default: false)
test('daemon-dbus', test_daemon_dbus, env: test_env, suite: 'dbus', depends: pamac_daemon, timeout: 60, is_parallel: false)
