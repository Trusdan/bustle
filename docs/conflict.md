# Conflict

Conflict (`addons/bustle/core/conflict/`) covers what agents do when trouble comes: fight, flee or fetch help, in the CRITICAL band, then go back to their usual goals.

Nothing in it is left to chance. Every fight starts from a **cause**, and every intent to kill has a **reason**. How often agents fight, or kill, follows from how often those causes and reasons come up. There are no random rolls.

## Causes

| Cause | How it starts |
| --- | --- |
| `hostile` | `notice(agent, other, now, nearby)`: the agent regards `other` as hostile through the disposition port. A low opinion never makes anyone a threat. |
| `quarrel` | `quarrel(a, b, now, provocation, nearby)`, called by the host. It comes to blows only past a threshold (see Quarrels). |
| `help` | A fetched ally fights for whoever fetched it. |

## Stances

| Stance | When |
| --- | --- |
| `fight` | The average of the agent's boldness and temper is at least `fight_threshold` (default 60). |
| `fetch_help` | Otherwise, when an ally in `nearby` is within `help_radius` (default 15 metres). |
| `flee` | Otherwise. |

**Allies:** an ally regards the agent as friendly, or shares its group without regarding it as hostile, and isn't in a conflict of its own.

**One at a time:** an agent is in at most one conflict.

**A fetched ally always fights,** whatever its own personality.

## Goals and actions

`fill_inputs(agent, inputs)` writes the stance as the inputs `threat.fight`, `threat.flee` and `threat.fetch_help` (1 for the stance, 0 for the others). They are erased when the conflict ends.

`BustleConflict.goal_defs()` gives three CRITICAL goals that read those inputs, each running one action. Register the actions on the agent's runner:

| Action | Class | What it does |
| --- | --- | --- |
| `fight` | `BustleFightAction` | Engages the threat through the combat port with the agent's intent, and outputs `attack_target`. Each tick it works the intent out again and engages again if it changed. When the port reports the fight resolved, `finish` reports it. |
| `flee` | `BustleFleeAction` | Outputs `move_to` straight away from the threat, aimed `flee_margin` (default 2 m) past `flee_distance` (default 10 m), so a body that stops a little short still gets there. Done once the agent is `flee_distance` away. Without positions it gets away at once. |
| `fetch_help` | `BustleFetchHelpAction` | Outputs `move_to` and `talk_to` for the ally. Within 2 metres it hands over the threat: the ally fights, and the fetcher is out of the conflict. If there's no ally, or the ally has a conflict of its own, the fetcher switches to fleeing. |

When a conflict ends, its inputs go and the agent's usual goals, such as its schedule, win again.

## Intent

Every fighter has an **intent**: `subdue` (the default) or `kill`. It can kill only for a reason:

| Reason | When |
| --- | --- |
| `defend_life` | Its threat means to kill it, **and** it is cornered (`cornered_of(agent, threat)`) or its life is in danger (`BustleHealthPort.is_life_threatened`). |
| Any reason from the host | `lethal_reason_of(agent, threat, cause)` returns a non-empty reason. The default gives none. |

Otherwise the intent is `subdue`, with the reason `none`.

**Escalation:** the intent is worked out again on every fight tick. A fight can escalate mid-way, for example when the agent's life comes under threat. Every change emits `intent_changed(agent, threat, intent, reason)`.

`intent_of`, `intent_reason_of` and `conflict_of` let a host or the inspector look at a conflict.

## The combat port and harm

- **Engaging:** `BustleCombatPort.engage(id, target, intent)` passes the intent on, and `outcome(id)` reports `{target, intent, killed, downed}`. The default resolves at once and never hurts anyone.
- **Immediate damage:** for now, a host's combat passes a `subdue` fight's damage through `filter_damage(damage, health, intent)`, which always leaves the victim at least `scuffle_floor` (default 1) health. This is a stopgap until the host's health system decides what blows do.
- **Death:** a victim can still die, in a subdue fight or later of its wounds. Accidents (harm beyond the intent), wounds and bleeding are the host's health system's business.

## Events

Every fight that ends emits `assaulted(attacker, victim, circumstances)`. One in which the victim died also emits `killed`, whatever the intent: a death in a subdue fight is reported too, for the host to judge.

`circumstances` is `{act, cause, cause_detail, intent, intent_reason, killed, at}`:

| Field | What it is |
| --- | --- |
| `act` | A fixed id for the fight: `act_id(attacker, victim, start minute)`. A host stores it on the wounds the fight causes, so a victim who dies later of them can be traced back to the fight. |
| `cause` | `hostile`, `quarrel` or `help`. |
| `cause_detail` | `{disposition}`, `{provocation, grudge, threshold}` or `{for}`. |
| `intent`, `intent_reason` | The intent at the end of the fight, and why. |
| `killed` | Whether the victim died. |
| `at` | The minute the fight ended. |

When someone dies, every conflict with them ends (`end_involving`). What follows a fight or a death, such as arrests, is for the host.

## Quarrels

`quarrel(a, b, now, provocation, nearby)` comes to blows only when `provocation + grudge(a, b) >= quarrel_threshold(a)`.

- **`provocation`:** 0 to 1, from the host (a harsh word, a shove).
- **`grudge(a, b)`:** 0 to 1. It's the sum of `a`'s negative opinion entries about `b` (most come from deeds), over `grudge_scale` (default 50), from the social port.
- **`quarrel_threshold(a)`:** follows `a`'s temper in straight lines, and a low mood lowers it (by up to a quarter at mood 0):

| Temper | Threshold |
| --- | --- |
| 0 | 1.4 |
| 50 | 1.0 |
| 100 | 0.6 |

The lowest the threshold can go is 0.45 (temper 100 at mood 0), so a single insult (about 0.2) with no grudge never starts a fight.

When a quarrel comes to blows, `a` fights and `b` takes its own stance. Nobody becomes hostile.

## Saving

`export_state` and `import_state` save the conflicts in progress as plain data, in id order. Import refuses malformed data and changes nothing when it does.

## Settings (`BustleConflictConfig`)

| Setting | Default |
| --- | --- |
| `fight_threshold` | 60 |
| `help_radius` | 15 metres |
| `flee_distance` | 10 metres |
| `flee_margin` | 2 metres |
| `scuffle_floor` | 1 |
| `quarrel_threshold_calm`, `quarrel_threshold`, `quarrel_threshold_hot` | 1.4, 1.0, 0.6 |
| `quarrel_mood_scale` | 0.25 |
| `grudge_scale` | 50 |
