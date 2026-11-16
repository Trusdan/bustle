# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted
## The performance budgets (docs/perf.md), in one place: the benches report against these values,
## and the CI gate (bench/perf_gate.gd) fails at [constant CI_HEADROOM] times each timing budget.
## Changing a budget or the headroom is a one-line change here.

## Perception for 40 actors: average and 99th-percentile milliseconds per physics frame.
const PERCEPTION_AVG_MS := 1.0
const PERCEPTION_P99_MS := 2.0
## FULL brains and sequences: average and 99th-percentile milliseconds per frame.
const FULL_AVG_MS := 1.0
const FULL_P99_MS := 2.0
## LIGHT, 40 agents at 1 Hz: average milliseconds per frame.
const LIGHT_AVG_MS := 0.3
## OFF_SCREEN, 200 agents once per game hour: average milliseconds per frame, amortised.
const OFFSCREEN_AVG_MS := 0.5
## Save size: bytes per agent.
const SAVE_BYTES_PER_AGENT := 2048

## The CI gate fails a timing at this many times its budget. Shared runners' timings swing to
## about 1.8 times their median (docs/perf.md, "Budgets and the CI gate"), so a gate at the
## budget itself would fail on noise. The save size and stuck agents are deterministic and get no headroom.
const CI_HEADROOM := 2.0
