# Health

Agents react to their health, but Bustle keeps none of it. The host owns bodies, harm, illness, medicine and recovery, and reports them through `BustleHealthPort`. Bustle reads the port and responds: slower work and movement, thoughts, brain inputs, a downed agent kept from work and travel, and healers who ask the host to tend the sick. Bustle simulates no body parts and stores no wound, illness or body state. Nothing is random: the same readings give the same results.

All of it is opt-in. With the default port everyone is healthy, a tick does nothing, no one tends and no one seeks care.

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

## The seek-care goal

`BustleSeekCare.new(health, care_roles)` (experimental) lets an agent who needs care go to someone, or somewhere, that can give it. Bustle names where. The host moves the body, gives the care and owns the recovery. Nothing about health is kept: every answer comes from the ports each time.

- **Who seeks care:** an agent whose `needs_care` is at or above `threshold` (0.5), who isn't downed and who has somewhere to go. `fill_inputs(patient, inputs)` sets `fact.seek_care` to its need, so the goal scores higher the more urgent the care. A threshold outside 0 to 1 warns once and 0.5 is used.
- **Where:** `destination_for(patient)` picks the holder of the first of `care_roles` that is held (`BustleRolesPort.holder_of`), skipping the patient itself and a downed holder. If none is held, it falls back to `care_place`, a place the world port knows (`has_place`). With neither, the agent doesn't seek care. Who counts as a healer stays the host's call: name the roles, and give them to whom it chooses.
- **Getting there:** register `BustleSeekCareAction.new(seek)` for `seek_care` on each agent's runner.
  - While the agent is on its way, the action names the target in the output (`seek_care`) and asks the host to move the agent: `move_to` is the target's position, and `talk_to` is the healer when the target is a person.
  - Positions come from `where` (`func(id) -> Vector3 or null`), or else the world port's position of the agent's area.
  - It stops once the agent no longer needs to seek care (it recovered or is downed). It fails with `no_care` when there is nowhere to go.
- **Arriving:** a healer is reached in its area (`area_of`). A care place is reached within 2 metres of it (by `where`). `can_reach` (`func(patient, target) -> bool`) replaces both. A care place without `where` or `can_reach` warns once and isn't used, since its arrival couldn't be told.
- **Being tended:** once there, the patient waits (30 minutes by default, then the goal can be chosen again). A healer whose tend job counts the patient as `nearby` (for example by area) now finds it and asks the host to care. The tend job is unchanged.
- **The goal:** `BustleSeekCare.goal_def(minutes, band)` is the `seek_care` goal:
  - band `PERSONAL` by default, so duty, urgent needs and orders outrank it;
  - tags `seek_care` and `travel`, so the downed gate blocks it too;
  - scored by `fact.seek_care` in a straight line;
  - it runs `seek_care`, then waits `minutes` (30). A failed run waits the same before the goal can be chosen again.

With the default port, or without the goal in an agent's library, nothing changes.

## Config defaults

`BustleHealthConfig.defaults()`, which `BustleHealthBehaviour` uses when it is given no config. A new `BustleHealthConfig` resource starts empty instead: no effects and no thoughts, so health changes nothing until the host adds some. Change any of these values.

| Setting | Default |
| --- | --- |
| Effects | `moving` → `move.speed`; `manipulation` → `work.speed`; `consciousness` → `work.speed` and `move.speed`. Each is a straight line to 0 (`at_zero` 0, `power` 1). |
| Pain thoughts | `in_pain` (−6) from pain 0.2; `in_great_pain` (−14) instead from 0.6 |
| Tag thoughts | `sick` → `feeling_sick` (−8); `fever` → `feverish` (−6) |
| Downed blocks | `work`, `travel` |
| Tend wait | 30 minutes (`BustleTendJob.goal_def(minutes)`) |
| Seek-care threshold | 0.5 (`BustleSeekCare.threshold`) |
| Seek-care roles and place | none (`care_roles`, `care_place`): nobody seeks care until the host names them |
| Seek-care reach | 2 metres from a care place (`BustleSeekCare.REACH`); a healer in its area |
| Seek-care wait and band | 30 minutes, `PERSONAL` (`BustleSeekCare.goal_def(minutes, band)`) |

`config.validate()` returns why a config can't be used, or empty. With an invalid config the behaviour does nothing.
