# Crime

Crime (`addons/bustle/core/crime/`) covers desperate theft. Nothing in it is left to chance: an agent steals when its circumstances and its personality add up, every time they do, and never otherwise. There is no limit on how much crime a place sees. How often it happens follows from who lives there and how hard pressed they are.

## The guards

`BustleCrime.consider(agent, now)` runs the guards in order. Each must pass:

1. **Crime is allowed.** That needs both the developer setting `bustle/simulation/npc_crime` (a project setting, on unless set to `false`) and the host's `enabled`. Neither is a game option, and a host doesn't show them to players.
2. **The agent can act.** It's an agent of the society, isn't in `exempt`, and isn't held to a story or task by `is_locked(agent)`.
3. **Need.** One of `config.needs` (default `food`) presses at least `min_need` (default 0.6).
4. **Personality.** That pressure plus `Σ weight × (slider − 50) / 100` reaches `threshold` (default 1). The default weights are honesty −2, greed +1 and boldness +1.
   - An honest agent (honesty 90) never steals, even starving: 1.0 − 0.8 < 1.
   - An ordinary agent steals only when starving: 1.0.
   - A dishonest, greedy, bold one steals sooner.
5. **Opportunity.** There's an item in the agent's area that:
   - is owned by someone else;
   - isn't protected;
   - eases the need;
   - isn't seen. By default it's seen when any other agent of the society is in that area. A host can replace that with `is_observed(thief, area)`.

   The item that eases the need most is chosen (ties by id).

When every guard passes, `consider` returns `{item, owner_id, place, need, pressure, score}` and remembers it as the agent's target. `fill_inputs` then sets the agent's `fact.steal` input to 1.

## The goal and the action

`BustleCrime.goal_defs()` gives one goal, `steal`, in the new `BustleBands.GUARDED` band. That band sits below `URGENT` self-care and above `ORDERED` and `DUTY`. The goal is eligible only while `fact.steal` is 1, and it runs the `steal` action (`BustleStealAction`).

The action calls `steal(agent, now)`:

- It checks every guard again for the same item. If someone came along in the meantime, it fails with `guards_failed`.
- It then moves the item to the agent through the property port and emits `theft(thief, owner_id, item, circumstances)`. `circumstances` is `{place, need, pressure, score, at}`, so it says what drove the theft.

Afterwards the target is gone, and the agent's usual goals win again.

## What theft never does

- **It never creates or destroys goods.** It only moves an existing item from its owner.
- **It never makes anyone mean to kill.** Nothing here engages the combat port. Any scuffle that follows goes through the conflict rules (see `docs/conflict.md`).
- **It decides nothing that follows.** `theft` is a neutral event, and the host decides what comes of it.

## The property port (`BustlePropertyPort`)

The property port records who owns which things and where they are. A host extends it to use its own items. The standalone default is an in-memory register.

| Method | What |
| --- | --- |
| `register(id, owner_id, place, relieves, protected)` | Adds an item. `relieves` is need → amount. A protected item can never be taken. |
| `item(id)`, `owner_of(id)`, `items_at(place)` | Read the register. |
| `is_protected(id)`, `set_protected(id, protected)` | A host marks its own protected things (keepsakes, things a story needs). |
| `transfer(id, from, to)` | Moves an item from its owner. It refuses protected items and items not owned by `from`. |
| `export_state()`, `import_state(saved)` | Plain data, in id order. Import is all or nothing. |

## Settings (`BustleCrimeConfig`)

| Setting | Default |
| --- | --- |
| `needs` | `food` |
| `min_need` | 0.6 |
| `threshold` | 1.0 |
| `slider_weights` | honesty −2, greed +1, boldness +1 |
