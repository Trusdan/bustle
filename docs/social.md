# Social store

`BustleSocialStore` (`addons/bustle/society/`) is Bustle's built-in social store. It's a `BustleSocialPort` that keeps opinions with reasons and relationship kinds, for hosts that don't have a social engine of their own.

To use it, give it to the society's ports: `society.set_port(&"social", BustleSocialStore.new())`.

Deeds work exactly as in the port's default:

- The actor and the named witnesses know a deed first-hand.
- `share_news` passes on first-hand deeds only, and only one hop.

## Opinions

An opinion is one-way: how `a` regards `b`, from 0 to 100. It's 50 plus every live opinion entry, clamped to that range.

- `add_opinion(a, b, value, reason, days)` adds an entry.
  - The entry lasts `days` game days from the store's minute.
  - `reason` is plain data. When a deed caused the entry, put the deed's key under `deed`.
- `set_time(now)` moves the store's clock forward. Ended entries go, and every pair's kinds are checked again.
- `reasons(a, b, count)` returns the live entries, strongest first, with their reasons.

## Relationship kinds

Kinds are one-way too: `a` counts `b` a friend. `kinds_between(a, b)` returns them sorted.

**Kinds a host sets** with `set_kind` (kin, for example) stay until `clear_kind` removes them.

**Kinds formed from deeds** come and go with opinion, by `BustleRelationshipRules`. Every number below is a starting default, not tuning:

| | Forms when | Lapses when |
| --- | --- | --- |
| Friend | opinion is 75 or more, with at least 3 positive deed entries within 14 days | opinion falls below 55 |
| Rival | opinion is 25 or less, with at least 3 negative deed entries within 14 days | opinion rises above 45 |

A deed entry is an opinion entry whose reason has a `deed`. The gap between forming and lapsing means a kind doesn't flicker. `kind_changed(a, b, kind, formed)` fires each time a kind forms or lapses.

The rules never add or remove a host's kinds, and `clear_kind` never removes the rules' kinds.

## Compatibility

`BustleCompatibility.of(a, b, world_seed)` says how well two agents get on by nature, from -1 to 1.

- It's fixed for a pair in a world: the same every time, and the same both ways round.
- It differs between worlds and between pairs. It's a hash of the world seed and the two ids.
- It can blend in how close the two agents' personality sliders are: pass both personalities and a weight from 0 to 1. The default weight is 0, which uses the hash alone.

## Saving

`export_state` and `import_state` save and load opinions, both sets of kinds, deeds and the clock as plain data.

Import refuses malformed data and changes nothing when it does. Deed keys carry on after a load and are never reused.
