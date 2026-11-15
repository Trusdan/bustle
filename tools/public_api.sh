#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# The frozen public API (docs/public-api/VERSIONING.md): a manifest of it, its page, and the check.
#   tools/public_api.sh --write             regenerate docs/public-api/public_api.json and PUBLIC_API.md
#                                           (refuses a breaking change without a deprecation entry)
#   tools/public_api.sh [--check]           fail on a frozen symbol removed, renamed or changed without an
#                                           entry in docs/public-api/deprecations.json; new symbols pass
#   tools/public_api.sh --check --base REF  also check against the manifest at a git ref (CI: the base branch)
# Needs the pinned Godot (tools/pins.env) on PATH as `godot`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mode=check
base=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--write) mode=write ;;
		--check) mode=check ;;
		--base) base="${2:?--base needs a git ref}"; shift ;;
		*) echo "usage: tools/public_api.sh [--write | --check [--base REF]]" >&2; exit 2 ;;
	esac
	shift
done
if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

dir=docs/public-api
manifest="$dir/public_api.json"
page="$dir/PUBLIC_API.md"
deprecations="$dir/deprecations.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tool() {
	godot --headless --path . --script res://tools/public_api/public_api_tool.gd -- "$@" 2>"$work/tool.err" \
		|| { cat "$work/tool.err" >&2; return 1; }
	if grep -E -q 'SCRIPT ERROR|Parse Error' "$work/tool.err"; then
		cat "$work/tool.err" >&2
		return 1
	fi
}

# Doctool XML for each addon in the checkout (the bridge is optional), then the current manifest.
godot --headless --path . --import >/dev/null 2>&1
xml_dirs=()
for addon in bustle bustle_wyrd; do
	[[ -d "addons/$addon" ]] || continue
	mkdir -p "$work/xml/$addon"
	if ! godot --headless --path . --doctool "$work/xml/$addon" --gdscript-docs "res://addons/$addon" \
			>"$work/doctool.log" 2>&1 || grep -E -q 'SCRIPT ERROR|Parse Error' "$work/doctool.log"; then
		cat "$work/doctool.log"
		echo "Godot's doctool failed on addons/$addon." >&2
		exit 1
	fi
	xml_dirs+=("$work/xml/$addon")
done
version="$(tr -d '[:space:]' < addons/bustle/VERSION)"
tool build "$work/public_api.json" "$work/PUBLIC_API.md" "$version" "${xml_dirs[@]}"

fail=0
compare() { # baseline label
	tool compare "$1" "$work/public_api.json" "$deprecations" "$2" || fail=1
}

if [[ "$mode" == write ]]; then
	[[ -f "$manifest" ]] && compare "$manifest" "the committed manifest"
	if [[ "$fail" -ne 0 ]]; then
		echo "Not written: add a deprecation entry for each breaking change (docs/public-api/VERSIONING.md)." >&2
		exit 1
	fi
	mkdir -p "$dir"
	cp "$work/public_api.json" "$manifest"
	cp "$work/PUBLIC_API.md" "$page"
	echo "Wrote $manifest and $page."
	exit 0
fi

if [[ ! -f "$manifest" ]]; then
	echo "$manifest is missing. Run tools/public_api.sh --write." >&2
	exit 1
fi
compare "$manifest" "the committed manifest"
if [[ -n "$base" ]]; then
	if git cat-file -e "$base:$manifest" 2>/dev/null; then
		git show "$base:$manifest" > "$work/base.json"
		compare "$work/base.json" "$base"
	else
		echo "No $manifest at $base; nothing older to compare against."
	fi
fi
# The page must be exactly what the committed manifest renders to.
tool render "$manifest" "$work/committed.md"
if ! diff -u "$page" "$work/committed.md"; then
	echo "$page doesn't match $manifest. Run tools/public_api.sh --write." >&2
	fail=1
fi
if [[ "$fail" -eq 0 ]] && ! cmp -s "$manifest" "$work/public_api.json"; then
	echo "Note: $manifest is behind the code (new symbols or wording only). Run tools/public_api.sh --write to record it."
fi
if [[ "$fail" -ne 0 ]]; then
	echo "The public API check failed (docs/public-api/VERSIONING.md)." >&2
	exit 1
fi
echo "The public API check passed."
