# Crime

Crime (`addons/bustle/core/crime/`) covers desperate theft. Nothing in it is left to chance: an agent steals when its circumstances and its personality add up, every time they do, and never otherwise. There is no limit on how much crime a place sees. How often it happens follows from who lives there and how hard pressed they are.

## The guards

`BustleCrime.consider(agent, now)` runs the guards in order. Each must pass:

1. **Crime is allowed.** That needs both the developer setting `bustle/simulation/npc_crime` (a project setting, on unless set to `false`) and the host's `enabled`. Neither is a game option, and a host doesn't show them to players.
2. **The agent can act.** It's an agent of the society, isn't in `exempt`, and isn't held to a story or task by `is_locked(agent)`.
3. **Need.** One of `config.needs` (default `food`) presses at least `min_need` (default 0.6), and the agent owns nothing that eases it. An agent that already has what it needs, stolen or not, isn't driven to take more.
4. **Personality.** That pressure plus `Σ weight × (slider − 50) / 100` reaches `threshold` (default 1). The default weights are honesty −2, greed +1 and boldness +1.
   - An honest agent (honesty 90) never steals, even starving: 1.0 − 0.8 < 1.
   - An ordinary agent steals only when starving: 1.0.
   - A dishonest, greedy, bold one steals sooner.
5. **Opportunity.** There's an item in the agent's area that:
   - is owned by someone else;
   - isn't protected;
   - eases the need;
   - isn't seen, as far as the thief can tell. By default it's seen when any other agent of the society who isn't incapacitated (the health port) is in that area. A host can replace that judgement with `is_observed(thief, area)`, which may be wrong: who really perceived a theft is up to the crime watch (below).

   The item that eases the need most is chosen (ties by id).

When every guard passes, `consider` returns `{item, owner_id, place, need, pressure, score}` and remembers it as the agent's target. `fill_inputs` then sets the agent's `fact.steal` input to 1.

## The goal and the action

`BustleCrime.goal_defs()` gives one goal, `steal`, in the new `BustleBands.GUARDED` band. That band sits below `URGENT` self-care and above `ORDERED` and `DUTY`. The goal is eligible only while `fact.steal` is 1, and it runs the `steal` action (`BustleStealAction`).

The action calls `steal(agent, now)`:

- It checks every guard again for the same item. If someone came along in the meantime, it fails with `guards_failed`.
- It then moves the item to the agent through the property port and emits `theft(thief, owner_id, item, circumstances)`. `circumstances` is `{place, need, pressure, score, at}`, so it says what drove the theft.

Afterwards the target is gone. The agent now owns something that eases the need, so the need guard fails and it doesn't steal again for that need, however many other items it could reach. Its usual goals win again. When the host lets it use up the item (and removes the item from the register), the need can drive it again.

## What theft never does

- **It never creates or destroys goods.** It only moves an existing item from its owner.
- **It never makes anyone mean to kill.** Nothing here engages the combat port. Any scuffle that follows goes through the conflict rules (see `docs/conflict.md`).
- **It decides nothing that follows.** `theft` is a neutral event, and the host decides what comes of it.

## After a theft (`BustleCrimeWatch`)

`BustleCrimeWatch.new(crime)` follows every `theft` and keeps a record of it: `{id, thief, owner_id, item, place, at, witnesses, known_by, decisions, reporters, deed, found_at}`. Every theft is witnessed and remembered, or it leaves a deed. Everyone who knows of it then decides what to do about it (see "What a witness does").

- **Witnesses.** An agent witnesses a theft only if `perceives(agent, thief, place)` says it perceived it. By default that's every other agent in the place who isn't incapacitated. There are no made-up witnesses.
  - With both defaults, a thief only steals where nobody can perceive it, so every theft is a deed.
  - Witnesses come from the gap between what the thief judged (`BustleCrime.is_observed`) and what was really perceived (`perceives`). A host using the perception module, for example, gives the thief its own awareness and the watch the onlookers' awareness, so an onlooker the thief missed sees it.
- **Each witness:**
  - knows of it (`known_by`);
  - remembers the thief and the item where it saw them, in its `BustleMemory` if `memory_of(agent)` gives one;
  - gets `witnessed(witness, thief, item, record)`;
  - decides what to do.
- **Reports**, when a witness or owner decides to report, go to a role, `authority_role` (default `authority`), never to a named agent. `crime_reported(reporter, role, report)` carries the record as the reporter knows it, plus `reporter`, `role`, `authority` (whoever holds the role in the roles port then, maybe nobody) and `reported_at`. Who holds the role, and what follows a report, is the host's.
- **Deeds.** A theft nobody perceived is a deed, an open trace:
  - `open_deeds()` lists the ones not yet found.
  - `stolen_goods_of(agent)` lists the records of stolen goods an agent still owns, the evidence on it.
  - The host calls `notice_losses(owner_id, place, now)` when an owner is somewhere, for example each tick. It finds what was stolen from that owner there. The owner remembers the item where it was taken, `deed_found(finder, item, record)` is emitted, and the owner decides what to do. The owner doesn't know the thief, so it can't confront anyone, and any report has an empty `thief`.
