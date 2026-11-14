# Health

Agents react to their health, but Bustle keeps none of it. The host owns bodies, harm, illness, medicine and recovery, and reports them through `BustleHealthPort`. Bustle reads the port and responds: slower work and movement, thoughts, brain inputs, a downed agent kept from work and travel, and healers who ask the host to tend the sick. Bustle simulates no body parts and stores no wound, illness or body state. Nothing is random: the same readings give the same results.

All of it is opt-in. With the default port everyone is healthy, a tick does nothing, and no one tends.

## The port contract

`BustleHealthPort` (`society.ports.health`). A host extends it and overrides what it has.

| Method | Meaning | Default |
| --- | --- | --- |
| `is_injured(id)` | hurt | false |
| `is_incapacitated(id)` | downed: can't act at all | false |
| `is_life_threatened(id)` | life in danger now | false |
| `capacity(id, name)` | how much of a capacity is left, 1 full to 0 none; names are the host's (`moving`, `manipulation`, `consciousness` in the defaults) | 1 |
| `pain(id)` | 0 (none) to 1 | 0 |
| `needs_care(id)` | how urgently care is needed, 0 to 1 | 0 |
| `is_contagious(id)` | can pass an illness on | false |
| `visible_tags(id)` | what others can see, as tags (`sick`, `fever`) | none |
| `care(healer, patient)` | a request: the host decides, does the care and returns true when it did | false |

`care` is the only write Bustle makes, and it is a request. How much it helps, and how fast anyone recovers, is the host's.

## The behaviour

`BustleHealthBehaviour.new(config, society.ports)`. It keeps nothing between ticks; its only fields are its config and ports. Each tick, for each agent, call `tick(id, modifiers, mood, inputs)`, or its three parts:

- **`apply(id, modifiers)`**: capacities below full scale modifier keys, under the source `health`. Each `BustleHealthEffect` maps a capacity to a key with the multiplier `at_zero + (1 − at_zero) × capacity^power`, and effects on one key multiply. Every named capacity also writes `capacity.<name>` as its amount. At full health nothing is written. Bustle doesn't move bodies or run work, so the host reads `work.speed` and `move.speed` (base 1), the same as skills and moods write them.
- **`sync(id, mood)`**: holds the pain thought for the highest pain line reached, and a thought for each visible tag that has a rule, then drops the others. When the port clears, so do the thoughts. A mood is optional; without one, `sync` just returns the thought ids.
- **`fill_inputs(id, inputs)`**: sets `health.pain`, `health.needs_care`, `fact.downed` and `fact.contagious`, each only while non-zero, so goals can read them.

Thoughts are held thoughts (duration 0) with the reason kind `health`. They are saved with the mood, and a tick after loading adds no second copy. The behaviour itself has nothing to save.

### Illness events

The host can also report an illness as it happens:

- `illness_began(id, tag, mood)` holds that tag's thoughts at once;
- `recovered(id, mood)` drops at once every tag thought whose tag the port no longer shows. A tag still shown (in `visible_tags`) keeps its thought, so recovering from one illness doesn't clear another.

The next `sync` follows the port's `visible_tags` again, so the port stays the truth: report the tag there too for as long as the illness lasts.

## The downed gate

Set `brain.gate = health.allows`. While an agent is downed, it never chooses a goal or option tagged with any of `BustleHealthConfig.downed_blocks` (`work` and `travel` by default). A goal is matched by its id or tags, and an option by its advertisement's tags. A blocked candidate is ineligible, with a `gate` reason. Once the agent is up again, nothing is blocked.

Orders aren't gated. An order is the host's call, so the host should stop ordering a downed agent.

## The tend job

`BustleTendJob.new(health, nearby)` lets an able agent tend someone near it who needs care.

- **Who can be tended:** `nearby` is `func(healer) -> Array[StringName]`, the host's answer to who is around (for example the agents in its area). Without it, nobody tends.
- **Choosing the patient:** `patient_for(healer)` is the nearby agent, not the healer itself, with the highest `needs_care` above 0 (ties in id order). A downed healer has no patient.
- **Scoring:** `fill_inputs(healer, inputs)` sets `fact.tend` to that patient's urgency, so the tend goal scores in proportion to it.
- **The goal:** `BustleTendJob.goal_def(minutes)` is the `tend` goal: band `PERSONAL`, tags `tend` and `work`, scored by `fact.tend` in a straight line.
  - It runs the `tend` action, then waits `minutes` (30 by default), so care is asked for at most that often.
  - A refused request waits the same before the goal can be chosen again.
- **The action:** register `BustleTendAction.new(job)` for `tend` on each healer's runner. It names the patient in the output (`tend`) so the host can move and animate the healer, and calls `job.tend(healer, patient)`. That asks the host through `care()` and emits `tended(healer, patient, done)`.
- **Who doesn't tend:**
  - A busy agent: duty, an urgent need or an order outranks a personal goal.
  - A downed agent: it gets no `fact.tend`, and the goal's `work` tag is blocked by the downed gate.

A doctor is just a role the host gives. To keep tending to certain agents, give the tend goal only to their libraries, or answer `nearby` only for them.

## Config defaults

`BustleHealthConfig.defaults()`. These are experimental values; change any of them.

| Setting | Default |
| --- | --- |
| Effects | `moving` → `move.speed`; `manipulation` → `work.speed`; `consciousness` → `work.speed` and `move.speed`. Each is a straight line to 0 (`at_zero` 0, `power` 1). |
| Pain thoughts | `in_pain` (−6) from pain 0.2; `in_great_pain` (−14) instead from 0.6 |
| Tag thoughts | `sick` → `feeling_sick` (−8); `fever` → `feverish` (−6) |
| Downed blocks | `work`, `travel` |
| Tend wait | 30 minutes (`BustleTendJob.goal_def(minutes)`) |

`config.validate()` returns why a config can't be used, or empty. With an invalid config the behaviour does nothing.
