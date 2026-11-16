#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Self-test for tools/check_godot_range.sh on scratch copies of the four files it reads: the real
# repository passes, and each kind of drift fails with a message naming the file to update.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/check_godot_range.sh"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

# A scratch root with copies of the real files, after running sed expression $2 on file $1.
scratch() {
	rm -rf "$work/root"
	mkdir -p "$work/root/tools" "$work/root/addons/bustle"
	cp "$repo/tools/pins.env" "$work/root/tools/pins.env"
	cp "$repo/README.md" "$work/root/README.md"
	cp "$repo/addons/bustle/plugin.cfg" "$work/root/addons/bustle/plugin.cfg"
	cp "$repo/CLAUDE.md" "$work/root/CLAUDE.md"
	if [[ -n "${1:-}" ]]; then
		sed -i "$2" "$work/root/$1"
	fi
}

expect() {
	local want="$1" label="$2" names="${3:-}"
	local out code
	set +e
	out="$("$script" "$work/root" 2>&1)"
	code=$?
	set -e
	if [[ "$code" -ne "$want" ]]; then
		echo "FAIL: ${label}: exit ${code}, wanted ${want}"
		fail=1
	fi
	if [[ -n "$names" ]] && ! grep -q -F "$names" <<< "$out"; then
		echo "FAIL: ${label}: the message doesn't name ${names}"
		fail=1
	fi
	echo "${label}: exit ${code}: ${out}"
}

scratch
expect 0 "the repository as it is passes"

scratch tools/pins.env 's/^GODOT_TAG=.*/GODOT_TAG=4.8.0-stable/'
expect 1 "a new minor in the pin fails" "README.md"

scratch tools/pins.env 's/^GODOT_TAG=.*/GODOT_TAG=4.7.3-stable/'
expect 1 "a new patch in the pin fails until the README names it" "README.md"

scratch README.md 's/^\(\*\*Supported Godot:\*\* Godot \)[0-9]*\.[0-9]*\.x/\14.6.x/'
expect 1 "a README naming another minor fails" "README.md"

scratch README.md '/^\*\*Supported Godot:\*\*/d'
expect 1 "a README without the line fails" "README.md"

scratch addons/bustle/plugin.cfg 's/Godot [0-9]*\.[0-9]*\.x/Godot 4.6.x/'
expect 1 "a plugin description naming another minor fails" "addons/bustle/plugin.cfg"

scratch CLAUDE.md 's/Godot [0-9]*\.[0-9]*\.x/Godot 4.6.x/'
expect 1 "a CLAUDE.md naming another minor fails" "CLAUDE.md"

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "check_godot_range.sh self-test passed."
