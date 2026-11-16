#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Writes docs/config.md: every @export field in addons/bustle/ and every bustle/... project setting,
# with its type, default, range and effect. Ranges for numbers without an editor hint come from
# tools/config_reference/ranges.tsv (hand-checked; one "Class.field<TAB>range" per line).
#   tools/config_reference.sh          regenerate docs/config.md
#   tools/config_reference.sh --check  fail if docs/config.md is out of date, a number field has no
#                                      range entry, or an entry names no field (used by CI)
# Needs the pinned Godot (tools/pins.env) on PATH as `godot`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

check=0
if [[ "${1:-}" == "--check" ]]; then
	check=1
elif [[ -n "${1:-}" ]]; then
	echo "usage: tools/config_reference.sh [--check]" >&2
	exit 2
fi
if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
page=docs/config.md

godot --headless --path . --import >/dev/null 2>&1
if ! godot --headless --path . -s res://tools/config_reference/config_reference.gd -- \
		"$root/tools/config_reference/ranges.tsv" "$work/config.md" >"$work/log" 2>&1 \
		|| grep -E -q 'SCRIPT ERROR|Parse Error' "$work/log"; then
	cat "$work/log"
	echo "The configuration reference couldn't be built." >&2
	exit 1
fi

if [[ $check -eq 1 ]]; then
	if ! diff -u "$page" "$work/config.md"; then
		echo "$page is out of date. Run tools/config_reference.sh and commit the result." >&2
		exit 1
	fi
	echo "$page is up to date."
else
	cp "$work/config.md" "$page"
	echo "Wrote $page."
fi
