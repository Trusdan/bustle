# Performance

The budgets below were ratified on 2026-11-16. Their values live in one place, `bench/perf_budgets.gd`: the benches report against it and the CI gate judges against it, so changing a budget is a one-line change there. [Budgets and the CI gate](#budgets-and-the-ci-gate) explains the gate.

## Perception

**Budget:** 40 actors that perceive and can be perceived, in one area, at 60 physics frames a second. Perception may take at most **1.0 ms per physics frame on average** and at most **2.0 ms at the 99th percentile**. That covers copying the components' state, the senses and the sight rays.

**Bench:** `bench/perception_bench.gd` builds a neutral village square: an 80 m floor, 12 walls, and 40 villagers. Each villager has a `BustlePerceiver` (default profile, 10 Hz) and a `BustlePerceivable` (noise 7 m). They walk about for 600 frames, and the bench times `BustlePerceptionSystem.step()` each frame. It exits 1 when over budget.

```bash
godot --headless --path . -s res://bench/perception_bench.gd             # 40 actors, 600 frames
godot --headless --path . -s res://bench/perception_bench.gd -- --actors=80 --frames=1200
```

CI runs it on Ubuntu as a report at the budget (`continue-on-error`), because shared runners' timings vary, and the [CI gate](#budgets-and-the-ci-gate) fails the job only at twice the budget.

**Measured** (2026-11-02, Godot 4.7.2 headless, Linux cloud machine):

```
perception bench: 40 actors, 600 frames: average 0.734 ms, p99 1.305 ms (budget 1.0 / 2.0 ms): OK
```

What keeps it cheap:

- each perceiver senses at its profile's `perception_hz` (default 10), with phases spread evenly so about a sixth of them sense each frame;
- a target beyond both sight and hearing reach is skipped until there is a meter for it;
- a sight ray is cast only for a target in range, in the cone, visible and lit enough.

## Simulation rings

**Budgets (from the design's ring section):**

- **LIGHT:** at most **0.3 ms per frame on average** for up to 40 LIGHT agents thinking at 1 Hz.
- **OFF_SCREEN:** at most **0.5 ms per frame on average, amortised**, for 200 agents thinking once per game hour (one game hour is two real minutes at 30× game speed).

**Bench:** `bench/rings_bench.gd` sets up 40 LIGHT agents (one area away from the player) and 200 OFF_SCREEN agents, each with a six-goal library. It runs one game hour: 7,200 frames at 60 frames a second and 30× game speed. It times each ring's thinking per frame with `BustleSimRings.last_timings`. It reports the agent counts, the simulated time, the engine version and the raw average and 99th percentile per ring, and exits 1 when an average is over budget.

```bash
godot --headless --path . -s res://bench/rings_bench.gd
godot --headless --path . -s res://bench/rings_bench.gd -- --light=40 --offscreen=400 --frames=7200
```

CI runs it on Ubuntu as a report at the budget (`continue-on-error`), like the perception bench, and the CI gate judges it at twice the budget.

**Measured** (2026-11-08, Godot 4.7.2 headless, Linux cloud machine):

```
rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min), Godot 4.7.2-stable (official): LIGHT average 0.150 ms p99 0.521 ms (budget 0.3), OFF_SCREEN average 0.221 ms p99 0.536 ms (budget 0.5): OK
```

What keeps it cheap:

- LIGHT and FULL agents think at their ring's rate, at a fixed per-agent phase, so a ring's thinking is spread across the second rather than landing in one frame.
- OFF_SCREEN agents think once per game hour, at a fixed per-agent minute.
- Catch-up runs at most seven game days of hourly thinking (168 thinks) per agent, and summarises anything older. This holds in `tick()` too (see below).

## Demo soak

**Checks:** no agent stuck (by the rule of `BustleStuckWatch`, the addon's stuck watch in `addons/bustle/debug/stuck_watch.gd`, which the demo harness uses) and the same timeline hash when the same seed runs again. These are deterministic, so they fail the run, not just report.

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

These are the small demos' numbers, not the 40 Full / 40 Light / 200 Off-screen budgets; those are the population bench's, below.

## Stuck watch

`BustleStuckWatch` (`addons/bustle/debug/stuck_watch.gd`, experimental) tells a stuck agent from one in a legitimate long activity. A host, a soak or a bench feeds it one observation per agent per step, with `observe()` (what the caller saw) or `observe_agent()` (read from a `BustleNpcState`, with `travel_hook` and `offscreen_progress_hook` for what the state can't show). It only reads, makes no rolls, and keeps one small row per agent watched plus one entry per stuck spell.

- **Rule:** more than `bound_minutes` (120) with no legitimate activity and no progress, the same goal failing `fail_loop` (3) steps in a row, or a mental state past its end. Moving more than `move_epsilon` (0.5 m) is progress. All three are proposed defaults, not tuning.
- **Off-screen:** catch-up still advancing within `ring_config.offscreen_interval_game_minutes` is legitimate by default. With `check_offscreen_progress`, an off-screen agent needs a new goal or step, a new place, a hop pending, something consumed or the progress hook instead.
- **Cost:** it does nothing until fed. Measured (2026-11-16, Godot 4.7.2 headless, Linux cloud machine): `observe_agent()` for 80 agents in view and 200 off-screen, every game minute for a game day, took about 6 µs a call, so about 1.6 to 1.8 ms for each minute's 280 calls. That is a debugging cost: watch every few game minutes, or a sample of agents, rather than every frame. No number here is a claim about a minimum machine.

## Population

**Budgets:** FULL brains and sequences ≤ 1.0 ms average and ≤ 2.0 ms p99 per frame at 60 fps (on top of perception's), LIGHT ≤ 0.3 ms a frame for 40 at 1 Hz, OFF_SCREEN ≤ 0.5 ms a frame amortised for 200 per game hour, and a save of ≤ 2 KB per agent. No agent stuck (`BustleStuckWatch`'s rule) over a game day.

**Bench:** `bench/population_bench.gd` builds a synthetic, neutral town of 40 FULL agents (indoors in the player's area), 40 LIGHT (next door) and 200 OFF_SCREEN (elsewhere), run through `BustleSimRings`. Every agent has six goals, each a two-step sequence of timed waits, scored from three needs that rise and fall on a fixed per-agent cycle from the seed, so choices and sequences keep changing with no rolls.

- **Timing:** one game hour at 60 frames a second and 30× game speed (7,200 frames). It reports each ring's average and p99 per frame from `last_timings`, the whole `tick` (which also re-sorts the rings when something calls for it), the static memory the town takes and the save size per agent (the society's export as JSON).
- **Stuck at scale:** then a game day, one game minute a tick (the real seconds a minute takes at 30×). Each minute every agent is watched: a step still inside its wait (plus the ring's think interval), or off-screen catch-up still advancing within the rings' `offscreen_interval_game_minutes`, is legitimate; anything else needs a new goal or step. That is the rule as written: an off-screen agent the rings keep caught up is never stuck here. `BustleStuckWatch.check_offscreen_progress` holds off-screen agents to goal, step or place progress instead (see "Stuck watch" above); the bench doesn't turn it on.

It exits 1 when an average or the FULL p99 is over budget, the save is over budget, or an agent was stuck. CI runs it as a report at the budget (`continue-on-error`): shared runners' timings vary, and **no number here is a claim about a minimum machine**. The CI gate judges it at twice the timing budgets, and at the save budget and no stuck agent exactly.

```bash
godot --headless --path . -s res://bench/population_bench.gd
godot --headless --path . -s res://bench/population_bench.gd -- --full=40 --light=40 --offscreen=200 --frames=7200 --days=1 --seed=1
```

**Measured** (2026-11-12, Godot 4.7.2 headless, Linux cloud machine, seed 1):

```
population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days: FULL average 0.272 ms p99 0.708 ms (budget 1.0 / 2.0), LIGHT average 0.130 ms p99 0.414 ms (budget 0.3), OFF_SCREEN average 0.195 ms p99 0.480 ms (budget 0.5), frame average 2.228 ms p99 3.933 ms, memory 5509.2 KiB (20148 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min: OK
```

The whole frame is more than the three rings' thinking: it also covers the per-agent loop and timing, and the re-sorts. Since 2026-11-12, `BustleSimRings.tick` re-sorts only when something calls for it (the player's area or a move of `resort_move` metres, a new game minute, a roster change, `request_sort()`, or `resort_hz`, 4 a second by default), and it keeps the society's sorted agent ids until its `roster_version` changes. It used to do both every frame. The whole frame has no budget of its own.

| Whole `rings.tick` frame, 40 / 40 / 200, seed 1 | Average | p99 |
| --- | --- | --- |
| Before, re-sorting every frame (local, two runs) | 1.95–1.97 ms | 3.49–3.65 ms |
| After (local) | 0.836 ms | 1.600 ms |
| Before (CI runner, run 43295066001) | 1.278 ms | 1.709 ms |

The rings' own thinking was unchanged or slightly lower (local, after: FULL 0.196 / 0.446 ms, LIGHT 0.107 / 0.303 ms, OFF_SCREEN 0.166 / 0.307 ms).

## Catch-up bound and FULL cap

**Catch-up in `tick()`.** An agent that stays OFF_SCREEN through a long clock jump never falls more than `catch_up_cap_game_days` (7) behind.

- The older time is summarised at once, split exactly as `catch_up()` splits it (whole intervals, the most recent week kept, a part interval carried over), through `summary_hook` and one `caught_up`.
- The kept week is then thought one interval a tick, as before, so a frame costs what it did.
- A 365-day jump costs 168 thinks per agent instead of 8,760.
- A clock that runs several game hours a frame is trimmed the same way.
- A backlog within the cap is untouched, so normal hourly thinking and the timings above don't change.

**FULL cap.** `max_full_bodies`, and `max_full_bodies_interior` in an interior, are optional. Both are 0 (no cap) by default.

- They limit the FULL ring, and so the FULL brains and, with `manage_bodies`, the bodies.
- The design's "FULL ≤ 40 bodies (≤ 12 per interior)" are **PROPOSED budgets, not addon defaults**: a host sets its own cap.
- Over the cap, the extra agents stay LIGHT, so they still think, at the LIGHT rate. The LIGHT ring grows by as many as the cap holds back.

The population bench takes the cap as `--max-full=N` and `--max-full-interior=N`, as bench parameters. Its 40 FULL agents are all in one interior, so the interior cap is the one that bites:

```bash
godot --headless --path . -s res://bench/population_bench.gd -- --max-full-interior=12
```

**Measured** (2026-11-14, 22:27 UTC, Godot 4.7.2 headless, Linux cloud machine, 2 vCPU Intel Xeon @ 2.10 GHz, seed 1), uncapped and then with an interior cap of 12:

```
population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days, Godot 4.7.2-stable (official), build 5fbc3e1c0981cf6049cfcb47d9a495981409aedf: FULL average 0.188 ms p99 0.530 ms (budget 1.0 / 2.0), LIGHT average 0.101 ms p99 0.324 ms (budget 0.3), OFF_SCREEN average 0.226 ms p99 0.532 ms (budget 0.5), frame average 0.870 ms p99 1.926 ms, memory 5548.6 KiB (20292 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min: OK
population bench: 12 FULL, 68 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days, Godot 4.7.2-stable (official), build 5fbc3e1c0981cf6049cfcb47d9a495981409aedf: FULL average 0.057 ms p99 0.228 ms (budget 1.0 / 2.0), LIGHT average 0.171 ms p99 0.465 ms (budget 0.3), OFF_SCREEN average 0.227 ms p99 0.548 ms (budget 0.5), frame average 0.826 ms p99 2.140 ms, memory 5548.6 KiB (20292 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min, FULL cap 0 (interior 12), held back by the cap 28: OK
```

With the cap, the 28 agents held back think as LIGHT, so LIGHT carries 68 agents rather than the 40 its budget is set for. Its average stays under the budget, but its p99 is above the uncapped one.

## Budgets and the CI gate

**The budgets** (ratified 2026-11-16), all in `bench/perf_budgets.gd`:

| Budget | Value | Bench |
| --- | --- | --- |
| Perception, 40 actors | 1.0 ms average, 2.0 ms p99 per physics frame | perception |
| FULL brains and sequences, 40 agents | 1.0 ms average, 2.0 ms p99 per frame | population |
| LIGHT, 40 agents at 1 Hz | 0.3 ms average per frame | rings and population |
| OFF_SCREEN, 200 agents once per game hour | 0.5 ms average per frame, amortised | rings and population |
| Save | 2 KB (2048 B) per agent | population |

The design's FULL body caps above stay PROPOSED: they are a host's choice, not one of these budgets.

**The gate.** The three report steps in CI run the benches at their budget configuration and stay report-only at the budget. The next step, `bench/perf_gate.gd`, reads their summary lines and fails the job when:

- a timing is over **`CI_HEADROOM` (2) times its budget**;
- the save is over its budget, or any agent was stuck (both deterministic, so no headroom);
- a bench printed no summary line, a number can't be read, or a bench didn't run its budget configuration.

It prints every number against its budget and its gate, and the machine it ran on. `tests/bench/test_perf_gate.gd` covers each rule.

**Why twice the budget.** Shared runners differ in speed from run to run. Here is what the same benches gave in CI over 100 green runs from 2026-11-12 to 2026-11-16 (GitHub's `ubuntu-24.04` runners; the population bench's line is in 95 of them):

| Number | Runs | Fastest | Median | Slowest | Slowest ÷ median | Budget | Slowest ÷ budget | Gate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Perception average (ms) | 100 | 0.376 | 0.595 | 1.075 | 1.81× | 1.0 | 1.07 | 2.0 |
| Perception p99 (ms) | 100 | 0.425 | 0.770 | 1.372 | 1.78× | 2.0 | 0.69 | 4.0 |
| Rings LIGHT average (ms) | 100 | 0.055 | 0.076 | 0.119 | 1.56× | 0.3 | 0.40 | 0.6 |
| Rings OFF_SCREEN average (ms) | 100 | 0.099 | 0.193 | 0.296 | 1.54× | 0.5 | 0.59 | 1.0 |
| Population FULL average (ms) | 95 | 0.103 | 0.146 | 0.239 | 1.64× | 1.0 | 0.24 | 2.0 |
| Population FULL p99 (ms) | 95 | 0.225 | 0.316 | 0.526 | 1.66× | 2.0 | 0.26 | 4.0 |
| Population LIGHT average (ms) | 95 | 0.056 | 0.080 | 0.127 | 1.59× | 0.3 | 0.42 | 0.6 |
| Population OFF_SCREEN average (ms) | 95 | 0.102 | 0.194 | 0.296 | 1.53× | 0.5 | 0.59 | 1.0 |
| Population save (B an agent) | 95 | 546 | 546 | 546 | 1.00× | 2048 | 0.27 | 2048 |

- The slowest run of a number is up to 1.81× its median, and up to 2.9× its fastest run (perception's average: 0.376 to 1.075 ms).
- One run put perception's average over its budget (1.075 ms), with no code change behind it, so a gate at the budget itself would fail on noise.
- At twice the budget, the slowest run seen of any number is at most 54% of its gate (perception's average, 1.075 of 2.0 ms). A false failure needs a runner another 1.86× slower than the slowest of those 100.
- A real regression that doubles a cost past its budget fails. The save size never varied, so it is gated at its budget.

A stored-baseline gate (a percentage over a recorded CI median) would catch smaller regressions on the numbers far under budget, but every runner change or deliberate cost would need a new baseline, and the 2.9× spread between runners would need about the same headroom. The budget is the contract, so the gate follows it.

**Running it.** `tools/perf_bench.sh` runs the three benches at their budget configuration, saves their lines in `build/perf/` and runs the gate (about 45 seconds on a 2-vCPU cloud machine). On Windows, run it from Git Bash with Godot 4.7.2 on `PATH` as `godot`:

```bash
tools/perf_bench.sh
```

## Reference machine

One measurement on a named reference machine, the maintainer's own Windows PC, recorded exactly as the maintainer reported it. It was run on commit `6a29f01e` with the same commands as `tools/perf_bench.sh`, from PowerShell. The `machine:` line is the OS, processor and Godot build as Godot reports them. "build unknown" is the population bench's own wording when it can't read the commit.

```text
machine: Windows 10.0.26200, Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz, 8 logical processors, Godot 4.7.2-stable (official)
perception bench: 40 actors, 600 frames: average 1.569 ms, p99 3.394 ms (budget 1.0 / 2.0 ms): OVER BUDGET
rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min), Godot 4.7.2-stable (official): LIGHT average 0.250 ms p99 0.818 ms (budget 0.3), OFF_SCREEN average 0.678 ms p99 2.000 ms (budget 0.5): OVER BUDGET
population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days, Godot 4.7.2-stable (official), build unknown: FULL average 0.522 ms p99 1.603 ms (budget 1.0 / 2.0), LIGHT average 0.267 ms p99 0.918 ms (budget 0.3), OFF_SCREEN average 0.746 ms p99 2.014 ms (budget 0.5), frame average 2.630 ms p99 6.386 ms, memory 5455.4 KiB (19951 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min: OVER BUDGET
perf gate (timings at 2.0x budget): OK
```

**Perception and OFF_SCREEN are over budget on the reference machine:**

- Perception: average 1.569 ms against 1.0 ms, and p99 3.394 ms against 2.0 ms.
- OFF_SCREEN: average 0.678 ms in the rings bench and 0.746 ms in the population bench, against 0.5 ms.

Both are within the 2× CI gate, so the gate passes. FULL, LIGHT, the save size and stuck agents are within budget.

Optimising perception and OFF_SCREEN is tracked as a follow-up. The budgets stay as ratified.

**Re-run pending:** perception and OFF_SCREEN ticking have since been optimised with no change in behaviour. A re-run of `tools/perf_bench.sh` on the reference machine is pending; the run above stays the recorded one until then.
