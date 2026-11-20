#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Checks the example release zip (docs/RELEASE.md) as someone who downloads it would use it:
#   1. tools/build_release.sh --check builds the zips twice and they're byte-identical, the
#      example zip included;
#   2. the example zip unpacks into one folder holding a project with the addon in it;
#   3. that project loads headless with no errors or warnings (tools/example.sh --check
#      --project): the import, its two-day check, the main scene and the editor.
#   tools/test_example_zip.sh [--ref REF]   (default HEAD)
# Needs the pinned Godot (tools/pins.env) on PATH as `godot`, and Python 3.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ref="HEAD"
if [[ "${1:-}" == "--ref" ]]; then
	ref="$2"
elif [[ -n "${1:-}" ]]; then
	echo "usage: tools/test_example_zip.sh [--ref REF]" >&2
	exit 2
fi

python="$(command -v python3 || command -v python || true)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "1. Build the release zips twice:"
tools/build_release.sh --ref "$ref" --out "$work/zips" --check
version="$(git show "$(git rev-parse "$ref^{commit}"):addons/bustle/VERSION" | tr -d '[:space:]')"
zip="$work/zips/bustle-example-$version.zip"
if [[ ! -f "$zip" ]]; then
	echo "FAIL: no bustle-example-$version.zip (does $ref have examples/village/?)" >&2
	exit 1
fi

echo "2. Unpack bustle-example-$version.zip:"
"$python" -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
	tops = sorted({name.split("/")[0] for name in z.namelist()})
	if tops != [sys.argv[3]]:
		sys.exit("the zip should hold one folder, %s, but holds %s" % (sys.argv[3], tops))
	z.extractall(sys.argv[2])
	print("%d files into %s/" % (len(z.namelist()), sys.argv[3]))
' "$zip" "$work/unpacked" "bustle-example-$version"

echo "3. Load the unpacked project headless:"
tools/example.sh --check --project "$work/unpacked/bustle-example-$version"
echo "The example release zip builds reproducibly, unpacks and loads headless."
