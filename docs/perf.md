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
