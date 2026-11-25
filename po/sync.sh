#!/usr/bin/env bash
# Synchronize Pamac translations.
# pamac.pot is shared by libpamac, pamac, pamac-cli and pamac-gtk3.

set -euo pipefail

po_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$po_dir")
pamac_dir=${PAMAC_DIR:-$root/../pamac}
pamac_cli_dir=${PAMAC_CLI_DIR:-$root/../pamac-cli}
pamac_gtk3_dir=${PAMAC_GTK3_DIR:-$root/../pamac-gtk3}
repos=("$root" "$pamac_dir" "$pamac_cli_dir")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

die () { echo "error: $*" >&2; exit 1; }

usage () {
	cat <<EOF
Usage: po/sync.sh <command>

  pot           regenerate pamac.pot and POTFILES from the sources
  push [--yes]  regenerate, show the changes, then upload pamac.pot to Transifex
  pull          download the translations, check them and update LINGUAS
  check         check the local .po files

The pamac, pamac-cli and pamac-gtk3 (gtk3 branch of pamac) repositories are
expected next to libpamac, or set PAMAC_DIR, PAMAC_CLI_DIR and PAMAC_GTK3_DIR.
EOF
}

need () {
	local cmd
	for cmd in "$@"; do
		command -v "$cmd" > /dev/null || die "$cmd not found"
	done
}

find_tx () {
	# Arch Linux installs the Transifex client as tx-cli
	tx=$(command -v tx-cli || command -v tx) || die "Transifex client not found (tx or tx-cli)"
}

# print the sorted msgids of a pot file, one per line
msgids () {
	msgcat --no-wrap "$1" | awk '
		function flush () { if (inside && id != "") print ctx id; if (inside) ctx = ""; inside = 0 }
		/^msgctxt / { ctx = substr($0, 9) " " ; next }
		/^msgid / { inside = 1; id = substr($0, 8, length($0) - 8); next }
		inside && /^"/ { id = id substr($0, 2, length($0) - 2); next }
		{ flush() }
		END { flush() }
	' | LC_ALL=C sort -u
}

# replace the header of a pot file by ours, which has a fixed date to avoid useless diffs
set_header () {
	{ cat "$po_dir/pot_head"; echo; sed '1,/^$/d' "$1"; } > "$2"
}

# extract $tmp/<name>.pot and its file list $tmp/<name>.files from some repositories,
# which must not have any translatable file path in common
extract () {
	local name=$1 repo file
	shift
	: > "$tmp/$name.files"
	mkdir "$tmp/$name"
	# gather the translatable files in a single tree,
	# xgettext can't find .ui files spread over several directories
	for repo in "$@"; do
		git -C "$repo" rev-parse --git-dir > /dev/null 2>&1 \
			|| die "repository not found: $repo (a missing one would delete its strings from Transifex)"
		echo "$(basename "$(realpath "$repo")"): $(git -C "$repo" branch --show-current) $(git -C "$repo" log -1 --format=%h)$(
			[ -z "$(git -C "$repo" status --porcelain -- src data resources)" ] || echo ' (uncommitted changes)')"
		while IFS= read -r file; do
			[ -f "$repo/$file" ] || continue
			case $file in
				*.vala|*.c|*.js) grep -qE '(^|[^[:alnum:]_.])(_|N_|C_|ngettext|dgettext|dngettext)[[:space:]]*\(' "$repo/$file" || continue ;;
				*.ui) grep -qE 'translatable="(yes|true|1)"' "$repo/$file" || continue ;;
				*.policy.in) ;;
				*) continue ;;
			esac
			[ ! -e "$tmp/$name/$file" ] || die "$file exists in several repositories"
			mkdir -p "$tmp/$name/$(dirname "$file")"
			cp "$repo/$file" "$tmp/$name/$file"
			echo "$file" >> "$tmp/$name.files"
		done < <(git -C "$repo" ls-files --cached --others --exclude-standard -- src data resources)
	done
	LC_ALL=C sort -o "$tmp/$name.files" "$tmp/$name.files"

	(cd "$tmp/$name" && xgettext --from-code=UTF-8 --add-location=file \
		--keyword=_ --keyword=N_ --keyword=C_:1c,2 --keyword=translatable \
		--files-from="$tmp/$name.files" --output="$tmp/$name.body")
	set_header "$tmp/$name.body" "$tmp/$name.pot"
}

generate_pot () {
	need git xgettext msgcat msgfmt
	extract main "${repos[@]}"
	# pamac-gtk3 has the same file paths as pamac, extract it apart and merge
	extract gtk3 "$pamac_gtk3_dir"
	msgcat --use-first --add-location=file --output-file="$tmp/merged.pot" "$tmp/main.pot" "$tmp/gtk3.pot"
	set_header "$tmp/merged.pot" "$tmp/pamac.pot"
	msgfmt --check-format --output-file=/dev/null "$tmp/pamac.pot"
	LC_ALL=C sort -u "$tmp/main.files" "$tmp/gtk3.files" > "$tmp/files"

	cp "$tmp/pamac.pot" "$po_dir/pamac.pot"
	cp "$tmp/files" "$po_dir/POTFILES"
	echo "pamac.pot: $(msgids "$po_dir/pamac.pot" | wc -l) strings from $(wc -l < "$tmp/files") file paths"
}

# compare with the last committed pamac.pot
show_changes () {
	git -C "$root" show HEAD:po/pamac.pot > "$tmp/head.pot"
	msgids "$tmp/head.pot" > "$tmp/old"
	msgids "$po_dir/pamac.pot" > "$tmp/new"
	LC_ALL=C comm -13 "$tmp/old" "$tmp/new" > "$tmp/added"
	LC_ALL=C comm -23 "$tmp/old" "$tmp/new" > "$tmp/removed"
	echo
	echo "Changes since the last commit:"
	echo "  added: $(wc -l < "$tmp/added")"
	sed 's/^/    + /' "$tmp/added"
	echo "  removed: $(wc -l < "$tmp/removed")"
	sed 's/^/    - /' "$tmp/removed"
}

push () {
	local answer
	find_tx
	generate_pot
	show_changes
	if [ "${1:-}" != "--yes" ]; then
		echo
		echo "Strings absent from pamac.pot will be deleted from Transifex."
		read -r -p "Upload pamac.pot to Transifex? [y/N] " answer || answer=
		[[ $answer == [yY] ]] || die "upload canceled"
	fi
	(cd "$root" && "$tx" push --source)
}

check () {
	need msgfmt
	local file failed=0
	for file in "$po_dir"/*.po; do
		if ! msgfmt --check --output-file=/dev/null "$file" 2> "$tmp/msgfmt"; then
			cat "$tmp/msgfmt" >&2
			failed=$((failed + 1))
		fi
	done
	[ "$failed" -eq 0 ] || die "$failed invalid .po file(s), fix them on Transifex"
	echo "All .po files are valid"
}

pull () {
	find_tx
	need git
	[ -z "$(git -C "$root" status --porcelain -- 'po/*.po')" ] \
		|| die "uncommitted changes in po/*.po would be overwritten, commit or stash them first"
	(cd "$root" && "$tx" pull --all --force)
	(cd "$po_dir" && sh ./populate_LINGUAS_file.sh)
	echo
	git -C "$root" status --short -- po
	check
}

case ${1:-} in
	pot) generate_pot; show_changes ;;
	push) push "${2:-}" ;;
	pull) pull ;;
	check) check ;;
	-h|--help|help) usage ;;
	*) usage >&2; exit 1 ;;
esac
