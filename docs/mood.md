# Mood and thoughts

The `needs_mood` module (`addons/bustle/modules/needs_mood/`) gives each agent a mood from 0 to 100 that moves toward a target. Thoughts set the target, and every thought keeps the reason it exists. Mental states (see below) build on it.

## Thoughts

A `BustleThoughtDef` (a Resource) describes one kind of thought:

| Field | Meaning |
| --- | --- |
| `id` | The thought's name. |
| `value` | Mood points it adds to the target (negative lowers it). |
| `duration_hours` | How long it lasts in game hours. 0 means it lasts while its condition holds. |
| `stack_limit` | How many can be active at once. Past the limit, a new one replaces the oldest. |
| `stack_mult` | Each repeat counts this much of the one before, so the n-th counts `stack_mult^(n-1)`. |
| `emotion` | The emotion it carries, for example `content`, `lonely` or `tense`. |
| `tags` | The modifier `thought.tag.<tag>` (base 1) multiplies its value. |
| `reason_kind` | `need`, `event`, `environment`, `trait` or `deed`. |
| `need`, `need_at_least` | For a need thought: it holds while that need's pressure is at least this. |

How a thought becomes active:

- **Timed:** `BustleMood.add_thought(def, details)` starts it now, and it expires at its minute. Durations are rounded to the nearest whole game minute, with at least 1 (`duration_minutes()`). Past the stack limit, the oldest of the same id goes and only the new one's timer starts.
- **Conditional:** `set_held(def, held, details)` holds or drops a thought with no duration.
- **From a need:** `sync_need_thoughts(needs, defs)` holds each need thought while its need is pressing.

`details` is plain data added to the reason, for example the id of the deed that caused it. Details that won't save as JSON are refused.

`is_valid()` accepts a definition only when it has an id, a finite value, a duration from 0 to 10 million hours, a stack limit of at least 1, a `stack_mult` from 0 to 1, a `need_at_least` from 0 to 1, and a known reason kind.

## Mood

A `BustleMood` holds one agent's mood.

- **Target:** the baseline plus every active thought (after stacking and tag modifiers), clamped to the config's range.
- **Approach:** mood moves toward the target at `rise_per_hour` (default 12) or `fall_per_hour` (default 8), both times `volatility`.
- **Sleep:** `advance_to(now, asleep)` leaves mood where it is while the agent sleeps. Thoughts still expire.
- **Cost:** `advance_to` is closed-form. It splits the time only where a thought expires, so a long off-screen step costs one step per expiry. A host splits a step wherever sleep starts or ends.
- **Per agent:** the modifiers `mood.baseline`, `mood.volatility`, `mood.rise.mult` and `mood.fall.mult` adjust the `BustleMoodConfig` defaults (baseline 50, range 0 to 100).
- **Dominant emotion** (`emotion`): the emotion with the largest total of absolute thought values. On a tie, the current one stays. It is updated at every expiry inside a step, so the result doesn't depend on step size.
- **Range:** mood starts, resets and stays inside the config's range, even when the baseline or a modifier is outside it. Bounds that aren't finite count as 0 and 100, and reversed bounds are swapped. A baseline that isn't finite counts as the middle of the range, and rates that aren't finite count as 0.
- **Reasons:** `reasons()` lists every active thought, strongest first, with its effective value, emotion, reason and end minute (-1 for a held thought).
- **Scorer:** `fill_inputs(inputs)` writes `mood` for the scorer's mood curves.
- **Saving:** `export_state` and `import_state(saved, defs)` save and load plain data. A host keeps it in `BustleNpcState.data`. Import refuses impossible data without changing anything. That includes:
  - a thought that `defs` doesn't have;
  - a start after the save's minute;
  - a held thought with an end, or a timed one without one;
  - an end before its start;
  - more of one thought than its stack limit;
  - a reason that isn't plain data.

  A timed thought that had already ended by the save's minute is dropped.

The config's numbers are a starting point, not tuning: a host sets its own.

## Mental states

A `BustleMentalState` holds one agent's mental state: which state it's in, if any, and when that started and ends. It decides and records states. What agents do in them is `BustleMentalBehaviour` (see "Behaviour").

