#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Fails when the supported Godot range in the docs drifts from the pinned Godot in tools/pins.env.
#   tools/check_godot_range.sh [ROOT]   check ROOT (default: this repository)
# Checks:
#   README.md has the line "**Supported Godot:** Godot X.Y.x (CI tests <GODOT_TAG> on Linux and Windows)."
#   where X.Y is the major.minor of GODOT_TAG, and <GODOT_TAG> is the pinned tag itself;
#   addons/bustle/plugin.cfg's description names "Godot X.Y.x" with the same X.Y;
#   CLAUDE.md names "Godot X.Y.x" with the same X.Y.
# Each failure names the file to update.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
pins="$root/tools/pins.env"
readme="$root/README.md"
plugin="$root/addons/bustle/plugin.cfg"
guide="$root/CLAUDE.md"

tag="$(sed -n 's/^GODOT_TAG=//p' "$pins" | tr -d '\r' | head -n 1)"
if [[ ! "$tag" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?-[A-Za-z0-9.]+$ ]]; then
	echo "tools/pins.env: GODOT_TAG '${tag}' isn't a Godot tag such as 4.7.2-stable." >&2
	exit 1
fi
minor="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
fail=0

line="$(grep -E '^\*\*Supported Godot:\*\*' "$readme" | tr -d '\r' | head -n 1 || true)"
if [[ "$line" =~ Godot\ ([0-9]+\.[0-9]+)\.x\ \(CI\ tests\ ([^ ]+)\ on\ Linux\ and\ Windows\) ]]; then
	if [[ "${BASH_REMATCH[1]}" != "$minor" ]]; then
		echo "README.md states Godot ${BASH_REMATCH[1]}.x, but tools/pins.env pins ${tag}: update the \"Supported Godot\" line in README.md to Godot ${minor}.x (or fix the pin)." >&2
		fail=1
	fi
	if [[ "${BASH_REMATCH[2]}" != "$tag" ]]; then
		echo "README.md says CI tests ${BASH_REMATCH[2]}, but tools/pins.env pins ${tag}: update the \"Supported Godot\" line in README.md." >&2
		fail=1
	fi
else
	echo "README.md has no \"**Supported Godot:** Godot ${minor}.x (CI tests ${tag} on Linux and Windows)\" line: add it to README.md." >&2
	fail=1
fi

described="$(sed -n 's/^description="\(.*\)"$/\1/p' "$plugin" | tr -d '\r' | head -n 1)"
if [[ "$described" =~ Godot\ ([0-9]+\.[0-9]+)\.x ]]; then
	if [[ "${BASH_REMATCH[1]}" != "$minor" ]]; then
		echo "addons/bustle/plugin.cfg's description states Godot ${BASH_REMATCH[1]}.x, but tools/pins.env pins ${tag}: update it to Godot ${minor}.x." >&2
		fail=1
	fi
else
	echo "addons/bustle/plugin.cfg's description names no \"Godot ${minor}.x\": update it in addons/bustle/plugin.cfg." >&2
	fail=1
fi

stated="$(grep -o -E 'Godot [0-9]+\.[0-9]+\.x' "$guide" | head -n 1 || true)"
if [[ "$stated" =~ ^Godot\ ([0-9]+\.[0-9]+)\.x$ ]]; then
	if [[ "${BASH_REMATCH[1]}" != "$minor" ]]; then
		echo "CLAUDE.md states Godot ${BASH_REMATCH[1]}.x, but tools/pins.env pins ${tag}: update it in CLAUDE.md to Godot ${minor}.x." >&2
		fail=1
	fi
else
	echo "CLAUDE.md names no \"Godot ${minor}.x\": update it in CLAUDE.md." >&2
	fail=1
fi

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "The supported Godot range (${minor}.x, CI tests ${tag}) matches tools/pins.env."
