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
- **Reports**, when a witness or owner decides to report, go to a role, `authority_role` (default `authority`), never to a named agent. `crime_reported(reporter, role, report)` carries the record as the reporter knows it, plus `reporter`, `role`, `authority` (the holder it reached), `source` and `reported_at`. A report only counts once it reaches the holder (see "Errands"). Who holds the role, and what follows a report, is the host's.
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
| `report` | An errand to the role's holder, then `crime_reported` on arrival. |
| `tell_victim` | An errand to the victim, then `victim_told(witness, owner_id, record)` on arrival. |
| `confront` | `confronted(witness, thief, record)`: an accusation, words only. It never starts a fight or sets any intent to harm; if the host lets a scuffle follow, it goes through the conflict rules. |
| `gossip` | An errand to the listener, then `gossiped(teller, listener, record)` on arrival. |
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

### Errands

Reporting, telling the victim and gossiping are errands. The word counts only when the agent reaches whoever it's for, face to face: `can_reach(agent, other)`, by default the same area. Being there already counts at once. `errands_of(agent)` lists an agent's errands, oldest first: `{agent, kind, record, to, source, knows_thief, since, target}`. `target` is who it has to reach now; for a report that's the role's current holder.

- **The goal:** `BustleCrimeWatch.goal_defs()` gives a `deliver` goal in the guarded band (75), eligible while `fill_inputs(agent, inputs, now)` sets `fact.errand` to 1. Urgent self-care outranks it; orders and duty don't.
- **The action:** `BustleDeliverAction` (`deliver`) calls `deliver(agent, now)`, which goes on with the oldest errand that has someone to reach. Errands still waiting are skipped, so they never hold up the rest. While the agent still has to get there, the action's output names `move_to` (`where(id)`, by default the world port's position of the target's area), `talk_to` and `gear`. The gear is `travel_gear` (default `hurry`), and the host maps it to its own movement gears; `BustleIntent.gear` carries it. Bustle names the destination, and the host moves the body.
- **`deliver` returns** one of:
  - `delivered`: the event is emitted;
  - `travelling`;
  - `waiting`: every errand left is waiting on an empty role, so they stay and the goal isn't eligible until someone holds it;
  - `forgot`: the agent's memory of the item has faded below recall, so the errand is dropped with `errand_dropped(agent, errand, &"forgot")` and nothing is reported. Memory is checked only when `deliver` runs, and it checks waiting errands too. An errand that faded while the role was empty is dropped at the first try after that, never delivered;
  - `none`.
- **Pausing:** `can_travel(agent, now)` returning false (night, fear: the host's call) keeps the goal ineligible. The errand waits.
- **Intimidation:** `intimidate(thief, witness, now)` drops every errand the witness has about that thief's thefts, whether it's a report, word for the victim or gossip (`errand_dropped(..., &"intimidated")`). The witness still remembers, and `reconsider(agent, id, now)` decides again with that moment's fear and opinions. Nothing here sets any intent to harm; any scuffle is the conflict rules' business.
- **Second-hand:** a victim who is told, and anyone who hears gossip, learns of the theft, remembers the item and decides in turn. So the authority can hear of it second-hand.
- **Sources:** every report carries `source`:
  - `eyewitness`: the reporter saw it;
  - `secondhand`: the reporter was told;
  - `owner_deed`: the owner found it gone and doesn't know the thief.

  How much to trust each is the host's.
- **Targets that aren't agents:** a target that isn't an agent of the society (the host's own character, say) is never reached by default. A host with such targets sets `can_reach` and `where`; otherwise the errand stays `travelling`.
- **Instant:** `instant` delivers every errand the moment it's decided, with no travel. It's for developers and tests only, and off unless the project setting `bustle/simulation/instant_crime_reports` is on. A watch reads the setting when it's created. It isn't a game option.
- **Saving:** errands save and load with the records.
