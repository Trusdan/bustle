# Life stages

`addons/bustle/modules/life_stages/` gives each agent an age and a life stage, lets a stage rule out goals and options, moves ages on with the clock, and carries the host's birth and death hooks. It is opt-in: with no module, or with the ageless default `BustleLifeStagePort`, nothing changes. Nothing is random: a stage comes from the age alone, and nobody is born or dies unless the host says so.

```gdscript
var stages := BustleLifeStages.new(rules)
if stages.error() != "":
	push_warning(stages.error())
for brain in brains:
	brain.life_stages = stages
stages.stage_changed.connect(func(id, old_stage, new_stage): host_on_stage(id, old_stage, new_stage))
stages.set_age(&"baker", rules.days_of(34.0))
stages.birth(&"newborn")              # at age 0
stages.advance_to(clock_minute)       # each tick, or once after a long skip
stages.note_death(&"smith", "illness") # the host decides; Bustle only records it
```

## Ages

Ages are game days. The host sets them with `set_age(id, days)`, as of the module's current minute (`now()`). A negative or non-finite age, an empty id or a dead agent is refused and changes nothing. `age_days(id)` and `age_years(id)` read an age back. An agent with no age has no stage and no gates.

`BustleLifeStageRules.days_per_year` (360, an experimental default) only converts with `days_of(years)` and `years_of(days)`. Bustle assumes no calendar: a host picks its own year length, or works in days throughout.

## Aging

`advance_to(minute)` moves every living age on to that game minute, at `BustleLifeStageRules.minutes_per_day` (1440, the default clock's day) minutes a day. Ages are closed-form: each is the age last set plus the minutes since, so one long catch-up call leaves exactly the state that many short calls would, day by day or minute by minute.

A step that crosses several stages fires `stage_changed` once per stage crossed, in order. Across agents, crossings fire in the order the ages reached them (ties in id order), so a catch-up fires the same signals in the same order as stepping. A minute before `now()` is refused; the same minute again is a no-op.

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

`validate()` runs once and its result is kept. After changing the rules in place, call `revalidate()`.

## Birth and death

These are the host's hooks; Bustle never calls them on its own.

- **`birth(id, days = 0.0)`** adds an agent at age 0, or at an age the host gives, emits `born(id, days)` and then `stage_changed` into its first stage. It returns why it was refused, or empty. It refuses an empty id, a known or dead agent, a bad age, an age below the first stage (so every birth starts in a stage) and invalid rules. A refused birth fires nothing.
- **`note_death(id, cause)`** records a death with a host string Bustle doesn't read (`"illness"`, say). It emits `died(id, cause)` once, then releases what the agent held:
  - its career, through `careers` (`BustleCareers.end`);
  - its job claim, through `jobs` (`BustleJobBoard.release`);
  - its roles, through `roles` (`BustleRolesPort.set_holder(role, "")`, in role-name order).

  Each release emits `vacated(id, kind, what)`, with `kind` one of `career`, `job` or `role`. Leave any of the three null to skip it. The career goes first, because careers ends a career on its own when its role changes hands. Nothing is refilled: that is the host's call.

  A dead agent stops aging and keeps its last stage. `set_age` and `birth` refuse it, and every goal and option is closed to it. `living_ids()` lists the agents still to schedule. `note_death` refuses an agent with no age, one already dead, or an empty cause.

## Gates

Set `BustleBrain.life_stages` to the module. Each tick, before choosing:

- a goal is blocked when its stage lists the goal's id, or any of its `BustleGoalDef.tags`, in `blocked_goal_tags`;
- an option is blocked when its stage lists any of its advertisement's tags in `blocked_affordance_tags`.

When several advertisements share an option id, the first one's tags count, as the scorer uses the first one too.

A blocked candidate is made ineligible with a `{"kind": "stage_gate", "stage": ...}` reason, so it is never picked; a goal running when its stage blocks it is dropped. Allowed goals and options are scored and chosen exactly as before. Orders aren't gated: an order is the host's call.

The port has the gate methods too (`allows_goal(id, tags)` and `allows_affordance(id, tags)`), true in the ageless default, so a host can put its own stage logic behind the brain instead.

## Saving

`export_state()` holds, in id order:

- every age (at `now()`);
- each age's anchor (`[days, minute]`), so aging after a load carries on exactly;
- every stage;
- every death (`{cause, at}`);
- `now`.

`import_state()` restores all of it without emitting anything. It also loads a version 1 save (ages and stages only, taken as of minute 0). It refuses a save, changing nothing, that has:

- another version;
- a bad age or anchor;
- a stage or death for an agent with no age;
- a stage id the rules don't have;
- a death with no cause.

A stage comes back as saved, even when it no longer matches the saved age because the rules changed between the save and the load. The next `set_age` or `advance_to` moves it on and emits once.

## In the demo

The harness's `enable_life_stages(rules)` gates every brain, logs `stage`, `born`, `died` and `vacated`, and stops stepping a dead agent. With `age_each_step` on, it calls `advance_to(now)` at the start of each step.
