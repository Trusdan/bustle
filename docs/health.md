# Health

Agents react to their health, but Bustle keeps none of it. The host owns bodies, harm, illness, medicine and recovery, and reports them through `BustleHealthPort`. Bustle reads the port and responds: slower work and movement, thoughts, brain inputs, a downed agent kept from work and travel, and healers who ask the host to tend the sick. Bustle simulates no body parts and stores no wound, illness or body state. Nothing is random: the same readings give the same results.

All of it is opt-in. With the default port everyone is healthy, a tick does nothing, no one tends, no one seeks care, no one rests for illness and no one fetches a healer.

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

Host snippets for this goal, resting when sick and fetching a healer are in [host-hooks.md](host-hooks.md#seeking-care-and-resting-when-sick).

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

## The rest-when-sick goal

`BustleRestSick.new(health, sick_tags)` (experimental) makes an agent who is ill rest instead of working or running errands, until the health port says it is better. Bustle names where to rest. The host moves the body and owns the illness and the recovery. Nothing about illness is kept: every answer comes from the ports each time.

- **Who rests:** an agent the port shows one of `sick_tags` for (`visible_tags`), or one of whose capacities is below its line in `capacity_lines` (`capacity`). `sickness(agent)` is how ill it is, 0 to 1: `tag_weight` for a listed tag, and `capacity_weight` × (line − capacity) / line for each capacity below its line, whichever is highest. `fill_inputs(agent, inputs)` sets `fact.rest_sick` to that.
- **Who doesn't:** a downed agent (as for seeking care), a locked one (`is_locked`, for example `society.is_locked`), and, when `seek_care` is set, one that should seek care first.
- **Its place:** band `BustleRestSick.BAND` (65), above duty (60) and below orders (70). It outranks ordinary work, errands and free time, but never an order, a lock or an urgent need (80). Orders aren't gated: an order still runs.
- **Where:** `bed_for(agent)` picks the agent's own item (`BustlePropertyPort.items_of`) that relieves `bed_need` the most, at a place the world port knows. The agent goes there first (`move_to`, judged by `where` within 2 metres or by `can_reach`), and otherwise rests where it stands. A bed with no `where` or `can_reach` warns once and isn't used, the same as a care place.
- **Resting:** register `BustleRestSickAction.new(rest)` for `rest_sick`. It names the bed in the output (`rest_sick`: the item, or empty where the agent stands) and runs while the agent should rest.
- **Ending:** it is done on the first tick after the port clears the tag or restores the capacity, and the goal stops being eligible at the same time.
- **The goal:** `BustleRestSick.goal_def(band)`, the `rest_sick` goal, tagged `rest_sick` and `travel` (so the downed gate blocks it too) and scored by `fact.rest_sick` in a straight line.

### Resting and seeking care together

The two goals are separate, and each works alone. When both are in an agent's library and both are eligible:

- **By default,** resting wins. It sits in a higher band (65) than seeking care (`PERSONAL`, 40), so an ill agent rests and doesn't go for care.
- **With `rest.seek_care = seek`,** seeking care comes first. While `seek.wants_care(agent)` holds, the agent isn't eligible to rest, so it goes to the healer and waits there. Once its need for care is below the seek-care threshold (or there is nowhere to go), it rests until the port says it is better.
- **Shared rules:** both skip a downed agent and carry `travel`. Both take their settings as properties and their goal's band as a `goal_def` argument. Both judge a place by `where` within 2 metres or by `can_reach`, and drop a place they can't judge with one warning.

## Fetching a healer

`BustleFetchHealer.new(health, care_roles)` (experimental) sends a bystander for a healer when an agent is downed or urgently needs care and no healer is near. The bystander moves and arrives by the same rule as fetching help in a fight, then tells the healer, and the tend job does the rest. Bustle names who and where; the host moves the bodies and gives the care.

- **Patients:** `urgency(patient)` is `downed_weight` (1) for a downed agent, else `care_weight` (1) × its `needs_care` when that is at or above `urgent_at` (0.8), else 0. A dead patient (`is_dead`, for example `life_stages.is_dead`) needs no healer.
- **Healers:** the holders of `care_roles` and whoever `healers` (`func() -> Array[StringName]`, for example the agents with the tend goal) names, never the patient and never a downed agent. Who may tend stays the host's call.
- **Starting an errand:** `notice(bystander, patient, now)`, or `look(bystander, now)` over the `nearby` hook, starts one to the healer nearest the patient who isn't already summoned to another patient. All of these must hold:
  - the patient needs a healer and no errand or summons is under way for it;
  - no healer is within `reach` (15 metres) of the patient;
  - the bystander isn't the patient or a healer, isn't downed, isn't busy (`is_busy`, for example with an order) and has no errand.

  Positions come from `where`, else the world port's position of the agent's area.
- **The errand:** register `BustleFetchHealerAction.new(fetch)` for `fetch_healer`. It uses `BustleFetchHelpAction.approach()`, the rule the conflict's `fetch_help` action uses:
  - while more than 2 metres from the healer, it asks the host to move there (`move_to`, `talk_to`);
  - once there, or at once without positions, it tells the healer.

  The patient is named in the output (`fetch_healer`).
- **The healer:** on arrival the healer is summoned:
  - `summoned_to(healer)` names the patient, and `fact.summoned` is set to its urgency;
  - `nearby_with_summons(base)`, given as the tend job's `nearby`, adds the patient to whom the unchanged tend job can choose;
  - connect the tend job's `tended` signal to `fetch.tended` to end the summons once care is given.
- **One summons per healer:** a healer keeps the first summons it gets. A bystander who arrives at a healer that was summoned to another patient meanwhile ends its errand (`healer_busy`) and leaves that summons alone. A later errand for the second patient goes to the next-nearest free healer, or waits until the healer's summons ends.
- **Ending:** an errand ends (`errand_ended`) when the patient recovers (`recovered`) or dies (`dead`), the bystander is downed (`bystander_downed`), the healer can no longer be fetched (`no_healer`) or is already summoned (`healer_busy`), or the host calls `drop(patient)` (`dropped`). A summons ends when the patient is tended, recovers, dies or is dropped. For a patient who is up, "recovers" means its `needs_care` falls below `urgent_at`: the summons then ends quietly, even while the healer is on its way, and seeking care (from its own, lower threshold) can carry on from there.
- **The goal:** `BustleFetchHealer.goal_def(band)` is the `fetch_healer` goal:
  - band `URGENT` by default ("help someone in trouble"), so it outranks orders and duty once started, but a bystander busy with an order doesn't start one;
  - tags `fetch_healer` and `travel`, so the downed gate blocks it too;
  - scored by `fact.fetch_healer` in a straight line.
- **Saving:** errands and summons are saved (`export_state()`, version 1).

### How the three goals fit together

Each goal works alone, and they share their shape:
- **Settings:** properties, with the constructor taking the behaviour and the main list.
- **Band:** an argument to `goal_def`.
- **Downed guard:** a downed agent never takes one, and each carries `travel`.
- **Hooks:** `where` and the other hooks warn once when they return the wrong type.

They act for different agents:

| Goal | Who | Band (default) |
| --- | --- | --- |
| `fetch_healer` | a bystander, for a downed or urgent patient | `URGENT` (80) |
| `rest_sick` | an ill agent, instead of working | 65 |
| `seek_care` | a patient who can walk to care | `PERSONAL` (40) |

- **A downed patient** takes none of them. A bystander fetches a healer, and the healer's tend job comes to it.
- **A patient who is up and urgent** (at or above `urgent_at`) may be fetched for by a bystander, and may also seek care itself. With `rest.seek_care` set, it seeks care before resting; otherwise it rests, and the fetched healer comes to it.
- **A healer** is never a bystander for a patient it could tend, and a bystander's errand ends once the healer is told.

## Work that needs a minimum capacity

A posted work type can name the least of each capacity a taker needs (`BustleWorkType.min_capacities`, experimental; see [work.md](work.md)), for example `{&"moving": 0.5}` for hauling. The job board reads `capacity()` through the health port:

- an agent below a minimum isn't offered the work and can't claim it (`refusal()` gives `capacity:<name>`);
- an agent who drops below one while holding a claim lets go of it at the next `settle()` or `work()`, with the usual `released`.

No type has minimums by default, and the default port reports everyone fully able, so nothing changes until the host sets them.

### With the three goals

The health gates on work and the three goals read the same port, each for its own purpose:

- **Resting when sick** keeps an ill agent away from work in the brain's bands. Its `capacity_lines` (PROPOSED: `consciousness` below 0.5) are separate from a work type's minimums. An agent can be well enough not to rest but still below a heavy job's minimum: it isn't offered that job, and takes lighter work or other goals. An agent who rests without dropping below a minimum keeps its claim and comes back to it. One who drops below a minimum loses the claim at the next update.
- **A downed agent** (for example `consciousness` 0) keeps a claim only if its work type names no minimum it fails. To have downed agents let go of all work, give work types a minimum on the capacity the host lowers when an agent is downed.
- **Seeking care and fetching a healer** don't touch the board. A healer who holds a claim still answers a summons or tends through its tend goal, by band, and keeps its claim unless its own capacities drop below a minimum.

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
| Rest-when-sick tags and lines | PROPOSED: tag `sick`; `consciousness` below 0.5 (`sick_tags`, `capacity_lines`) |
| Rest-when-sick weights | PROPOSED: 1 for a tag, 1 for a capacity at 0 (`tag_weight`, `capacity_weight`) |
| Rest-when-sick band | PROPOSED: 65, between duty and orders (`BustleRestSick.BAND`, `goal_def(band)`) |
| Rest-when-sick bed | none (`bed_need`): the agent rests where it stands until the host names a need its beds relieve |
| Fetch-a-healer lines and weights | PROPOSED: urgent from `needs_care` 0.8; 1 for downed, 1 per unit of need (`urgent_at`, `downed_weight`, `care_weight`) |
| Fetch-a-healer reach | PROPOSED: 15 metres, as the conflict's `help_radius` (`reach`); arrival within 2 metres (`BustleFetchHelpAction.REACH`) |
| Fetch-a-healer band | `URGENT` (`BustleFetchHealer.goal_def(band)`) |

`config.validate()` returns why a config can't be used, or empty. With an invalid config the behaviour does nothing.
