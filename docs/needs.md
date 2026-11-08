# Needs

The needs engine (`addons/bustle/core/needs/`) turns time and circumstances into need pressures, from 0 (fine) to 1 (urgent). The scorer reads them as `need.<id>` inputs. Bustle ships no needs of its own: a host defines them as data.

## A need

`BustleNeedDef` (a Resource) holds:

- `id`: the scorer reads it as `need.<id>`.
- `rate_per_hour`: the rise in pressure per game hour.
- `rises_when`: the conditions under which the base rate applies. Empty means always.
- `condition_rates`: condition → extra change per hour while that condition holds. Negative values fall; for example, a need for rest falls while `asleep`.
- `curve`: the response curve the scorer applies to the pressure (`BustleNeedSet.apply_curves`).
- `start`: the pressure an agent starts with.

Every number defaults to 0, so nothing happens until a host sets it.

## One agent's needs

A `BustleNeedSet` holds one agent's needs.

- `advance(minutes, conditions, modifiers)` moves every pressure on, then clamps it to 0..1. The changes are linear, so one long step equals many short ones under the same conditions (off-screen agents use this).
- **Conditions** are plain names the host passes each step, such as `awake`, `asleep`, `alone`, `in_company` and `crowded`.
- **Profile:** the modifier `need.<id>.rate` (base 1) scales how fast a need rises. It never changes how fast it falls.
- **Using an option:** `relieve(id, amount)` lowers a pressure and `raise(id, amount)` raises one (a side effect).
- `fill_inputs(inputs)` writes `need.<id>` for every need into the senses' inputs.
- `add_need` and `remove_need` let traits add needs.
- `export_state` and `import_state` save and load plain data. A host can keep it in `BustleNpcState.data`.

## The social pair

Two needs cover loners and extroverts with the same rules:

- One need rises while the agent is `alone` (wanting company).
- The other rises while it is `crowded` (wanting to be alone).

`BustleNeedSet.social_conditions(people_near, crowd_tolerance)` decides which condition holds: `alone` when no one is near, `crowded` when more people are near than the tolerance, and `in_company` otherwise. The tolerance is the modifier `social.crowd_tolerance` (base 6), read by `BustleNeedSet.crowd_tolerance(modifiers)`.

| Personality | Company need rises | Crowd need rises | Crowd tolerance |
| --- | --- | --- | --- |
| Loner | slowly | fast | low |
| Extrovert | fast | slowly | high |

Both rows come only from data and modifiers.

## Leisure

`BustleLeisure` keeps agents varying what they do for fun.

- **Kinds:** each kind (a tag on options, listed in `kinds`) has a tolerance from 0 to 1.
- **Using a kind:** each `use(kind)` adds `tolerance_per_use` to that kind's tolerance (default 0.25).
- **Recovery:** `advance(minutes)` lowers every tolerance by `tolerance_decay_per_day` per game day (default 0.5).
- **Scoring:** `adjust(ad)` scales an option's leisure relief by `1 − tolerance`. At or past `boredom_threshold` (default 0.75) the relief drops to 0, so the scorer turns to another kind.

With the defaults, a kind still gives relief on its third use in a day and none on the fourth. The defaults are a starting point; a host sets its own.
