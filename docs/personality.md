# Personality

Personality (`addons/bustle/core/personality/`) is what makes agents differ: 8 sliders every agent has, plus up to 3 traits. All of it is data. No trait has code; modules read its effects by modifier key.

## Sliders

`BustlePersonality.SLIDERS` lists the 8 sliders:

- `sociability`
- `boldness`
- `diligence`
- `greed`
- `piety`
- `temper`
- `honesty`
- `curiosity`

Each runs from 0 to 100, and 50 is average.

- `set_slider(name, value)` sets one.
- `slider(name)` reads one, including every trait's shift.
- `fill_inputs(inputs)` gives them to the scorer as `trait.<slider>`, from 0 to 1, for goal considerations.

## Traits

A `BustleTraitDef` (a Resource) bundles:

- `excludes`: traits it can't be combined with, checked both ways round.
- `adds` and `mults`: modifier keys, such as `need.company.rate`, `need.money.weight`, `tag.social.mult`, `social.crowd_tolerance`, `mood.baseline`, `mood.volatility` and `thought.tag.social_pos`.
- `slider_offsets`: shifts to the sliders.
- `needs` and `goals`: needs and goals only agents with this trait have.
- `thoughts`: permanent thoughts, as thought definitions from the mood module with no duration.

`BustlePersonality.add_trait(def)` adds a trait. It returns `""` on success, or one of these reasons:

- `invalid`: the trait isn't valid data;
- `already`: the agent has it;
- `excluded`: it excludes, or is excluded by, a trait the agent has;
- `full`: the agent already has 3 traits.

## Putting traits into effect

`apply(modifiers, needs, library, mood)` puts the traits into effect. Pass null for any of these to skip it.

| Target | What applying does |
| --- | --- |
| Modifier set | Adds each trait's modifiers, one source per trait. |
| Need set | Adds each trait's needs. |
| Goal library | Adds each trait's goals. |
| Mood | Holds each trait's permanent thoughts, with the reason `{kind: trait, trait: <id>}`. |

Applying again after `add_trait` or `remove_trait` adds only what's new, and removes only what a removed trait brought. A need, goal or thought the agent already had before a trait wanted it (the same need id, the same goal resource, or a thought id the mood already holds) is never added again, never owned by the personality and never removed by it.

A trait's thoughts must be held thoughts, with no duration.

`export_state` and `import_state(saved, defs)` save and load the sliders and trait ids. Import refuses unknown traits, or traits that can't be combined, and changes nothing when it does.

## Demo traits

`demo/traits/` holds five neutral traits:

| Trait | What it does |
| --- | --- |
| Loner | Company builds slowly; crowds start at 2 people and drain fast. Social options count less and quiet ones more. Excludes outgoing. |
| Outgoing | Company builds fast; crowds start at 12 people. Social options count more. Mood rests higher and changes faster. Excludes loner. |
| Low-spirited | A permanent "heavy heart" thought of −12. Mood lifts slowly. Social and indulgent options count less and quiet ones more. |
| Greedy | Money pressure builds faster and weighs more. Shifts greed up. |
| Pious | Adds a devotion need and an observance goal. Shifts piety up. |

The tests give five agents the same day and the same evening options, with one of these traits each. They pick a walk alone, the common room, the porch with one neighbour, an odd job and evening prayer.

A low-spirited trait is a way of weighing things, not something to fix. It sets a lower baseline and a slower lift, and the addon has no mechanic that cures it.
