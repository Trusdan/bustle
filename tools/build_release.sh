#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
#
# Builds the two release zips described in docs/RELEASE.md from a commit, the same way every time:
#   bustle-<version>.zip              addons/bustle/ and LICENSE
#   bustle-wyrd-bridge-<version>.zip  addons/bustle_wyrd/ and LICENSE
#
# The files come from the commit itself (git archive), never the working tree, so local changes
# and untracked files can't slip in. Entries are sorted by path, every entry has the commit's own
# time and the same permissions, and the compression is fixed: the same commit gives byte-identical
# zips on any machine. It refuses to build when the addon's and the bridge's versions disagree.
#
# The compression doesn't use the system's zlib, whose output depends on its build (classic zlib
# and zlib-ng compress the same file to different bytes). tools/release/zlib_deflate.py, a pure-
# Python port of classic zlib's level-9 deflate, writes every entry instead, so the bytes are
# classic zlib's wherever it runs. Each zip is then read back with the system's zlib and checked.
#
#   tools/build_release.sh [--ref REF] [--out DIR] [--list] [--check] [--expect FILE]
#     --ref     the commit to build (default HEAD)
#     --out     where to write the zips (default build/release)
#     --list    also print each zip's file list
#     --check   build twice in fresh folders and fail unless both builds are byte-identical
#     --expect  fail unless each zip's SHA-256 is the one FILE lists ("<sha256>  <zip name>"
#               lines, as tools/release/published.sha256 holds for published releases)
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
	git archive --format=tar "$commit" -- "$@" | "$python" -c '
import io, sys, tarfile, time, zipfile
zip_path, epoch = sys.argv[1], int(sys.argv[2])
sys.path.insert(0, sys.argv[3])
import zlib_deflate
# Every deflated entry goes through the pure-Python compressor instead of the system zlib.
if not hasattr(zipfile, "_get_compressor"):
	sys.exit("this Python'"'"'s zipfile has no _get_compressor, so the compressor cannot be pinned")
system_compressor = zipfile._get_compressor
def pinned_compressor(compress_type, compresslevel=None):
	if compress_type == zipfile.ZIP_DEFLATED and compresslevel == 9:
		return zlib_deflate.Compressor()
	return system_compressor(compress_type, compresslevel)
zipfile._get_compressor = pinned_compressor
stamp = time.gmtime(max(epoch, 315532800))[:6]  # zip times start in 1980
files = {}
with tarfile.open(fileobj=io.BytesIO(sys.stdin.buffer.read())) as tar:
	for member in tar.getmembers():
		if member.isfile():
			files[member.name] = tar.extractfile(member).read()
with zipfile.ZipFile(zip_path, "w") as out:
	for name in sorted(files):
		info = zipfile.ZipInfo(name, date_time=stamp)
		info.compress_type = zipfile.ZIP_DEFLATED
		info.create_system = 3
		info.external_attr = 0o100644 << 16
		out.writestr(info, files[name], compresslevel=9)
# Read it back with the system zlib: every entry must decompress to the committed file.
with zipfile.ZipFile(zip_path) as back:
	for name in sorted(files):
		if back.read(name) != files[name]:
			sys.exit("%s: %s does not read back as committed" % (zip_path, name))
' "$zip" "$epoch" "$deflate_dir"
}

build() {
	local dir="$1"
	mkdir -p "$dir"
	rm -f "$dir/bustle-$version.zip" "$dir/bustle-wyrd-bridge-$version.zip"
	zip_from_commit "$dir/bustle-$version.zip" addons/bustle LICENSE
	zip_from_commit "$dir/bustle-wyrd-bridge-$version.zip" addons/bustle_wyrd LICENSE
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

report() {
	local dir="$1"
	for name in "bustle-$version.zip" "bustle-wyrd-bridge-$version.zip"; do
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
report "$out"

if [[ -n "$expect" ]]; then
	for name in "bustle-$version.zip" "bustle-wyrd-bridge-$version.zip"; do
		want="$(awk -v n="$name" '$2 == n {print $1}' "$expect")"
		got="$(sha256sum "$out/$name" | cut -d" " -f1)"
		if [[ -z "$want" ]]; then
			echo "$expect lists no hash for $name" >&2
			exit 1
		fi
		if [[ "$got" != "$want" ]]; then
			echo "$name is $got, but $expect expects $want: this build does not reproduce it" >&2
			exit 1
		fi
	done
	echo "Both zips match $expect."
fi

if [[ $check -eq 1 ]]; then
	again="$(mktemp -d)"
	trap 'rm -rf "$again"' EXIT
	build "$again"
	for name in "bustle-$version.zip" "bustle-wyrd-bridge-$version.zip"; do
		if ! cmp -s "$out/$name" "$again/$name"; then
			echo "$name differs between two builds of the same commit" >&2
			exit 1
		fi
	done
	echo "Two builds of $commit are byte-identical."
fi
