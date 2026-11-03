# Perception

Bustle's perception module (`addons/bustle/modules/perception/`) is how every actor senses every other actor. It uses one set of rules for sight, hearing and light, whoever is looking and whoever is looked at. The rules and the world are headless: plain `RefCounted` and `Resource` classes with no nodes and no physics, and the host casts its own sight rays. Three node components wrap them for scenes (see "In a scene" below). Performance is covered in `docs/perf.md`.

Every default number is PROPOSED tuning. A project supplies its own resources.

## How visible and how loud

- **`BustleStealthRules`** (`Resource`): posture and movement factors, the stealth-skill reductions and floors, a light `Curve`, and the visibility clamp.
- **`BustleVisibilityModel.compute(light, posture, movement, wear_factor, skill)`:**

  ```
  visibility = clamp(light_curve(light) × posture × movement × wear
                     × max(skill_visibility_floor, 1 − skill × skill_visibility_reduction_per_point),
                     min_visibility, max_visibility)
  ```

- **`BustleNoiseModel.compute(base_radius, surface_factor, gear_factor, skill)`:**

  ```
  noise = base_radius × surface × gear × max(skill_noise_floor, 1 − skill × skill_noise_reduction_per_point)
  ```

- **`BustleNoiseModel.event_noise(radius, position, source_id)`** returns a **`BustleNoiseEvent`**, a one-off sound with no skill applied.

## Light

- **`BustleLightProbe`** (abstract): `sample(position)` returns a **`BustleLightSample`** (`level` 0..1 and the contributing `sources`).
- **`BustlePointLightProbe`** sums an `ambient` level and `energy × (1 − distance / range)²` for each enabled **`BustleLightSource`**, clamped to 1. An optional `occluded(from, to)` callable lets the host drop sources behind walls.

## Detection

- **`BustleSenseTarget`**: what the host reports about one target to one observer each tick. It holds `position`, `visibility`, `noise_radius`, `line_of_sight` (the host casts the ray) and `carries_light` (the target carries a lit light of its own).
- **`BustlePerceptionProfile`** (`Resource`, one per kind of observer):
  - senses: `sees`, `hears`, `sight_range`, `sight_angle_deg` (inner cone), `peripheral_angle_deg` (half-rate band) and `hearing_scale`;
  - light: `sight_light` (`AMBIENT`, or `CARRIED_LIGHT_ONLY` to see only targets carrying a light);
  - fill rates and decay;
  - the `suspicious_at` and `alert_at` thresholds;
  - `search_time` and `lose_track_time`;
  - `perception_hz` (throttling).
- **`BustleDetectionMeter`**: one per observer-and-target pair.
  - `tick(delta, observer_position, observer_forward, target)` fills from sight and hearing, and decays when neither reaches the target.
  - `hear_event(event, observer_position)` handles one-off sounds.
  - Fields: `level` (confidence), `state`, `last_known_position`, `seen_now`, `heard_now` and `since_sensed` (freshness).
  - `sight_cone(...)` is the geometry alone, so a host casts rays only for candidates in range and in the cone.
  - `light_allows(target)`, `is_unaware()`, and `export_state()` / `import_state()` (plain data, JSON-safe).
  - Signals: `state_changed(old, new)` and `noticed(position)`.

Fill rates:

```
sight   = fill_rate_sight × visibility × (1 − distance / sight_range) × cone
          (cone 1 inside sight_angle_deg, 0.5 out to peripheral_angle_deg, else 0;
           needs sees, line_of_sight, and a carried light under CARRIED_LIGHT_ONLY)
hearing = fill_rate_hearing × (1 − distance / (noise_radius × hearing_scale))
```

States:

```
UNAWARE ──level ≥ suspicious_at──▶ SUSPICIOUS ──level ≥ alert_at──▶ ALERT
   ▲                                   │                              │
   │                         level < suspicious_at      lost for lose_track_time
   │                                   ▼                              │
   └──── search_time, nothing new ── SEARCHING ◀──────────────────────┘
                                        │ level ≥ alert_at ──▶ ALERT
```

A heard `BustleNoiseEvent` raises the level to at least `suspicious_at`, moves the last known position to the event, and makes an unaware or searching observer suspicious.

## The world, actors and awareness

- **`BustlePerceptionActor`:** one actor. It has:
  - `id`, a stable id the host supplies (opaque to Bustle);
  - `position` (eyes and ears) and `forward`;
  - `profile` (null: it perceives nothing, but can still be perceived) and `perceivable`;
  - `visibility`, `noise_radius`, `carries_light` and `group` (for dispositions);
  - its `awareness`.

  The host keeps the fields current. Any actor can perceive any actor, with the same rules and numbers.
