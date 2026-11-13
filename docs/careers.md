# Careers

`addons/bustle/modules/careers/` gives standing jobs ranks. A career is not a second job: it is the agent's standing job (a role with a routine, see `docs/schedules.md`) held at a rank of a track. Each rank sets the wage of the career block. Performance from mood, skill and attendance leads to promotion or demotion after a configured number of working days, decided by a host hook.

Nothing is random: the same mood, skill and attendance always give the same reviews. Agents with no career keep their job, routine and wages exactly as before.

## Using it

```gdscript
var careers := BustleCareers.new(career_defs, roster, society.ports)
careers.assign(&"clerk_1", &"office", &"junior", now)
```

Each tick (or at least every few game days), call `careers.update(id, now, mood)` for every agent with a career, where `mood` is its `BustleMood` (or null). After the role changes and loading, the module keeps itself in step with the roster.

Only the host puts an agent on a track. A new holder of a role is not enrolled automatically. An agent can hold one career at a time.

## Tracks and ranks

`BustleCareerDef` is one track, as host data:

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | The host's id. |
| `role` | | The standing role it ranks. Only an agent whose job is this role can be on it. Several tracks may share a role. |
| `skill` | none | The skill its ranks ask for and performance reads. |
| `activity` | | The routine activity that is the career block. |
| `off_site` | **true** | The agent is away while it attends the career block. Set it to false for a track worked on site. |
| `ranks` | | `BustleCareerRank`s, lowest first. |

`BustleCareerRank`, with experimental defaults:

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | Unique in its track. |
| `wage` | 0 | What one attended career block earns. It replaces the block's own wage; 0 means the rank is unpaid. |
| `min_skill` | 0 | The skill level needed to hold it. |
| `review_days` | 7 | Working days (days with a career block) in each review window. Days off don't count. |
| `promote_if` | 0.75 | A window's performance at or above this makes a promotion due. |
| `demote_if` | 0.35 | At or below this, a demotion is due. Must be below `promote_if`. |

## The career block

The rank's wage goes on the agent's schedule as `BustleSchedule.wages[activity]`. It is fixed into the block when the agent attends and paid at the block's end through the usual `settle`, once, and only if attended. A missed block pays nothing. A rank change pays from the next block attended.

`is_away(id, now)` is true from when the agent **attends** an off-site career block until the block ends. An agent that is late stays in the world until it turns up, and one that misses the block is never away. The host takes an away agent out of the world; Bustle has no map of its own.

A career ends when the agent's job is no longer the track's role. That happens when the role passes to someone else, and also when the agent takes another job while still holding the role (another role with a routine that sorts first). The job itself stays. Ending a career restores the block's own wage.

## Performance

`update` closes each whole game day once that day's career blocks have all ended. A day with a career block (a working day) is scored from 0 to 1 with `day_performance`. A day with no career block (a day off) is skipped: it adds no score and doesn't count toward the window, so good days off can't lift a window of missed shifts.

```
performance = (mood_weight × mood + skill_weight × skill + attendance_weight × attendance)
              ÷ (the sum of the weights used)
```

| Term | From 0 to 1 | Weight (default) |
| --- | --- | --- |
| mood | The mood given to `update`, within its range (0 to 100 by default). With no mood, `neutral_mood` (0.5). | `mood_weight` 0.4 |
| skill | The track's skill level now ÷ `skill_full` (10), at most 1. Left out for a track with no skill. | `skill_weight` 0.3 |
| attendance | The day's career blocks: (on time + `late_credit` × late) ÷ blocks, with `late_credit` 0.5 and missed counting 0 (from `BustleSchedule.report`). | `attendance_weight` 0.3 |

All of these are properties of `BustleCareers` and configurable experimental defaults. For example, at skill 5 and on time every day, mood 90 scores `0.4 × 0.9 + 0.3 × 0.5 + 0.3 × 1 = 0.81`, and mood 20 scores 0.28 less (0.53). So low mood lowers performance linearly, by `mood_weight` per unit of mood range.

`performance(id)` is the mean of the current window so far.

## Reviews

When a window has `review_days` working days, the agent is reviewed at the end of the last one. The window's mean is compared with the rank's thresholds:

- **At or above `promote_if`:** if there is a next rank and the agent has its skill minimum, `promotion_due` is emitted and the hook is asked. If it grants the promotion, the agent takes the next rank: its wage goes on the career block, and `promotion_granted` is set (see below). If there is no next rank, the agent lacks the skill, or the hook refuses, the outcome is a good review and the rank stays.
- **At or below `demote_if`:** if there is a lower rank, `demotion_due` is emitted and the hook is asked. If it grants the demotion, the agent takes the lower rank. Otherwise the outcome is a poor review.
- **In between:** steady.

A new window starts after every review. After a change of rank, it starts the next day. A demotion applies even if the agent is below the lower rank's skill minimum; ending a career is the host's call.

**The hook.** `review_hook` is `func(id, career, from_rank, to_rank, kind) -> bool`, where `kind` is `promoted` or `demoted`. It returns true to grant. With no hook set, every change is granted. The employer's staffing and pay policy goes here.

- **Refusing delays the change.** A refusing hook leaves the rank as it is, the next window starts at once, and the hook is asked again after that window if the agent is still due.
- **The hook only answers.** It must not change careers itself (`assign`, `end` or a change of role); make such changes after `update` returns.

**Ambitions.** `fill_inputs(id, inputs)` sets the fact `promotion_granted` from a granted promotion until the agent's next review, so the `get_promoted` ambition completes.

**Signals.**

- `promotion_due` and `demotion_due` fire before the hook.
- `career_changed(id, career, old_rank, new_rank)` fires on every start, change and end.
- `reviewed(id, career, performance, outcome, at)` fires after every review, with outcome `promoted`, `demoted`, `good_review`, `poor_review` or `steady`.

`update` also returns `{at, performance, outcome, rank}` for each review.

**Thoughts.** With the needs_mood module, set `thoughts` (outcome → a timed `BustleThoughtDef`) and pass the agent's mood to `update`. A review then adds the thought for its outcome, with the career and rank in its reason. Without the module, leave `thoughts` empty and pass no mood; only the signals fire.

## Catch-up

A day closes only once its career blocks have ended, so its attendance can't change afterwards. Reviews happen at day boundaries, whenever `update` is called. Given the same mood, skill and attendance, one long `update` over a window gives the same reviews and state as daily or hourly ones.

Two limits apply:

- The mood and skill used are those passed at the call. A long catch-up applies one mood to every day it closes.
- The schedule keeps only 7 days of attendance, so call `update` at least that often.

## Saving

`export_state()` gives `{agent: {career, rank, since, closed, window, promoted}}`, which covers the rank and the review clock (the last closed day, the window so far, and whether a promotion was just granted).

`import_state(saved)` replaces every career and puts the rank wages back on the career blocks. It refuses (returns false, changing nothing) data that:

- is malformed;
- names an unknown track or rank;
- has a window value outside 0 to 1.

A save without the review clock starts it afresh from `since`.

Import doesn't check who holds which role or skill minimums, and emits no signals. Restore the roles and roster first, then careers, then tick.
