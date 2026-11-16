#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Runs the three timing benches (perception, rings, population) at their budget configuration,
# prints each one's summary line and saves it as DIR/<bench>.txt, then runs the performance gate
# (bench/perf_gate.gd), which prints the machine and every budgeted number against
# bench/perf_budgets.gd. Exits with the gate's code. Needs the pinned Godot on PATH as godot; on
# Windows run it from Git Bash. See docs/perf.md.
#   tools/perf_bench.sh [--out DIR]   (default build/perf, ignored by git)
set -euo pipefail
cd "$(dirname "$0")/.."

out="build/perf"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done
mkdir -p "$out"

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
