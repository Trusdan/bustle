#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
#
# Builds the release zips described in docs/RELEASE.md from a commit, the same way every time:
#   bustle-<version>.zip              addons/bustle/ and LICENSE
#   bustle-wyrd-bridge-<version>.zip  addons/bustle_wyrd/ and LICENSE
#   bustle-example-<version>.zip      bustle-example-<version>/: the example project
#                                     (examples/village/), with addons/bustle/ and LICENSE in it
#                                     (only from a commit that has the example)
#
# The files come from the commit itself, never the working tree, so local changes and untracked
# files can't slip in: the addon zips through git archive, and the example zip from the commit's
# files directly, since .gitattributes keeps examples/ out of archives. Entries are sorted by path,
# every entry has the commit's own time and the same permissions, and the compression is fixed:
# the same commit gives byte-identical zips on any machine. It refuses to build when the addon's and
# the bridge's versions disagree.
#
# The compression doesn't use the system's zlib, whose output depends on its build (classic zlib
# and zlib-ng compress the same file to different bytes). tools/release/zlib_deflate.py, a pure-
# Python port of classic zlib's level-9 deflate, writes every entry instead, so the bytes are
# classic zlib's wherever it runs. Each zip is then read back with the system's zlib and checked.
# tools/release/write_zip.py writes each zip.
#
#   tools/build_release.sh [--ref REF] [--out DIR] [--list] [--check] [--expect FILE]
#     --ref     the commit to build (default HEAD)
#     --out     where to write the zips (default build/release)
#     --list    also print each zip's file list
#     --check   build twice in fresh folders and fail unless both builds are byte-identical
#     --expect  fail unless each zip's SHA-256 is the one FILE lists ("<sha256>  <zip name>"
#               lines, as tools/release/published.sha256 holds for published releases); FILE
#               must list the two addon zips, and the example zip's hash is checked if listed
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ref="HEAD"
out="build/release"
list=0
check=0
expect=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--ref) ref="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		--list) list=1; shift ;;
		--check) check=1; shift ;;
		--expect) expect="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

python="$(command -v python3 || command -v python || true)"
if [[ -z "$python" ]]; then
	echo "python3 is not on PATH" >&2
	exit 1
fi
deflate_dir="$(pwd)/tools/release"

commit="$(git rev-parse --verify "$ref^{commit}")"
version="$(git show "$commit:addons/bustle/VERSION" | tr -d '[:space:]')"
bridge_version="$(git show "$commit:addons/bustle_wyrd/VERSION" | tr -d '[:space:]')"
if [[ "$version" != "$bridge_version" ]]; then
	echo "addons/bustle/VERSION ($version) and addons/bustle_wyrd/VERSION ($bridge_version) disagree" >&2
	exit 1
fi
epoch="$(git log -1 --format=%ct "$commit")"

# zip_from_commit <zip path> <paths...>: writes the zip from the commit's files under those paths.
zip_from_commit() {
	local zip="$1"
	shift
	git archive --format=tar "$commit" -- "$@" | "$python" "$deflate_dir/write_zip.py" "$zip" "$epoch" --tar
}

# The example project, with the addon and the license, all under one top folder.
example_top="bustle-example-$version"
has_example=0
if git cat-file -e "$commit:examples/village/project.godot" 2>/dev/null; then
	has_example=1
fi
zips=("bustle-$version.zip" "bustle-wyrd-bridge-$version.zip")
if [[ $has_example -eq 1 ]]; then
	zips+=("bustle-example-$version.zip")
fi

# example_zip <zip path>: the example's committed files (but its .gitignore, which would hide the
# addon from git in a copied project), the addon and the license, from the commit's files.
example_zip() {
	"$python" "$deflate_dir/write_zip.py" "$1" "$epoch" --commit "$commit" \
		--map examples/village "$example_top" \
		--map addons/bustle "$example_top/addons/bustle" \
		--map LICENSE "$example_top/LICENSE" \
		--skip examples/village/.gitignore
}

build() {
	local dir="$1"
	mkdir -p "$dir"
	rm -f "$dir/bustle-$version.zip" "$dir/bustle-wyrd-bridge-$version.zip" "$dir/bustle-example-$version.zip"
	zip_from_commit "$dir/bustle-$version.zip" addons/bustle LICENSE
	zip_from_commit "$dir/bustle-wyrd-bridge-$version.zip" addons/bustle_wyrd LICENSE
	if [[ $has_example -eq 1 ]]; then
		example_zip "$dir/bustle-example-$version.zip"
	fi
}