Everything follows from the agent's mood, personality and circumstances. There's no chance, no timer between episodes and no limit shared between agents, so any number of agents can be in a state at once.

`update(now, mood, personality, circumstances)` does the work. The host calls it after advancing the mood. `circumstances` is `{locked, indulgence, target, target_opinion, target_rival}`:
- whether the agent is locked to a task (the host's `is_locked`);
- whether it knows an indulgence;
- who it dislikes nearby;
- its opinion of that person, 0 to 100 (50 when not given);
- whether the host marks them as a rival.

### The states

`BustleMentalConfig.states` holds `BustleMentalStateDef` resources, in tie-break order.

| State | Kind | Weights | Needs | Lasts |
| --- | --- | --- | --- | --- |
| withdraw | low | sociability −2, diligence −1 | | 8 h |
| sulk | low | temper +1, sociability −1 | | 12 h |
| wander | low | curiosity +1, diligence −1 | | 24 h |
| binge | low | greed +1 | an indulgence | 8 h |
| lash_out | low | temper +2, boldness +1, plus dislike | someone disliked, or a rival, nearby | 12 h |
| high_spirits | high | sociability +1 | | 8 h |
| inspired | high | diligence +1, curiosity +1 | a match (below) | 12 h |

A state's `behaviour` is one of the `Behaviour` enum: withdraw, sulk, wander, binge, lash out, high spirits or inspired. Nothing else can be expressed. There's no field for harming anyone, the agent included, or for any intent, and lashing out is words only.

### Starting

A state can only start when the agent is in none, isn't locked, and mental states are on.

- **Low states** start when mood is below the break threshold:
  - The threshold is `break_threshold` (30) plus the `mental.break_threshold` modifier, so traits can move it.
  - Each eligible low state scores `Σ weight × (slider − 50) / 100`. Lashing out adds `dislike_weight × (50 − target_opinion) / 100`.
  - The highest score wins. Ties go to the earlier state, so quieter states win.
  - Binge needs an indulgence; without one, it's skipped.
  - Lashing out needs a target the agent dislikes (opinion below `dislike_line`, 50) or a rival. A target it likes, or doesn't dislike, doesn't count, so lashing out is skipped and the next-highest state wins.
- **Tier:** a low state records its tier: `extreme` below 1/7 of the threshold (about 4), `major` below 4/7 (about 17), otherwise `minor`.
- **Inspiration** starts when mood is above `inspired_above` (90) and the agent matches: diligence or curiosity above 50, or a trait that adds the `mental.inspired` modifier.
- **High spirits** start otherwise when mood is above `high_spirits_above` (80).
- **Inspiration beats high spirits.** An agent in high spirits whose mood rises far enough to be inspired leaves high spirits (`replaced`) and becomes inspired.

### Ending

A state ends when its duration is up (`ended`) or when mood recovers early (`recovered`):
- a low state once mood rises to the threshold plus `recover_margin` (40 by default);
- high spirits below `high_spirits_exit` (75);
- inspiration below `inspired_exit` (85).

A state that ends doesn't start another in the same update. At the next update, an agent still below the line can start one; there's no cooldown.

**Catharsis.** When a low state ends, the agent gets the catharsis thought, an aftermath only. It adds +20 mood for 2 game days and stacks up to three times, each repeat counting half the one before. Nothing stops another state starting.
- `catharsis_def()` gives its thought def. A host passes that def with its other thought defs when it loads a mood.

**Events.** `state_entered(agent, id, info)` and `state_exited(agent, id, reason)` are generic. `active()` returns `{id, kind, tier, since, until}`.

### Switching off and saving

- **Off switch:** `bustle/simulation/mental_states` is a project setting for developers and tests (default on, `BustleMentalConfig.allowed()`). It isn't a game option.
  - With it off, or with the agent's own `enabled` false, no state starts and an active one ends (`disabled`, without catharsis).
- **Saving:** `export_state()` and `import_state(saved)`. Import refuses an unknown state, a wrong kind or tier, or an end that isn't after the start, without changing anything.

The numbers are configurable experimental defaults, not tuning.

### Behaviour

`BustleMentalBehaviour.new(society)` acts out the states of a whole society. Call `update(agent, now, mood, personality)` instead of the state's own `update`. It builds the circumstances, updates the agent's `BustleMentalState` (`state_of(agent)`) and sets the state's modifiers.

- **Circumstances:**
  - `locked`: `is_locked(agent)`, the same hook crime uses (made with a society, its `is_locked`, see [locks](locks.md));
  - `indulgence`: `indulgence_of(agent)` names an affordance;
  - `target`, `target_opinion` and `target_rival`: from `lash_target(agent)` (below).
- **Modifiers:** while an agent is in a state and not locked, `state_modifiers` for it are set on its mood's `BustleModifierSet` under the source `mental_state`. They're swapped whenever the active state changes (high spirits giving way to inspiration included), and removed when the state ends, a lock starts or `import_state` loads other states. `applied_state(agent)` says whose rows are on.

  | State | Modifiers |
  | --- | --- |
  | withdraw | `tag.social.mult` ×0.2 |
  | sulk | `tag.social.mult` ×0.6, `work.speed` ×0.75, `dialogue.curt` +1 |
  | binge | `tag.indulgent.mult` ×3 |
  | lash out | `dialogue.curt` +1 |
  | high spirits | `tag.social.mult` ×1.5, `social.generosity` +1 |
  | inspired | `work.speed` ×1.25, `work.quality` +1 |

  `work.*`, `dialogue.curt` and `social.generosity` are for the host to read.
- **Goals:** `goal_defs()` gives `mental_withdraw`, `mental_wander`, `mental_binge` and `mental_lash_out`, in the guarded band (75). Urgent self-care outranks them; orders and duty don't. Each is eligible while `fill_inputs(agent, inputs)` sets `fact.mental.<state>` to 1, and runs the `mental` action (`BustleMentalAction`). The action names where to go; the host moves the body.
  - **withdraw:** goes home (`home_of`) and stays (`withdrawn` in the output), and turns others away. `accepts(agent, visitor, opener)` is false while it's withdrawn and not locked, unless `opener` is one of `welcome_openers` (`comfort`, so a friend's comfort still gets through).
    - For conversations, set `BustleConversation.accepts` to it: `run` then returns `turned_away`, and a `converse` step fails with `turned_away`.
    - Bustle has no visits of its own. A host's visits ask `accepts` (or read the `withdrawn` output) and turn the visitor away.
  - **wander:** walks to `wander_to(agent, now)`, by default the agent's neighbouring areas in turn.
  - **binge:** uses its indulgence (`use_affordance`).
  - **lash out:** goes to its target (`talk_to`), insults it and is done.
  - Sulk, high spirits and inspired are modifiers only.
