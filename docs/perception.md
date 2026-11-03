# Perception

Bustle's perception module (`addons/bustle/modules/perception/`) is how every actor senses every other actor. It uses one set of rules for sight, hearing and light, whoever is looking and whoever is looked at. This page covers the headless core: plain `RefCounted` and `Resource` classes with no nodes and no physics. The perceiver and perceivable components, the awareness list and its queries come in a later change.

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
