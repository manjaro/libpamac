#!/usr/bin/env python3
#
#  pamac-vala
#
#  Copyright (C) 2014-2026 Guillaume Benoit <guillaume@manjaro.org>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Vala annotates a returned GenericArray with owned elements as
# transfer full, but the array is created with a free function for its
# elements: bindings free each element and then the array, which frees
# them again. Freeing the container frees the elements, so the right
# annotation is transfer container.
# Only methods and functions are fixed: a virtual method return value is
# built by the binding, which does not set a free function.

import re
import sys

CALLABLE = re.compile(r'^\s*<(method|function|constructor|virtual-method|callback|glib:signal)\b')

def fix(text):
	lines = text.split('\n')
	kind = None
	for i, line in enumerate(lines):
		match = CALLABLE.match(line)
		if match:
			kind = match.group(1)
		if (kind in ('method', 'function', 'constructor')
				and '<return-value transfer-ownership="full">' in line
				and i + 1 < len(lines)
				and '<array name="GLib.PtrArray"' in lines[i + 1]):
			lines[i] = line.replace('transfer-ownership="full"', 'transfer-ownership="container"')
	return '\n'.join(lines)

if __name__ == '__main__':
	with open(sys.argv[1]) as f:
		text = f.read()
	with open(sys.argv[2], 'w') as f:
		f.write(fix(text))
