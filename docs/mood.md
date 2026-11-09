# Mood and thoughts

The `needs_mood` module (`addons/bustle/modules/needs_mood/`) gives each agent a mood from 0 to 100 that moves toward a target. Thoughts set the target, and every thought keeps the reason it exists. This is part 1 of the module. Mental states, breaks and catharsis come later.

## Thoughts

A `BustleThoughtDef` (a Resource) describes one kind of thought:

| Field | Meaning |
| --- | --- |
| `id` | The thought's name. |
| `value` | Mood points it adds to the target (negative lowers it). |
| `duration_hours` | How long it lasts in game hours. 0 means it lasts while its condition holds. |
| `stack_limit` | How many can be active at once. Past the limit, a new one replaces the oldest. |
| `stack_mult` | Each repeat counts this much of the one before, so the n-th counts `stack_mult^(n-1)`. |
| `emotion` | The emotion it carries, for example `content`, `lonely` or `tense`. |
| `tags` | The modifier `thought.tag.<tag>` (base 1) multiplies its value. |
| `reason_kind` | `need`, `event`, `environment`, `trait` or `deed`. |
| `need`, `need_at_least` | For a need thought: it holds while that need's pressure is at least this. |

How a thought becomes active:

- **Timed:** `BustleMood.add_thought(def, details)` starts it now, and it expires at its minute. Durations are rounded to the nearest whole game minute, with at least 1 (`duration_minutes()`). Past the stack limit, the oldest of the same id goes and only the new one's timer starts.
- **Conditional:** `set_held(def, held, details)` holds or drops a thought with no duration.
- **From a need:** `sync_need_thoughts(needs, defs)` holds each need thought while its need is pressing.

`details` is plain data added to the reason, for example the id of the deed that caused it. Details that won't save as JSON are refused.

`is_valid()` accepts a definition only when it has an id, a finite value, a duration from 0 to 10 million hours, a stack limit of at least 1, a `stack_mult` from 0 to 1, a `need_at_least` from 0 to 1, and a known reason kind.

## Mood

A `BustleMood` holds one agent's mood.

- **Target:** the baseline plus every active thought (after stacking and tag modifiers), clamped to the config's range.
- **Approach:** mood moves toward the target at `rise_per_hour` (default 12) or `fall_per_hour` (default 8), both times `volatility`.
- **Sleep:** `advance_to(now, asleep)` leaves mood where it is while the agent sleeps. Thoughts still expire.
- **Cost:** `advance_to` is closed-form. It splits the time only where a thought expires, so a long off-screen step costs one step per expiry. A host splits a step wherever sleep starts or ends.
- **Per agent:** the modifiers `mood.baseline`, `mood.volatility`, `mood.rise.mult` and `mood.fall.mult` adjust the `BustleMoodConfig` defaults (baseline 50, range 0 to 100).
- **Dominant emotion** (`emotion`): the emotion with the largest total of absolute thought values. On a tie, the current one stays. It is updated at every expiry inside a step, so the result doesn't depend on step size.
- **Range:** mood starts, resets and stays inside the config's range, even when the baseline or a modifier is outside it. Bounds that aren't finite count as 0 and 100, and reversed bounds are swapped. A baseline that isn't finite counts as the middle of the range, and rates that aren't finite count as 0.
- **Reasons:** `reasons()` lists every active thought, strongest first, with its effective value, emotion, reason and end minute (-1 for a held thought).
- **Scorer:** `fill_inputs(inputs)` writes `mood` for the scorer's mood curves.
- **Saving:** `export_state` and `import_state(saved, defs)` save and load plain data. A host keeps it in `BustleNpcState.data`. Import refuses impossible data without changing anything. That includes:
  - a thought that `defs` doesn't have;
  - a start after the save's minute;
  - a held thought with an end, or a timed one without one;
  - an end before its start;
  - more of one thought than its stack limit;
  - a reason that isn't plain data.

  A timed thought that had already ended by the save's minute is dropped.

The config's numbers are a starting point, not tuning: a host sets its own.
