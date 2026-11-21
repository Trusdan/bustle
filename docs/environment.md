# Environment

Rooms change how the people inside them feel, and whether they are indoors or out. Bustle never detects rooms, builds anything or looks at what is in a room: the host computes its rooms and their scores and reports them, and Bustle turns them into thoughts. Nothing is random.

## The environment port

`BustleEnvironmentPort` (`society.ports.environment`) answers two questions:

- `room_of(id)`: the room an agent is in, or empty for none.
- `scores(room)`: the room's scores, each from 0 to 1. The scores are `beauty`, `comfort`, `cleanliness` and `impressiveness` (`BustleEnvironmentPort.SCORES`).

A host either extends the port and overrides both, or fills the built-in store:

```gdscript
var environment := society.ports.environment
environment.set_scores(&"hall", {&"beauty": 0.9, &"cleanliness": 0.6})
environment.set_room(&"baker_1", &"hall")
environment.set_room(&"baker_1", &"") # outside every room
```

- **Unset scores.** A score a room doesn't have is unset, not 0. An unscored room isn't ugly; it is just not rated. `set_scores` replaces all of a room's scores, and an empty dictionary clears them.
- **The default.** The standalone default has no rooms and no scores.
- **One room per agent.** An agent is in at most one room at a time: `set_room` replaces its room, and `room_of` gives that one room. Overlapping rooms are the host's to resolve before it reports one.
- **Saving.** `export_state` and `import_state` save the built-in store, so room membership and scores survive a save. A host that overrides the lookups saves its own rooms.

## Environment thoughts

The environment module (`addons/bustle/modules/environment/`) holds thoughts from the agent's room. It needs the needs_mood module for the thoughts themselves (see `docs/mood.md`).

A `BustleRoomThought` is a rule:

| Field | Meaning |
| --- | --- |
| `score` | One of the four scores. |
| `at_least` | A high rule: held while the score is at least this. |
| `at_most` | A low rule: held while the score is at most this. Set exactly one of `at_least` and `at_most`. |
| `thought` | A held `BustleThoughtDef`: it must have duration 0 and reason kind `environment`, or the rule is refused. |

Bustle ships no rules. The thresholds and thought values are the host's. A typical set has a pleasant-room thought at beauty 0.6 and a better one at 0.85, a dirty-room thought at cleanliness 0.3 and a worse one at 0.1, a cramped-room thought at comfort 0.25, and an impressive-room thought at 0.8. The demo rooms below show what that set does.

