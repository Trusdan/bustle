# Conflict

Conflict (`addons/bustle/core/conflict/`) covers what agents do when trouble comes: fight, flee or fetch help, in the CRITICAL band, then go back to their usual goals.

## Who is a threat

`BustleConflict.notice(agent, other, now, nearby)` is called when an agent sees someone. Only someone the agent regards as **hostile through the disposition port** is a threat. A low opinion never makes anyone a threat.

The agent then takes a stance from its personality:

| Stance | When |
| --- | --- |
| `fight` | The average of its boldness and temper is at least `fight_threshold` (default 60). |
| `fetch_help` | Otherwise, when an ally in `nearby` is within `help_radius` (default 15 metres). |
| `flee` | Otherwise. |

An ally regards the agent as friendly, or shares its group without regarding it as hostile, and isn't in a conflict of its own. An agent is in at most one conflict at a time.

## Goals and actions

`fill_inputs(agent, inputs)` writes the stance as the inputs `threat.fight`, `threat.flee` and `threat.fetch_help` (1 for the stance, 0 for the others). They are erased when the conflict ends.

`BustleConflict.goal_defs()` gives three CRITICAL goals that read those inputs, each running one action. Register the actions on the agent's runner:

| Action | Class | What it does |
| --- | --- | --- |
| `fight` | `BustleFightAction` | Engages the threat through the combat port and outputs `attack_target`. When the port reports the fight resolved, `finish` reports it. |
| `flee` | `BustleFleeAction` | Outputs `move_to` straight away from the threat until it is `flee_distance` (default 10 metres) away. Without positions it gets away at once. |
| `fetch_help` | `BustleFetchHelpAction` | Outputs `move_to` and `talk_to` for the ally. Within 2 metres it hands over the threat: the ally fights, and the fetcher is out of the conflict. |

When a conflict ends, its inputs go and the agent's usual goals, such as its schedule, win again.

## Scuffles and lethal fights

- **Mostly scuffles:** a fight is a scuffle unless a seeded roll against `lethal_chance` (default 0.02) makes it lethal. The roll uses the world seed, the pair and the minute, so it's the same every time.
- **The combat port:** `BustleCombatPort.engage(id, target, lethal)` passes the mode on, and `outcome(id)` reports `{target, lethal, killed}`. The default resolves at once and never hurts anyone.
- **Scuffles never kill:** a host's combat passes scuffle damage through `filter_damage(damage, health, lethal)`, which always leaves the victim at least `scuffle_floor` (default 1) health.
- **Events:** every fight that ends emits `assaulted(attacker, victim, circumstances)`, and one that killed also emits `killed`. `circumstances` is `{cause, lethal, killed, at}`, where `cause` is `hostile`, `quarrel` or `help`. What follows from them, such as arrests, is for the host.

## Quarrels

`quarrel(a, b, now, nearby)` turns into a scuffle with a chance of `quarrel_chance × temper / 100` for `a` (default 0.3 at temper 100). When it does, `a` fights and `b` takes its own stance. Nobody becomes hostile.

## Saving

`export_state` and `import_state` save the conflicts in progress as plain data. Import refuses malformed data and changes nothing when it does.

## Settings (`BustleConflictConfig`)

| Setting | Default |
| --- | --- |
| `fight_threshold` | 60 |
| `help_radius` | 15 metres |
| `flee_distance` | 10 metres |
| `lethal_chance` | 0.02 |
| `scuffle_floor` | 1 |
| `quarrel_chance` | 0.3 |
