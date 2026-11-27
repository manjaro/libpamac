#!/usr/bin/python

import gi
gi.require_version('Pamac', '12')
from gi.repository import Pamac

def print_pkg_details(details):
    print(" -Name:", details.get_name())
    print(" -Desc:", details.get_desc())
    print(" -Long Desc:", details.get_long_desc())
    print(" -Icon:", details.get_icon())
    print(" -Screenshots:", details.get_screenshots())

def search(pkgname, enable_appstream):
    config = Pamac.Config(conf_path="/etc/pamac.conf")
    # appstream data are loaded when the database is created
    config.set_enable_appstream(enable_appstream)
    db = Pamac.Database(config=config)
    for pkg in db.search_pkgs(pkgname):
        print_pkg_details(pkg)

if __name__ == "__main__":
    pkgname = "gimp"

    print("Without appstream support:")
    search(pkgname, False)

    print("")
    print("With appstream support:")
    search(pkgname, True)