- **Locks:** while `is_locked` holds, no state starts, the goals aren't eligible and the modifiers are off. When the lock ends, the state is evaluated again.
- **Lashing out** is words only.
  - `lash_target(agent)` is someone else in the same area, within `lash_radius` (30 m, by `position_of`, by default the area's position), who is disliked (opinion below `dislike_line`) or a rival. Rivals come first, then the lowest opinion, then by id. An agent insults its target once within `lash_reach` (2 m); without known positions, both fall back to their area's position, so the insult lands at once.
  - Each person can be insulted `insults_per_victim` times (1) an episode; a new episode starts afresh.
  - With nobody to lash out at, lash out isn't eligible, so another state wins, or, once it's started, its goal stops.
  - `insult(agent, target, now)` emits `insulted(agent, target, provocation)`. The provocation is by tier: minor 0.2, major 0.4, extreme 0.6.
  - With a `conflict`, the insulted agent then quarrels through the usual fight rules (`BustleConflict.quarrel`), which start every fight at subdue. Nothing here sets any intent.
- **Comfort:** `in_low_state(agent)` is for `BustleComfort.low_state_of` (see social docs).
- **Saving:** `export_state()` and `import_state(saved)` cover every agent's state and this episode's insults.
- **Cost:** `lash_target` looks at every agent in the society, and runs for each agent's update, so the cost grows with the square of the population. That's fine at town sizes; a host with many more agents can pass fewer through `update`.
