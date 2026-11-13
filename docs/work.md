# Work

Bustle has two kinds of work:

- **Standing jobs** are roles with routines (see `docs/schedules.md`): a baker holds the `baker` role, follows its schedule and is paid at the end of each attended shift. `BustleWorkPort.job_of(id)` reads them, with or without a board.
- **Posted work** is one-off tasks on a `BustleJobBoard` (`addons/bustle/core/jobs/`): a harvest that needs doing, an errand, a repair. An agent claims a posting, does it, and is paid once.

The board never turns into employment: a standing job stays a role. Nothing on the board is random. The same postings, agents and clock always give the same claims.

## Work types

`BustleWorkType` is host data. Bustle ships none; the demo's are in `demo/jobs/`.

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | | The host's id. |
| `skill`, `min_skill` | none, 0 | The skill it uses, and the least level a taker needs (read through the skill port). |
| `required_role` | none | A role the taker must hold (read through the roles port). |
| `required_tags` | none | Tags the taker must all have. |
| `priority` | 0 | The score every agent starts from. |
| `priority_weights` | none | Slider → weight: adds `Σ weight × (slider − 50) / 100`. |
| `need_weights` | none | Input → weight: adds `Σ weight × input` (for example how much the agent needs money). |
| `xp_per_hour` | 10 | Practice in `skill` per hour of work. |
| `wage` | 0 | Paid on completion, in the trade port's unit. |
| `minutes` | 60 | How long the work takes. |
| `place` | none | Where it's done, unless a posting says otherwise. |

The numbers are configurable experimental defaults. The score uses the same slider scale as ambitions and passions.

## The board

```gdscript
var board := BustleJobBoard.new(work_types, society.ports)
society.ports.work.board = board
var job := board.post(&"harvest", &"farm", now, due)
```

A posting lasts until it's **completed**, **released** (open again), **cancelled** by its employer or **expired** at its `due` minute (claimed or not). A claim has no timeout: it ends only in one of those ways. When an agent abandons work in the host's world, the host calls `release`.

**Gates.** An agent (a `BustleJobSeeker`: its id, personality, inputs and tags) can claim a posting only if it holds the required role, has at least the minimum skill level, and has every required tag. A missing or null port counts as none: no roles are held and every skill is 0.

**Claims.** A claim is exclusive, and an agent holds at most one at a time. `claim` is atomic. `best_for(seeker)` is the eligible open posting the agent wants most, with ties going to the earlier posting. Generated ids compare in natural order, so `job_2` comes before `job_10`.

When several agents want one posting in the same tick, the highest score wins, and ties go to the lower agent id. There is no host or employer override.

## With a brain

The board only ranks work. It never leaves out work an agent dislikes; the agent's brain weighs that against its other goals.

1. **Advertise.** Each tick, before the brain ticks, call `board.advertise(seeker, senses)`. It adds one advertisement per posting the agent can claim, or only the one it holds. Each advertisement:
   - has the posting id as its option;
   - relieves the need `job` by the posting's **appeal**, `clamp(appeal_base + score, 0, 1)` (`appeal_base` is 0.5, an experimental default);
   - carries the tag `job`, so a trait or mental state can scale work with `tag.job.mult`.

   It also sets the input `need.job` to 1. Work an agent dislikes has a low appeal, down to 0, so its other goals win.
2. **A job goal.** Give agents a goal with `uses_advertisements = true` in the band where work should compete. The demo uses free time (`PERSONAL`), so scheduled duty still comes first. Keep posting options to that goal only, and other options away from it, through the brain's `score_boost`, as with other agents for people goals.
3. **Request and settle.** When the brain picks a posting the agent doesn't hold, call `board.request(seeker, job)`. After every agent has ticked, call `board.settle(now)`. Each requested posting goes to the highest score, with ties going to the lower agent id. The others choose again next tick.
4. **Work.** While the brain holds the job goal on its claim, call `board.work(seeker, minutes)` each tick. This adds progress, which is kept if the claim is released. It also adds practice through the skill port when that port can take it (`xp_per_hour × hours`, so the skills module applies passions). Once the type's `minutes` are done, the posting completes.
5. **Completion.** The posting leaves the board, and the type's wage moves from the employer to the claimant through the trade port, once. A wage the employer can't pay isn't paid, and `changed` reports `unpaid`. Released, cancelled and expired postings pay nothing.

`changed(job, what, agent)` reports every step: `posted`, `claimed`, `released`, `completed`, `paid`, `unpaid`, `cancelled` and `expired`.

The demo harness does all of this when it's given a board (`enable_jobs`). The colony takes one through `Colony.build(..., board)`; see `demo/README.md`.

## Saving

`export_state()` gives `{"next": n, "postings": [...]}`. Each posting has its id, type, employer, place, `opened`, `due`, `claimed_by`, `claimed_at` and `progress`.

`import_state(saved)` replaces every posting. It refuses (returns false, changing nothing) data that:

- is malformed;
- names an unknown work type;
- repeats a posting id or gives one agent two claims;
- has a due or claim time before the posting opened, or negative progress;
- has a `next` that could repeat an id.

Requests in progress aren't saved; settle before saving.

## Costs

Claims are indexed by agent, so `claimed_of` is constant time. `best_for` and `advertise` look at every open posting once.
