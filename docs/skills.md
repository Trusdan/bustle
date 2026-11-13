# Skills

`addons/bustle/modules/skills/` gives agents skill levels that grow with practice, fade without it, speed up and improve their work, and grow faster for a skill they have a passion for. Nothing in it is random: the same practice, time and personality always give the same levels and passions.

Bustle ships no skills. The host supplies every skill and passion as data. The demo's generic set is in `demo/skills/` (cooking, farming and crafts).

## Using it

```gdscript
var skills := BustleSkills.new(skill_defs, passion_defs)
society.set_port(&"skills", skills)
```

Without the module, `society.ports.skills` stays the default `BustleSkillSet`, and `level()` is 0 for everyone.

The host reports practice and time, and puts the skill in use into effect:

- `add_xp(id, skill, amount, personality)` when the agent does work of that skill. `personality` is only needed for derived passions (see below).
- `advance(id, minutes)` for time passing (see [Decay](#decay)).
- `apply(id, modifiers, using_skill, personality, mood)` whenever the skill in use changes, and after `add_xp` or `advance` if the host wants the modifiers to follow the new level at once. Pass an empty `using_skill` when the agent isn't working at a skill.
- `forget(id)` when an agent leaves the society.

`level(id, skill)` reads a level; other systems read it through the port.

## Skills

`BustleSkillDef` holds one skill. The numbers are configurable experimental defaults.

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | The host's id for it. |
| `max_level` | 20 | The top level. |
| `xp_curve` | `[100.0]` | XP for each level, from level 0 to 1 onwards. The last entry repeats. |
| `decay_floor` | 0 | The level decay stops at. |
| `decay_per_day` | 0 | Levels lost a game day while above the floor. |
| `speed_add` | 0.5 | Added to `work.speed` at the top level. |
| `quality_add` | 1.0 | Added to `work.quality` at the top level. |

Each agent keeps XP per skill as a float. The level is worked out from it: one whole level for each band of the curve paid for, plus the fraction of the next. For example, with `[100.0]`, 250 XP is level 2.5. XP past the top level isn't kept.

Reading a level walks the curve, so it costs in proportion to `max_level`. That is cheap at 20; a host that raises it a lot and reads levels every frame may want to cache them.

## Decay

`advance(id, minutes)` lowers each skill above its `decay_floor` by `decay_per_day` levels a day, and never below the floor. A skill at or below the floor doesn't change. Decay is in levels, so it doesn't depend on the curve. One long call gives the same levels as many short ones.

**Call `advance` for all elapsed game time, including time spent practising.** The module can't tell practised time from idle time, so decay is a steady drift, and practice adds its XP on top of it through `add_xp`. A skill grows while practice outpaces its decay and fades towards the floor when it doesn't. Set `decay_per_day` with that in mind.

## Passions

`BustlePassionDef` is a passion for one skill:

| Field | Default | Meaning |
| --- | --- | --- |
| `skill` | | The skill. Its `BustleSkillDef` must be installed first. |
| `learn_mult` | 1.5 | Practice XP is multiplied by this. |
| `sliders` | `{}` | Slider → weight, for deriving the passion from personality. |
| `thought` | null | A held thought (a `BustleThoughtDef` with a duration of 0) while the agent does that skill's work. |

An agent's passions are:

1. the passions the host assigned with `assign_passion(id, skill)`; or,
2. when it has none assigned, the passions derived from its personality sliders.

### Deriving passions from sliders

`derived_passions(personality)` scores each passion def that has `sliders`:

```
score = Σ weight × (slider − 50) / 100
```

This is the same scale the ambitions module uses. Every passion with a score of at least `passion_min_score` qualifies. They are ordered by score, highest first, with ties broken by skill id, and the first `max_derived_passions` are kept. Both are properties of `BustleSkills` and configurable experimental defaults:

| Setting | Default | Meaning |
| --- | --- | --- |
| `passion_min_score` | 0.2 | One slider at 70 with weight 1. An average agent (every slider at 50) has no passion. |
| `max_derived_passions` | 1 | The agent's single best match. |

Derived passions aren't stored. They follow the personality, which the host saves, so a trait that shifts a slider can change them. Assigning any passion stops derivation for that agent; removing the last one starts it again.

The demo's mapping, with weight 1.0 each:

| Passion | Slider |
| --- | --- |
| cooking | sociability |
| crafts | curiosity |
| farming | diligence |

So an agent with diligence 80 and every other slider at 50 has a passion for farming. With sociability 90 as well, cooking scores 0.4 against farming's 0.3, so cooking wins.

## Work speed and quality

`apply(id, modifiers, using_skill)` writes under the modifier source `skills`. It replaces anything that source wrote before, so `apply` can be called as often as needed. For the skill in use, at `level ÷ max_level` of the way to the top, it writes:

- `work.speed` and `work.speed.<skill>`: that share of `speed_add`, as an add;
- `work.quality` and `work.quality.<skill>`: that share of `quality_add`, as an add.

The per-skill keys are written only when the skill id is a valid key part (lower-case letters, digits and underscores). At level 0, nothing changes. These are the same keys mental states write, and the modifier set combines them: with a sulk's `work.speed` ×0.75 and a skill at the top level, `work.speed` from base 1 is `(1 + 0.5) × 0.75 = 1.125`. The host reads the keys; Bustle doesn't.

## The passion thought

If `mood` is passed to `apply` (a `BustleMood`, or anything with `set_held(def, held, details)`), `apply` holds the thought of the passion for the skill in use while the agent works at it, with `skill` in its reason. It drops every other passion thought. Several passions may share one thought. Without the needs_mood module, leave `thought` null and pass no mood.

## Saving

`export_state()` gives `{"xp": {agent: {skill: xp}}, "passions": {agent: [skill, ...]}}`, sorted. Only assigned passions are saved. `import_state(saved)` restores it and replaces what's kept now. It refuses (returns false, changing nothing) data that is malformed, names a skill or passion with no def, repeats a passion, or holds XP that is negative, not finite or past the top level. A save with no `passions` has no assigned passions.

The society's own save doesn't include skills; the host saves `skills.export_state()` next to it, as for the other modules.
