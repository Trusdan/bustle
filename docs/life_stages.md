# Life stages

`addons/bustle/modules/life_stages/` gives each agent an age and a life stage, and lets a stage rule out goals and options. It is opt-in: with no module, or with the ageless default `BustleLifeStagePort`, nothing changes. Nothing is random; a stage comes from the age alone.

```gdscript
var stages := BustleLifeStages.new(rules)
if stages.error() != "":
	push_warning(stages.error())
for brain in brains:
	brain.life_stages = stages
stages.stage_changed.connect(func(id, old_stage, new_stage): host_on_stage(id, old_stage, new_stage))
stages.set_age(&"baker", rules.days_of(34.0))
```

## Ages

Ages are game days. The host sets them with `set_age(id, days)`. A negative or non-finite age, or an empty id, is refused and changes nothing. `age_days(id)` and `age_years(id)` read an age back. An agent with no age has no stage and no gates.

`BustleLifeStageRules.days_per_year` (360, an experimental default) only converts with `days_of(years)` and `years_of(days)`. Bustle assumes no calendar: a host picks its own year length, or works in days throughout.

Ages don't advance by themselves yet. Ticking them on the clock (and catching up after a long step) comes later; until then the host calls `set_age` when an age should change.

## Stages

A `BustleLifeStageDef` is an `id`, a `min_days` and two lists: `blocked_goal_tags` and `blocked_affordance_tags`. The rules list the stages youngest first. An agent is in the last stage whose `min_days` its age has reached, and in no stage when it is younger than the first.

`validate()` returns why a set can't be used, or empty when it can. It rejects:

- no stages;
- a missing stage, or one with no id;
- an id used twice;
- a `min_days` that is negative or not finite, or not above the previous stage's;
- an empty blocked tag;
- a `days_per_year` that is not finite or not above 0.

With rules that aren't valid, the module stays ageless: `set_age` is refused, there are no stages and nothing is blocked. `error()` gives the reason.

`stage_changed(id, old_stage, new_stage)` fires once per real change, including the first age set (from no stage). An age that stays in its stage fires nothing.

## Gates

Set `BustleBrain.life_stages` to the module. Each tick, before choosing:

- a goal is blocked when its stage lists the goal's id, or any of its `BustleGoalDef.tags`, in `blocked_goal_tags`;
- an option is blocked when its stage lists any of its advertisement's tags in `blocked_affordance_tags`.

A blocked candidate is made ineligible with a `{"kind": "stage_gate", "stage": ...}` reason, so it is never picked; a goal running when its stage blocks it is dropped. Allowed goals and options are scored and chosen exactly as before. Orders aren't gated: an order is the host's call.

The port has the gate methods too (`allows_goal(id, tags)` and `allows_affordance(id, tags)`), true in the ageless default, so a host can put its own stage logic behind the brain instead.

## Saving

`export_state()` holds every age and stage, in id order. `import_state()` restores them without emitting `stage_changed`, and refuses a save (changing nothing) with another version, a bad age, a stage for an agent with no age, or a stage id the rules don't have. A stage comes back as saved; if the rules have changed since, the next `set_age` moves it on and emits once.

## Not yet

Ticking ages on the clock with catch-up, birth and death hooks, and vacating roles on death come in a later part. They will build on `set_age` and `stage_changed`.