- **Questioning:** `question(agent, now)` gives what an agent can tell about each record it knows of: `{id, item, owner_id, place, at, thief, outcome}`. It names the thief only if the agent witnessed the theft and still remembers the thief in its memory, so a witness who stayed silent can still be asked, until it forgets.
- **Saving:** `export_state()` and `import_state(saved)` (all or nothing).

### What a witness does

A witness, or an owner who finds a deed, does exactly one thing: `report`, `tell_victim`, `confront`, `gossip` or `silent`. The watch emits `decided(agent, outcome, record)`, then:

| Outcome | What happens |
| --- | --- |
| `report` | `crime_reported`, at once. |
| `tell_victim` | `victim_told(witness, owner_id, record)`. |
| `confront` | `confronted(witness, thief, record)`: an accusation, words only. It never starts a fight or sets any intent to harm; if the host lets a scuffle follow, it goes through the conflict rules. |
| `gossip` | `gossiped(teller, listener, record)`. |
| `silent` | Nothing more. It still remembers. |

The host can replace the decision with `should_report(agent, case)`, which returns an outcome; anything else counts as `silent`. The case is `{record, thief, owner_id, place, can_confront, gossip_to}`, with the thief empty when the agent doesn't know it.

Otherwise `BustleWitnessJudge` decides, with the same formulas for every agent and no chance:

- **Eligible outcomes:**
  - `report` is always eligible;
  - `tell_victim` when the victim is someone else;
  - `confront` when the thief is known and within reach (`can_reach(agent, other)`, by default both agents in the same area);
  - `gossip` when `gossip_to(agent, record)` names someone (by default nobody).
- **Score:** each eligible outcome scores `Σ weight × (value − 50) / 100` over its terms in `BustleWitnessConfig.weights`, plus loyalty: `kind_weights` for each relationship kind between the witness and the thief (none by default).
- **Values:**
  - personality sliders (`personality_of`);
  - the witness's opinions of the thief and the victim (the social port);
  - its fear of the thief (`fear_of`);
  - the authority's standing with it (`standing_of`, by default its opinion of the role's holder).

  Each value is 0 to 100, and 50 when unknown.
- **The winner:** the highest score wins if it reaches `threshold` (default 1), with ties going to report, then tell the victim, confront and gossip. Otherwise the witness stays silent.

The default weights:

| Term | Every outcome | Plus |
| --- | --- | --- |
| honesty | +2 | |
| piety, boldness, diligence | +1 each | |
| opinion of the thief | −2 | |
| opinion of the victim | +2 | |
| fear of the thief | −2 | |
| the authority's standing | | +1 on `report` |
| temper | | +1 on `confront` |
| sociability | | +1 on `gossip` |

So an honest witness (honesty 100) reports. One who also distrusts the authority tells the victim instead, and a hot-tempered one with the thief in reach confronts it. An ordinary witness, or one afraid of the thief, stays silent.

The watch never punishes, fines or harms anyone, and changes nothing about the goods. Arrests, bounties and trials are the host's.

## The property port (`BustlePropertyPort`)

The property port records who owns which things and where they are. A host extends it to use its own items. The standalone default is an in-memory register.

| Method | What |
| --- | --- |
| `register(id, owner_id, place, relieves, protected)` | Adds an item. `relieves` is need → amount. A protected item can never be taken. |
| `item(id)`, `owner_of(id)`, `items_at(place)` | Read the register. |
| `is_protected(id)`, `set_protected(id, protected)` | A host marks its own protected things (keepsakes, things a story needs). |
| `items_of(owner_id)` | Every item an owner owns, wherever it is. |
| `remove(id)` | The host uses up or destroys an item (eaten, broken). Theft never calls it. |
| `transfer(id, from, to)` | Moves an item from its owner. It refuses protected items and items not owned by `from`. Only the owner changes: the item stays at its place until the host moves it. |
| `export_state()`, `import_state(saved)` | Plain data, in id order. Import is all or nothing. |

Only registered items can be stolen. A host's shop stock, for example, is out of reach unless the host registers those items too.

## Settings (`BustleCrimeConfig`)

| Setting | Default |
| --- | --- |
| `needs` | `food` |
| `min_need` | 0.6 |
| `threshold` | 1.0 |
| `slider_weights` | honesty −2, greed +1, boldness +1 |
