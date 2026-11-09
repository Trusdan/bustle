# Memory and FindPerson

Memory (`addons/bustle/core/memory/`) is what an agent remembers about where people, places and items are. It fades with time. `BustleFindPerson` uses it, with the other ways an agent can learn where someone is, to decide where to look.

## Memory

`BustleMemory` holds one agent's entries. Each entry is one subject of one kind:

- `person`: someone's whereabouts
- `place`: a place
- `item`: an item's whereabouts

An entry has an area, an optional position and a source. The source sets its starting strength:

| Source | Meaning | Strength |
| --- | --- | --- |
| `saw` | Seen first-hand. | 1.0 |
| `told` | Told directly. | 0.8 |
| `heard` | Overheard. | 0.6 |
| `routine` | Guessed from a routine. | 0.4 |

**Decay:** strength halves every half-life of the entry's kind:

| Kind | Half-life |
| --- | --- |
| Person | 6 game hours |
| Item | 3 days |
| Place | 30 days |

An entry is forgotten once its strength falls below 0.1.

**Capacity:** one agent keeps at most 32 entries. When a new note goes past that, the weakest entry goes.

**Overwriting:** a new note about a subject replaces the old one only when it's at least as strong as what's left of the old one. A fresh sighting beats an old rumour, but a rumour doesn't overwrite a fresh sighting.

**Config:** every number above is a default in `BustleMemoryConfig`. They're starting numbers, not tuning.

The methods:

- `note(kind, subject, area, position, source, now)` adds or replaces an entry. It returns false when the note wasn't kept, including when a full memory drops it straight away as the weakest.
- `recall(kind, subject, now)` returns the entry with its current strength.
- `confidence(kind, subject, now)` returns the strength alone.
- `forget(now)` drops faded entries.
- `export_state` and `import_state` save and load plain data, and refuse malformed data without changing anything.

### Writes from perception

`BustleMemoryFeed`, in the perception module, writes memory from perception events. It doesn't poll. It listens to `BustlePerceptionWorld.perception_changed`:

- When a perceiver becomes alert to a target, the perceiver's memory notes where the target is (`saw`).
- When the perceiver loses track (back to unaware), it notes where the target was last known. The position is the world's last-known one, and the area is the one the target was in when this perceiver last became alert to it, never where the target is now. With no such sighting, or no last-known position, nothing is written. The note is stamped with the minute track was lost.
- Suspicion alone writes nothing.

The host gives the feed three callables: one for each agent's memory, one for the game minute, and optionally one for the area of each actor.

## FindPerson

`BustleFindPerson.find(seeker, target, now)` tries each step in order and stops at the first that works:

1. **Sense:** the host's `sense(seeker, target)` says where the seeker can sense the target right now. The sighting goes into memory.
2. **Memory:** the seeker's own memory, if its entry is at least `min_confidence` strong (0.25). The target may be in another area.
3. **Routine:** the host's `routine(target, now)` gives a guess from the target's routine, for example its schedule block. The guess goes into memory as `routine`.
4. **Ask:** the people `ask_whom(seeker)` names are asked in order. The first whose own memory is confident enough answers, and the seeker notes it as `told`.
5. **Give up:** nobody knew. The result is `unknown`, and for `cooldown_minutes` (60) every new search for that target fails at once with `cooling_down`.

The result is `{found, how, area, position, from}`, where `from` is who answered when asked. The host moves the agent towards it.

Cooldowns are kept only while the game runs. An ended cooldown is dropped when that search runs again, and none are saved.