- **`BustleAwareness`:** one perceiver's awareness list. It holds one `BustleDetectionMeter` per target id, made the first time the target is sensed or heard. Its methods are `entry(id)`, `entries()`, `forget(id)` and `export_state()` / `import_state(data, profile)`, and it has a `state_changed(target_id, old, new)` signal.
- **`BustleAwarenessEntry`:** a snapshot of one target in the list:
  - `target_id`, `state`, `confidence` (the meter level) and `last_known_position` / `has_last_known`;
  - `seen_now`, `heard_now` and `perceived_now()`;
  - `freshness`, the seconds since the target was last sensed.
- **`BustlePerceptionWorld`:** the registry and the ticker.
  - `add_actor`, `remove_actor` (every perceiver forgets the removed actor), `actor(id)` and `actor_ids()`.
  - `line_of_sight`: the host's `func(from, to, perceiver_id, target_id) -> bool`. Unset, nothing blocks.
  - `tick(delta)` senses every perceiver whose turn it is. `sense(perceiver, delta)` senses one perceiver at once.
  - `broadcast(event, source_id)` sends a one-off sound to every hearer in reach. It lands on the meter for the actor that made it, else the event's `source_id`, else `NOISE_ID`.
  - Signal `perception_changed(perceiver_id, target_id, old_state, new_state)`, **on state changes only**. Memory and other systems can follow it instead of polling.

### Queries

| Query | Answers |
| --- | --- |
| `known_nearby(x, r)` | The targets X knows about (not unaware) whose last known position is within `r` of X. |
| `last_known(x, y)` | Where X last sensed Y (a `Vector3`), or `null`. |
| `perceives(x, y)` | Did X see or hear Y at its last sense? |
| `perceivers_of(y)` | Every perceiver that senses Y now. |
| `awareness(x)` | X's whole awareness list (`BustleAwarenessEntry`s, sorted by id). |
| `known_with(x, disposition)` | The targets X knows about that it regards as hostile, neutral or friendly (for example, who to fight). |
| `disposition_between(a, b)` | How A regards B. |

## Throttling

Each perceiver senses at its profile's `perception_hz` (default 10; 0 or less means every tick). Its first turn is staggered by a stable hash of its id, so perceivers don't all sense on the same tick. On its turn it senses with the time since its last turn. A target is skipped while it is beyond both sight range and hearing reach and the perceiver has no meter for it. Once there is a meter, it keeps ticking, so it decays. The sight ray is cast only for a target in range, in the cone, visible, and lit enough for the profile (`rays_last_tick` counts them).

## Dispositions

- **`BustleDispositionPort`** (in `ports/`) answers `disposition(a_id, a_group, b_id, b_group)` with `HOSTILE`, `NEUTRAL` or `FRIENDLY`. A host plugs in its own source by extending it. The standalone default is neutral everywhere, or reads a table if given one.
- **`BustleDispositionTable`** (`Resource`, in `society/`):
  - `groups` holds `"a>b"` rules for groups and `actors` holds `"a>b"` rules for actors; actor rules win;
  - `symmetric` (default on) lets a missing `"a>b"` fall back to `"b>a"`;
  - `same_group` covers two members of one group, and `default_disposition` covers anything unlisted.

  Changing a `.tres` value makes two actors hostile or neutral to each other with no code change.

Set `world.disposition` to the port to use.

## In a scene

- **`BustlePerceptionSystem`** (`Node`, group `bustle_perception_system`):
  - runs one `BustlePerceptionWorld`;
  - each physics frame (`step(delta)`) copies the components' state into the world, ticks it and casts the sight rays with physics (`sight_mask`, excluding the perceiver's and target's own bodies);
  - passes on `perception_changed` and records `last_tick_usec`.

  Put one in the scene or make it an autoload.
- **`BustlePerceiver`** (`Node3D`, at the actor's eyes, facing its −Z): `actor_id` (default: the parent's name), `profile`, `group`, and `awareness()`.
- **`BustlePerceivable`** (`Node3D`, about chest height): `actor_id`, `visibility`, `noise_radius`, `carries_light` and `group`. Its owner keeps them current, for example from `BustleVisibilityModel` and `BustleNoiseModel`.

A perceiver and a perceivable with the same id are one actor: the perceiver's position is used both for its senses and for being sensed, and the perceivable's group wins. Both find the first system in the tree unless their `system_path` points at one. They unregister when they leave the tree, and the actor leaves the world when neither component is left.
