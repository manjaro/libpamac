
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

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