# The zips must hold only what docs/RELEASE.md lists.
verify() {
	local zip="$1" prefix="$2"
	"$python" -c '
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
prefix = sys.argv[2]
bad = [n for n in names if n != "LICENSE" and not n.startswith(prefix)]
if bad or "LICENSE" not in names or not any(n.startswith(prefix) for n in names):
	sys.exit("%s holds something it should not, or misses LICENSE or %s: %s" % (sys.argv[1], prefix, bad[:5]))
' "$zip" "$prefix"
}

# The example zip must hold exactly the example (but its .gitignore) and the addon zip's entries,
# under its top folder, with the same bytes as the addon zip's.
verify_example() {
	local zip="$1" addon_zip="$2"
	git ls-tree -r -z --name-only "$commit" -- examples/village | "$python" -c '
import sys, zipfile
example_zip, addon_zip, top = sys.argv[1], sys.argv[2], sys.argv[3] + "/"
committed = [p[len("examples/village/"):] for p in sys.stdin.read().split("\0") if p and p != "examples/village/.gitignore"]
example = zipfile.ZipFile(example_zip)
addon = zipfile.ZipFile(addon_zip)
names = example.namelist()
want = sorted(set([top + p for p in committed] + [top + n for n in addon.namelist()]))
if sorted(names) != want:
	extra = sorted(set(names) - set(want))
	missing = sorted(set(want) - set(names))
	sys.exit("%s holds %s and misses %s" % (example_zip, extra[:5], missing[:5]))
for name in addon.namelist():
	if example.read(top + name) != addon.read(name):
		sys.exit("%s: %s%s differs from %s" % (example_zip, top, name, addon_zip))
for name in ("project.godot", "addons/bustle/plugin.cfg", "LICENSE"):
	if top + name not in names:
		sys.exit("%s has no %s%s" % (example_zip, top, name))
' "$zip" "$addon_zip" "$example_top"
}

report() {
	local dir="$1"
	for name in "${zips[@]}"; do
		local count
		count="$("$python" -c 'import sys, zipfile; print(len(zipfile.ZipFile(sys.argv[1]).namelist()))' "$dir/$name")"
		echo "$(sha256sum "$dir/$name" | cut -d" " -f1)  $name  ($count files)"
		if [[ $list -eq 1 ]]; then
			"$python" -c 'import sys, zipfile; print("\n".join("    " + n for n in zipfile.ZipFile(sys.argv[1]).namelist()))' "$dir/$name"
		fi
	done
}

echo "Bustle $version release zips from commit $commit"
build "$out"
verify "$out/bustle-$version.zip" "addons/bustle/"
verify "$out/bustle-wyrd-bridge-$version.zip" "addons/bustle_wyrd/"
if [[ $has_example -eq 1 ]]; then
	verify_example "$out/bustle-example-$version.zip" "$out/bustle-$version.zip"
else
	echo "($commit has no examples/village/, so no example zip.)"
fi
report "$out"

if [[ -n "$expect" ]]; then
	for name in "${zips[@]}"; do
		want="$(awk -v n="$name" '$2 == n {print $1}' "$expect")"
		got="$(sha256sum "$out/$name" | cut -d" " -f1)"
		if [[ -z "$want" && "$name" == bustle-example-* ]]; then
			continue
		fi
		if [[ -z "$want" ]]; then
			echo "$expect lists no hash for $name" >&2
			exit 1
		fi
		if [[ "$got" != "$want" ]]; then
			echo "$name is $got, but $expect expects $want: this build does not reproduce it" >&2
			exit 1
		fi
	done
	echo "Every zip $expect lists matches."
fi

if [[ $check -eq 1 ]]; then
	again="$(mktemp -d)"
	trap 'rm -rf "$again"' EXIT
	build "$again"
	for name in "${zips[@]}"; do
		if ! cmp -s "$out/$name" "$again/$name"; then
			echo "$name differs between two builds of the same commit" >&2
			exit 1
		fi
	done
	echo "Two builds of $commit are byte-identical."
fi
