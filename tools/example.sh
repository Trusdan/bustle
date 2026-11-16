#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# The standalone example project in examples/village/.
#   tools/example.sh          copy addons/bustle/ into examples/village/addons/ (not committed), so
#                             the example opens in Godot 4.7.x as a project of its own
#   tools/example.sh --check  copy it, then load the example headless as CI does: import, run its
#                             two-day check (check.gd), run the main scene for 300 frames, and open
#                             it in the editor. Fails on a non-zero exit or any ERROR, WARNING or
#                             SCRIPT ERROR line.
# Needs the pinned Godot (tools/pins.env) on PATH as `godot` for --check.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
example="$root/examples/village"

check=0
if [[ "${1:-}" == "--check" ]]; then
	check=1
elif [[ -n "${1:-}" ]]; then
	echo "usage: tools/example.sh [--check]" >&2
	exit 2
fi

rm -rf "$example/addons"
mkdir -p "$example/addons"
cp -R "$root/addons/bustle" "$example/addons/bustle"
echo "Copied addons/bustle/ into examples/village/addons/. Open examples/village/project.godot in Godot 4.7.x."
if [[ $check -eq 0 ]]; then
	exit 0
fi

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
fail=0

# Runs one headless Godot command in the example; fails on its exit code or a bad line in its log.
run() {
	local label="$1"
	shift
	local code
	set +e
	godot --headless --path "$example" "$@" >"$log" 2>&1
	code=$?
	set -e
	tr -d '\r' < "$log"
	if [[ $code -ne 0 ]]; then
		echo "::error::Example: ${label} exited with code ${code}."
		fail=1
	elif grep -q -E 'ERROR|WARNING' "$log"; then
		echo "::error::Example: ${label} logged an ERROR or WARNING. See the log above."
		fail=1
	else
		echo "Example: ${label}: OK"
	fi
}

run "import" --import
run "two-day check" -s res://check.gd
run "main scene, 300 frames" --quit-after 300
run "editor" --editor --quit-after 120

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "The example loads headless with no errors."
