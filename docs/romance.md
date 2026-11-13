# Romance

`addons/bustle/modules/romance/` gives pairs of agents a courtship ladder: courting, partner, engaged and married. Each status is a relationship kind written both ways through the social port, so the built-in store and the Wyrd bridge both carry it. Nothing is random, and there is no explicit content.

```gdscript
var romance := BustleRomance.new(society.ports.social, rules, world_seed)
romance.confirm_hook = func(a, b, status) -> bool: return host_allows(a, b, status)
romance.update_all(agent_ids, now, mood_of)
```

## The ladder

| Status | How it forms |
| --- | --- |
| courting | Both opinions are at least `courting_opinion` (70), compatibility is at least `courting_compat` (0.2), `may_court` allows it, and neither is courting or bonded to anyone. Automatic. |
| partner | Courting has lasted `partner_days` (7) and both opinions are at least `partner_opinion` (80). Automatic. |
| engaged | `request(a, b, ENGAGED, now)` from partner, and the host's `confirm_hook` approves. |
| married | `request(a, b, MARRIED, now)` from engaged, and the hook approves. |

Bustle never moves a pair to engaged or married on its own. With no `confirm_hook` set, every request is refused.

Compatibility is `BustleCompatibility.of(a, b, world_seed)` unless the host sets `compatibility` (`func(a, b) -> float`), for example to blend in personality.

`may_court(a, b)` refuses:

- a pair where either holds a `blocked_kinds` kind toward the other (`parent`, `child` or `sibling` by default, as the host sets them);
- a pair where either agent is already courting or bonded to anyone. Courting is one at a time.

The thresholds are on `BustleRomanceRules` and are experimental defaults.

## Breakups

A pair breaks up when either opinion falls below its release line: `courting_release` (55) for courting, and `partner_release` (60) for partner, engaged and married. The host can also end it, as either one's choice, with `end(a, b, now)`.

Every release line sits below its forming line, so a status doesn't flicker. A breakup clears the kind both ways and gives each of the two `breakup_thought`, with the other in its reason, when their moods are passed in.

## Affairs

`affairs_enabled` is off by default. There is no affair path at all. Whatever the flag says, an agent who is courting, partnered, engaged or married never starts courting anyone else.

## Ports

- **The social port.** Romance writes kinds only through `set_kind` and `clear_kind`, which `BustleSocialPort` now has (as no-ops in the default, which keeps no kinds; `supports_kinds()` is false). The built-in store and the Wyrd bridge's social port both keep them. With a port that keeps no kinds, `update` does nothing.
- **Kinds it doesn't own.** Romance never writes or clears any kind outside its ladder, so family kinds the host set stay as they are.

## Signals and saving

`status_changed(a, b, old, new, reason)` fires on every change. The reason is `formed`, `confirmed`, `lapsed` or `ended`.

`export_state()` keeps each pair's status, since when, and its last `history_limit` (10) changes. The kinds themselves are saved by the social port: the store's or Wyrd's own save. `import_state` refuses malformed data or a status off the ladder, and changes nothing.
