#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Fails when a plugin folder's copy of the license drifts from the root LICENSE.
#   tools/check_license_copies.sh [ROOT]   check ROOT (default: this repository)
# Checks, byte for byte:
#   addons/bustle/LICENSE and addons/bustle_wyrd/LICENSE are exact copies of LICENSE;
#   both plugin folders hold a README.md.
# The copies are there so a project that copies only a plugin folder still has its license and a
# pointer to the docs. Each failure names the file to update.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
fail=0

if [[ ! -f "$root/LICENSE" ]]; then
	echo "LICENSE is missing at the repository root." >&2
	exit 1
fi
for folder in addons/bustle addons/bustle_wyrd; do
	copy="$folder/LICENSE"
	if [[ ! -f "$root/$copy" ]]; then
		echo "$copy is missing: copy the root LICENSE there (cp LICENSE $copy)." >&2
		fail=1
	elif ! cmp -s "$root/LICENSE" "$root/$copy"; then
		echo "$copy differs from the root LICENSE: copy it again (cp LICENSE $copy)." >&2
		fail=1
	fi
	if [[ ! -f "$root/$folder/README.md" ]]; then
		echo "$folder/README.md is missing: each plugin folder keeps a short README.md." >&2
		fail=1
	fi
done

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "addons/bustle/LICENSE and addons/bustle_wyrd/LICENSE match the root LICENSE; both folders have a README.md."
