
Library for Pamac package manager based on libalpm

#### Features

 - Optional AUR support
 - Optional Appstream support
 - Optional Flatpak support
 - Optional Snap support
 - Library usable in Vala, C, C++, Python, Javascript and all languages supporting [GObject Introspection](https://gi.readthedocs.io/en/latest/users.html)

#### Installing from source

libpamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson setup --prefix=/usr --sysconfdir=/etc -Denable-aur=true -Denable-appstream=true -Denable-snap=true -Denable-flatpak=true --buildtype=release`

`meson compile`

`sudo meson install`

#### Tests

In the build directory run:

`meson test`

The suites:

 - `unit`: thread helpers and `TransactionRequest`
 - `alpm`: `AlpmRunner` without root, on a pacman installation made in a temporary directory, with a repository served slowly over HTTP: install, cancelled downloads, wait for the lock, lock file of another package manager… Needs `bsdtar`, `repo-add` and `python3`
 - `dbus`: the D-Bus protocol between the library and the built `pamac-daemon`, run on a private bus. Needs `dbus-daemon`
 - `root`: install scriptlets and hooks, run by libalpm in a chroot of a temporary root. Skipped unless run as root, build first as user then run:

   `sudo meson test --no-rebuild --suite root`

A test missing a program is skipped. The tests never use the databases, cache or hooks of the system: the `alpm` and `root` suites use their own `pacman.conf`, the `dbus` suite only runs operations refused without polkit. Like pamac, they remove the lock file of the system if it is older than the boot.

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
