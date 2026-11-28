#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Runs the three timing benches (perception, rings, population) at their budget configuration,
# prints each one's summary line and saves it as DIR/<bench>.txt, then runs the performance gate
# (bench/perf_gate.gd), which prints the machine and every budgeted number against
# bench/perf_budgets.gd. Exits with the gate's code. Needs the pinned Godot on PATH as godot; on
# Windows run it from Git Bash. See docs/perf.md.
#   tools/perf_bench.sh [--out DIR]   (default build/perf, ignored by git)
# Opt-in: --load 1.1 runs the population bench with the hooks added after 1.0
# (bench/population_1_1_bench.gd) and labels every line "1.1 load"; its default DIR is
# build/perf-1.1, so the two runs can sit side by side. Without --load nothing changes.
set -euo pipefail
cd "$(dirname "$0")/.."

out=""
load=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		--load) load="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done
if [[ -n "$load" && "$load" != "1.1" ]]; then
	echo "unknown load: $load (the only opt-in load is 1.1)" >&2
	exit 2
fi
if [[ -z "$out" ]]; then
	out="build/perf${load:+-$load}"
fi
mkdir -p "$out"

if [[ "$load" == "1.1" ]]; then
	echo "1.1 load: the population bench runs bench/population_1_1_bench.gd; perception and rings as by default."
	for bench in perception rings population; do
		script="res://bench/${bench}_bench.gd"
		[[ "$bench" == "population" ]] && script="res://bench/population_1_1_bench.gd"
		echo "1.1 load: running the $bench bench..."
		godot --headless --path . -s "$script" 2>&1 | tr -d '\r' \
			| grep -E "^${bench} bench: [0-9]" > "$out/$bench.txt" || true
		sed 's/^/1.1 load: /' "$out/$bench.txt"
	done
	godot --headless --path . -s res://bench/perf_gate.gd -- "$(cd "$out" && pwd)" 2>&1 | tr -d '\r' \
		| grep -E '^(machine: |ok |FAIL |perf gate |usage: )' | sed 's/^/1.1 load: /'
	exit "${PIPESTATUS[0]}"
fi

for bench in perception rings population; do
	echo "Running the $bench bench..."
	# The bench's own exit code is its 1x-budget verdict, a report only; the gate judges below.
	godot --headless --path . -s "res://bench/${bench}_bench.gd" 2>&1 | tr -d '\r' \
		| grep -E "^${bench} bench: [0-9]" > "$out/$bench.txt" || true
	cat "$out/$bench.txt"
done
godot --headless --path . -s res://bench/perf_gate.gd -- "$(cd "$out" && pwd)" 2>&1 | tr -d '\r' \
	| grep -E '^(machine: |ok |FAIL |perf gate |usage: )'
exit "${PIPESTATUS[0]}"
