# Director

`addons/bustle/modules/director/` is a storyteller for host-authored events. It reads the story's tension from the host's world state and recent events, decides when the story needs a beat and of which kind, fires the event the story needs most, and applies what that event declares. Nothing is random: there is no seed, no deck and no roll. The same events, inputs, quest locks and clock replay the same timeline and the same effects.

It is opt-in. With no events, nothing fires, and `BustleDirectorPort` keeps allowing everything.

```gdscript
var director := BustleDirector.new(rules, society.ports)
director.add_event(load("res://events/gale.tres"))
var effects := BustleDirectorEffects.new(society.ports)
effects.agents = func(): return society.agent_ids()
effects.mood_of = func(id): return moods.get(id)
effects.brain_of = func(id): return brains.get(id)
director.effects = effects

# Each tick (or every few minutes):
director.update(clock_minute, BustleDirector.hooks(head_count, wealth, my_inputs), quest_lock_held)
```

## Events

A `BustleEventDef` is host data:

| Field | Meaning |
| --- | --- |
| `id` | unique among the director's events |
| `kind` | what the host veto is asked about (`allows(kind)`); empty means the id |
| `requires` | preconditions on the host's inputs, all of which must hold: `{"input": key}` with optional `at_least` and/or `at_most`; with neither, the input must be above 0; a missing input fails |
| `tension` | above 0 raises the story's tension when it fires, below 0 relieves it |
| `cooldown_minutes` | game minutes before it may fire again |
| `lock_sensitive` | never fires while a quest lock is held |
| `weight`, `score_inputs` | its score: the weight, plus points per unit of each named input |
| `effects` | what it does when fired (see below) |

`validate()` explains a bad definition, and `add_event` refuses one, or a repeated id.

## Pacing

Tension runs from 0 to 1. It is the host's inputs weighted by `BustleDirectorRules.tension_inputs`, plus each recently fired event's `tension`, fading in a straight line over `memory_minutes` (3 days by default). `tension(now, inputs)` shows it.

`need(now, inputs)` reads it as a beat:

- at or above `high` (0.7), the story needs relief;
- at or below `low` (0.3), it needs a raise;
- in between, nothing in particular.

Each `update(now, inputs, locked)` fires at most one event. Of the eligible events, it picks the best by, in turn:

1. **pacing:** events that move tension the way the story needs come first, those that leave it alone next, and those that push the wrong way last;
2. **score:** highest first;
3. **id.**

Pacing only orders events. It never blocks one: a wrong-way event still fires when nothing else is eligible. `eligible(now, inputs, locked)` lists the candidates in pick order.

### When an event is eligible

- its preconditions hold;
- its cooldown has passed since it last fired;
- it isn't lock-sensitive while the quest lock (`locked`, from the host) is held;
- the host veto, `BustleDirectorPort.allows(kind)`, agrees.

A lock-sensitive event that is still eligible fires once the lock drops. The host veto is checked for every candidate, so a host can pause the whole storyteller, or one kind of event, from its own port.

### The beat gap

`beat_gap_minutes` (0, off by default, and at most `memory_minutes`) is the least time between any two fired events. It only delays: an event still eligible when the gap ends fires then. It is never a budget that drops a warranted event.

## Effects

`BustleEventEffect`, in `BustleEventDef.effects`, applied in order by `BustleDirectorEffects` right after `event_fired`:

- **`thought`:** gives a timed `thought` to each target, through its mood's `add_thought`, with the event in its reason.
- **`order`:** queues an order to run `sequence` (at `place`, if set) on each target's brain, through the normal order path. The order's id is `<event>.<minute>`.
- **`spawn`:** asks the world port, `BustleWorldPort.request_spawn(kind, area, count, event)`. The host decides and makes them. The default world port does nothing and answers false. Bustle never creates goods, money or bodies itself.

Thoughts and orders reach exactly the agents the effect names:

- those in `target_ids`;
- those carrying `target_tag` (the host's `tags_of`);
- everyone in `target_area` (the world port's `area_of`).

Nobody else is touched. Each application emits `applied(event, kind, target, what, done)`, where `done` says whether a mood took the thought, a brain queued the order, or the host made the spawn. The applier keeps nothing.

## Population and wealth

These are host inputs, nothing more. `BustleDirector.hooks(population, wealth, inputs)` returns a copy of the inputs with `fact.population` and `fact.wealth` set. Preconditions, score inputs and tension inputs read them like any other input: an event might need at least 12 people, score higher with more wealth, or let crowds raise tension.

Bustle has no economy. It invents no shortages, restocks nothing and makes no money.

## Saving

`export_state()` keeps each event's last firing (the cooldowns) and the recent history. Tension is computed from these and the inputs, so it comes back with them. `import_state()` refuses, changing nothing, a save with another version, an unknown event, a malformed entry or history out of order. A director saved mid-run makes the same choices after loading.

## Defaults

All are experimental and configurable.

| Setting | Default |
| --- | --- |
| `memory_minutes` | 4320 (3 days) |
| `high` / `low` | 0.7 / 0.3 |
| `beat_gap_minutes` | 0 (off) |
| `tension_inputs` | none |
| Event `weight` | 1 |

## In the demo

The harness's `enable_director(events, rules)` runs the director each step on the head count (wealth is 0), applies effects to the settlers, and logs `director` and `effect` on the timeline.

`Colony.director_events()` is a small neutral deck that runs beside the fixed cold snap:

- a gale raises tension and leaves everyone windswept;
- a fair day relieves it;
- travellers ask the world for a visitor, which the default world doesn't make.

Without `enable_director`, the colony is unchanged.
