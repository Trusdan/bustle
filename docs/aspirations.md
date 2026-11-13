# Aspirations: wants and fears

`addons/bustle/modules/aspirations/` gives agents short-lived wants and fears formed by events. It is separate from ambitions (`docs/ambitions.md`), which keep working the same with it on or off. Nothing is random: wants and fears come only from causes and state.

Bustle ships no wants or fears. The demo's are data in `demo/aspirations/`.

## Using it

Each agent has its own `BustleAspirations`:

```gdscript
var aspirations := BustleAspirations.new(&"baker_1", config)
aspirations.update(now, personality, inputs, events, mood)
brain.score_boost = func(goal: StringName, option: StringName) -> float:
	return ambitions.boost(goal, option) * aspirations.avoidance(goal, option)
```

- **`inputs`** are the same circumstances and facts the host gives ambitions.
- **`events`** are the names of what happened to the agent since the last update.
- **`mood`** is optional. Without it, wants and fears still work and only the thoughts are skipped.

`update` runs in this order:

1. fulfils or expires wants;
2. ends fears;
3. forms fears from the events;
4. fills the automatic want slot.

## Wants

`BustleWantDef`:

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | Ties between equal scores break by id. |
| `auto` | true | False: only the host can give it. |
| `weights` | | Slider → weight: its score for the automatic slot is `Σ weight × (slider − 50) / 100`. |
| `requires` | | Circumstances that must all be true for it to be taken automatically. |
| `done_fact` | | A fact that fulfils it. |
| `progress_input`, `target` | | Or a number that fulfils it once it reaches the target. |
| `duration_hours` | 12 | How long it lasts before it expires unfulfilled. |
| `cooldown_hours` | 24 | How long after it ends before it is taken automatically again. |
| `thought` | | The satisfaction thought (a timed `BustleThoughtDef`). |

**How wants start.** While fewer than `auto_wants` (1) automatic wants are active, `update` takes the eligible want with the highest score:

- it must be automatic and every `requires` must be true;
- it must not already be fulfilled by the inputs;
- it must not be active or cooling down.

The host can also give one with `post_want(id, now)`. All wants together stay within `want_cap` (3). Both numbers are on `BustleAspirationConfig` and are experimental defaults.

**How wants end.**

- **Fulfilled:** when its fact or progress line holds at an update (checked before expiry), or when the host calls `fulfill(id, now, mood)`. Its satisfaction thought goes to the mood, following that thought's stack rules: a second fulfilment of a want that shares the thought refreshes it.
- **Expired:** when an update comes at or after its expiry minute. It expires with no thought.

Either way, the want is gone and its cooldown starts.

## Fears

`BustleFearDef`:

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | |
| `trigger` | | The event name that forms it. |
| `avoid_goals` | | Goals it makes the agent avoid, whatever the option. |
| `avoid_options` | | Options (objects, places, people) it makes the agent avoid. |
| `avoid_input` | | An input naming one more option to avoid, read when it forms (who or what caused it). |
| `avoid_mult` | 0.25 | What an avoided candidate's score is multiplied by, from 0 to 1. At 0, the candidate can't be chosen. |
| `duration_hours` | 72 | How long it lasts after it forms. At 0, it lasts until `cleared_fact`. |
| `cleared_fact` | | A fact that ends it early. |
| `thought` | | A thought added when it forms. |

- **Forming.** An update whose events include a fear's trigger forms that fear. If the fear is already formed, the trigger renews it from that minute.
- **Avoidance.** While formed, `avoidance(goal, option)` multiplies by `avoid_mult` for every fear that avoids the goal, the option, or the option named when it formed. With no fear it is 1, and it is never above 1, so fears only lower scores. Set it as (or multiply it into) `BustleBrain.score_boost`, where it applies last, inside the goal's band.
- **Ending.** It ends at an update at or after its end minute, or when its `cleared_fact` is true.

## Signals

- `want_added(agent, id, info)`
- `want_fulfilled(agent, id, info)`
- `want_expired(agent, id, info)`
- `fear_formed(agent, id, info)`, where `info.renewed` marks a renewal
- `fear_ended(agent, id, reason)`, where the reason is `expired` or `cleared`

## Saving

`export_state()` gives `{wants, fears, ended}`. Expiry and end times are absolute game minutes, so a want saved with an hour left expires an hour after the load. `import_state` refuses malformed data, or a want or fear the config doesn't have, and changes nothing.
