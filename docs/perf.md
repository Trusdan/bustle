# Performance

## Perception

**Budget (PROPOSED):** 40 actors that perceive and can be perceived, in one area, at 60 physics frames a second. Perception may take at most **1.0 ms per physics frame on average** and at most **2.0 ms at the 99th percentile**. That covers copying the components' state, the senses and the sight rays.

**Bench:** `bench/perception_bench.gd` builds a neutral village square: an 80 m floor, 12 walls, and 40 villagers. Each villager has a `BustlePerceiver` (default profile, 10 Hz) and a `BustlePerceivable` (noise 7 m). They walk about for 600 frames, and the bench times `BustlePerceptionSystem.step()` each frame. It exits 1 when over budget.

```bash
godot --headless --path . -s res://bench/perception_bench.gd             # 40 actors, 600 frames
godot --headless --path . -s res://bench/perception_bench.gd -- --actors=80 --frames=1200
```

CI runs it on Ubuntu as a report only (`continue-on-error`), because shared runners' timings vary.

**Measured** (2026-11-02, Godot 4.7.2 headless, Linux cloud machine):

```
perception bench: 40 actors, 600 frames: average 0.734 ms, p99 1.305 ms (budget 1.0 / 2.0 ms): OK
```

What keeps it cheap:

- each perceiver senses at its profile's `perception_hz` (default 10), with phases spread evenly so about a sixth of them sense each frame;
- a target beyond both sight and hearing reach is skipped until there is a meter for it;
- a sight ray is cast only for a target in range, in the cone, visible and lit enough.

## Simulation rings

**Budgets (PROPOSED, from the design's ring section):**

- **LIGHT:** at most **0.3 ms per frame on average** for up to 40 LIGHT agents thinking at 1 Hz.
- **OFF_SCREEN:** at most **0.5 ms per frame on average, amortised**, for 200 agents thinking once per game hour (one game hour is two real minutes at 30× game speed).

**Bench:** `bench/rings_bench.gd` sets up 40 LIGHT agents (one area away from the player) and 200 OFF_SCREEN agents, each with a six-goal library. It runs one game hour: 7,200 frames at 60 frames a second and 30× game speed. It times each ring's thinking per frame with `BustleSimRings.last_timings`. It reports the agent counts, the simulated time, the engine version and the raw average and 99th percentile per ring, and exits 1 when an average is over budget.

```bash
godot --headless --path . -s res://bench/rings_bench.gd
godot --headless --path . -s res://bench/rings_bench.gd -- --light=40 --offscreen=400 --frames=7200
```

CI runs it on Ubuntu as a report only (`continue-on-error`), like the perception bench.

**Measured** (2026-11-08, Godot 4.7.2 headless, Linux cloud machine):

```
rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min), Godot 4.7.2-stable (official): LIGHT average 0.150 ms p99 0.521 ms (budget 0.3), OFF_SCREEN average 0.221 ms p99 0.536 ms (budget 0.5): OK
```

What keeps it cheap:

- LIGHT and FULL agents think at their ring's rate, at a fixed per-agent phase, so a ring's thinking is spread across the second rather than landing in one frame.
- OFF_SCREEN agents think once per game hour, at a fixed per-agent minute.
- Catch-up runs at most seven game days of hourly thinking (168 thinks) per agent, and summarises anything older.

## Demo soak

**Checks:** no agent stuck (by the stuck watch's rule, `demo/README.md`) and the same timeline hash when the same seed runs again. These are deterministic, so they fail the run, not just report.

**Bench:** `bench/soak.gd` runs the house (2 residents) and the colony (4 settlers, every module on, the cold snap included) from seed 1 for a number of game days, twice each. It prints the seed, the engine version and build commit, the population, the simulated days, the wall time (and per day), the static memory, the timeline's size and SHA-256, the replay result, the stuck spells and each agent's longest run with no legitimate activity and no progress. It exits 1 on a stuck agent, a different replay hash or a short run.

```bash
godot --headless --path . -s res://bench/soak.gd                      # 30 days, seed 1, both demos
godot --headless --path . -s res://bench/soak.gd -- --days=2 --seed=7 --demo=colony
```

CI runs a two-day smoke on every change (`test`). The full 30-day soak runs nightly and on demand (`.github/workflows/soak.yml`), and keeps its log as an artifact.

**Measured** (2026-11-12, Godot 4.7.2 headless, Linux cloud machine, seed 1, 30 days):

```
soak house: 2 agents, 30 days in 3545 ms (118.2 ms a day), static memory 30.3 MiB, timeline 1246 entries, hash 973ec9e1…, replay same, stuck spells 0, longest still {"resident_a":0,"resident_b":0}: OK
soak colony: 4 agents, 30 days in 14216 ms (473.9 ms a day), static memory 36.2 MiB, timeline 5191 entries, hash 24703e18…, replay same, stuck spells 0, longest still {"settler_a":0,"settler_b":0,"settler_c":0,"settler_d":0}: OK
```

These are the small demos' numbers, not the 40 Full / 40 Light / 200 Off-screen budgets; a synthetic bench at those counts is still to come.