`BustleRoomThoughts.new(rules, society.ports)` applies them. Each tick (or whenever an agent moves or a room's scores change), call `room_thoughts.sync(id, mood)`:

1. For each score of the agent's room, it chooses the most extreme **high** rule the score meets (the highest `at_least`) and the most extreme **low** rule (the lowest `at_most`). A better room gives a better thought, not a pile of them.
2. On the mood, it drops every rule thought that wasn't chosen, then holds the chosen ones. Their reason has `room`, `score` and `value`.

Because the thoughts are held, the mood's stack rules apply: each is held at most once, and syncing again only updates its reason. So:

- **Leaving a room** (no room, or a room with no matching score) drops its thoughts.
- **Moving** swaps them.
- **A score changing** swaps a thought for a better or worse one, or drops it.

Other thoughts are left alone. Give environment thoughts ids of their own: `sync` drops any held thought that has a rule's id, even one held for another reason. It only drops thoughts that are actually held, so syncing every tick stays cheap.

`sync` returns the chosen thought ids, and `room_changed(id, old_room, new_room)` fires when the room differs from the last sync. Call `forget(id, mood)` when an agent leaves the society.

**The neutral default.** With no environment port, the default port (no rooms) or no mood, there are no environment thoughts and nothing errors. Without the module, nothing changes at all.

## The demo rooms (experimental demo data)

The demo has three example rooms with scores, in `demo/environment/demo_rooms.gd`. **They are experimental demo data, not canon:** they aren't part of the addon, nothing in `addons/bustle/` loads them, the demos don't install them unless asked, and their names and numbers may change in any release. A host replaces them with its own rooms and scores.

| Room | `beauty` | `comfort` | `cleanliness` | `impressiveness` | With the typical rules above |
| --- | --- | --- | --- | --- | --- |
| `house_room`, a plain room of a house | 0.6 | 0.7 | 0.7 | 0.3 | pleasant room |
| `workshop`, a working room | 0.3 | 0.4 | 0.35 | 0.5 | none |
| `cellar` | 0.1 | 0.2 | 0.2 | unset | cramped room, dirty room |

The cellar has no impressiveness score, to show that an unset score isn't 0.

Preload the script (it has no class name) and install the scores on a port. `install` sets only these rooms' scores and puts nobody in a room, so the host still places its agents:

```gdscript
const DemoRooms := preload("res://demo/environment/demo_rooms.gd")

DemoRooms.install(society.ports.environment)
society.ports.environment.set_room(&"baker_1", DemoRooms.WORKSHOP) # indoors, with the workshop's scores
```

`DemoRooms.rooms()` lists the ids and `DemoRooms.scores_of(room)` gives a room's scores. `tests/environment/test_demo_rooms.gd` checks the table, and that an agent placed in one of these rooms is indoors with that room's scores.

## Indoors and outdoors

An agent in a room is **indoors**, and one in no room is **outdoors**. `environment.is_indoors(id)` and `environment.conditions(id)` give that as the need condition `indoors` or `outdoors`. A host can override `is_indoors`, for example for a roofless yard it counts as a room.

To let needs follow it, add the conditions to the ones you pass to `BustleNeedSet.advance`:

```gdscript
conditions.append_array(BustleEnvironmentPort.conditions_of(society.ports.environment, id))
needs.advance(minutes, conditions, modifiers)
```

`conditions_of` gives no conditions when there is no environment port, so without one the environment changes no need. With the default port, an agent no host has put in a room counts as outdoors, because "indoors" means "in a room". Bustle keeps no flag for "never placed". A host that installs these needs puts its agents in rooms, or leaves the conditions out for agents it hasn't placed. Bustle never decides on its own whether anyone is inside.

Bustle ships no indoors or outdoors needs. The demo's pair is data in `demo/environment/`, and a host installs them only if it wants them:

| Need | Rises (per game hour) | Falls (per game hour) |
| --- | --- | --- |
| `outdoors` | 0.05 while `indoors` | 0.25 while `outdoors` |
| `indoors` | 0.05 while `outdoors` | 0.25 while `indoors` |

So an agent kept in for ten hours wants to go out (outdoors 0.5), and an hour outside eases it by 0.25. The demo harness adds the conditions when it is given a port (`enable_environment`).

**No goal acts on these needs.** Neither Bustle nor the demo has a goal that relieves them (going out, coming in). A host wires them to its own goals, for example with a consideration on `need.outdoors` in a goal that takes the agent outside.

### Pausing these needs while an agent sleeps

The conditions apply whenever they're passed, asleep or awake. The demo harness passes them while an agent sleeps too. A host that wants sleep to pause these needs leaves the environment conditions out while the agent is asleep:

```gdscript
var conditions: Array[StringName] = [&"asleep"] if asleep else [&"awake"]
if not asleep:
	conditions.append_array(BustleEnvironmentPort.conditions_of(society.ports.environment, id))
needs.advance(minutes, conditions, modifiers)
```

The demo pair rises only while its condition holds (`rises_when`) and falls only under `condition_rates`. So with neither `indoors` nor `outdoors`, both hold still, and they pick up again when the agent wakes. Nothing else changes, and no API is needed. A need of the host's own that should keep moving during sleep can use its own conditions. `tests/environment/test_demo_rooms.gd` checks that both needs hold still through eight hours of sleep.

## Saving

- The thoughts are saved with the mood (`BustleMood.export_state`). Pass the rule thought defs to `BustleMood.import_state`.
- `BustleRoomThoughts.export_state` saves each agent's last room and chosen thought ids. `import_state` refuses malformed data or a thought id no rule has.
- Need pressures are saved with the need set, and who is indoors is the port's room store, so both survive a save.
- After a load, the next `sync` brings the mood in line. Holding a thought that is already held adds no second one, so loading never duplicates environment thoughts.
