# Environment

Rooms change how the people inside them feel. Bustle never detects rooms, builds anything or looks at what is in a room: the host computes its rooms and their scores and reports them, and Bustle turns them into thoughts. Nothing is random.

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
- **Saving.** `export_state` and `import_state` save the built-in store, so room membership and scores survive a save. A host that overrides the lookups saves its own rooms.

## Environment thoughts

The environment module (`addons/bustle/modules/environment/`) holds thoughts from the agent's room. It needs the needs_mood module for the thoughts themselves (see `docs/mood.md`).

A `BustleRoomThought` is a rule:

| Field | Meaning |
| --- | --- |
| `score` | One of the four scores. |
| `at_least` | A high rule: held while the score is at least this. |
| `at_most` | A low rule: held while the score is at most this. Set exactly one of `at_least` and `at_most`. |
| `thought` | A held `BustleThoughtDef` (duration 0), with reason kind `environment`. |

Bustle ships no rules. The thresholds and thought values are the host's. A typical set has a pleasant-room thought at beauty 0.6 and a better one at 0.85, a dirty-room thought at cleanliness 0.3 and a worse one at 0.1, a cramped-room thought at comfort 0.25, and an impressive-room thought at 0.8.

`BustleRoomThoughts.new(rules, society.ports)` applies them. Each tick (or whenever an agent moves or a room's scores change), call `room_thoughts.sync(id, mood)`:

1. For each score of the agent's room, it chooses the most extreme **high** rule the score meets (the highest `at_least`) and the most extreme **low** rule (the lowest `at_most`). A better room gives a better thought, not a pile of them.
2. On the mood, it drops every rule thought that wasn't chosen, then holds the chosen ones. Their reason has `room`, `score` and `value`.

Because the thoughts are held, the mood's stack rules apply: each is held at most once, and syncing again only updates its reason. So:

- **Leaving a room** (no room, or a room with no matching score) drops its thoughts.
- **Moving** swaps them.
- **A score changing** swaps a thought for a better or worse one, or drops it.

Other thoughts are left alone.

`sync` returns the chosen thought ids, and `room_changed(id, old_room, new_room)` fires when the room differs from the last sync. Call `forget(id, mood)` when an agent leaves the society.

**The neutral default.** With no environment port, the default port (no rooms) or no mood, there are no environment thoughts and nothing errors. Without the module, nothing changes at all.

## Saving

- The thoughts are saved with the mood (`BustleMood.export_state`). Pass the rule thought defs to `BustleMood.import_state`.
- `BustleRoomThoughts.export_state` saves each agent's last room and chosen thought ids. `import_state` refuses malformed data or a thought id no rule has.
- After a load, the next `sync` brings the mood in line. Holding a thought that is already held adds no second one, so loading never duplicates environment thoughts.
