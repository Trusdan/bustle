# Romance

`addons/bustle/modules/romance/` gives pairs of agents a courtship ladder: courting, partner, engaged and married. Each status is a relationship kind written both ways through the social port, so the built-in store and the Wyrd bridge both carry it. Nothing is random, and there is no explicit content.

```gdscript
var romance := BustleRomance.new(society.ports.social, rules, world_seed)
romance.confirm_hook = func(a, b, status) -> bool: return host_allows(a, b, status)
romance.update_all(agent_ids, now, mood_of)
```

`update_all` asks `mood_of` for the two moods only when a pair breaks up.

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

- a pair where either holds a `blocked_kinds` kind toward the other (`parent`, `child`, `sibling` or `in_law` by default);
- a pair where either agent is already courting or bonded to anyone. Courting is one at a time.

The thresholds are on `BustleRomanceRules` and are experimental defaults. With rules that aren't `is_valid()` (a release line at or above its forming line, say), `update` changes nothing.

## Breakups

A courting or partnered pair breaks up when either opinion falls below its release line: `courting_release` (55) for courting and `partner_release` (60) for partner. Every release line sits below its forming line, so a status doesn't flicker.

An engaged or married pair never breaks up on its own, whatever the opinions. Only the host ends it, with `end(a, b, now)`, as either one's choice. `end` works for every status. A breakup clears the kind both ways and gives each of the two `breakup_thought`, with the other in its reason, when their moods are passed in.

**A breakup sticks.** After it, the pair may court again only once its lower opinion has dropped below `courting_release` and then climbed back to `courting_opinion`. A pair whose opinion had already lapsed below that line can court again as soon as it climbs back. This is kept per pair (`armed` in the saved record), so it survives a save, and it needs no extra tuning.

## The host's ratings policy

`ratings_policy` (`func(a, b, status) -> bool`) is the host's own rules, such as age, content rating or setting, without Bustle knowing why. It is asked before every step up the ladder:

- courting and partner, when `update` would form them;
- engaged and married, before `confirm_hook`.

Returning false vetoes the step. Nothing changes and no signal fires; the pair is simply asked again on a later update or request. Unset, it allows everything the ladder allows.

## Family

Bustle never creates family on its own, not even on a marriage. The host records it:

```gdscript
romance.link_family(&"child_1", &"parent_1", &"parent")  # parent_1 is child_1's parent
romance.link_family(&"a", &"b", &"sibling")
```

`link_family(a, b, relation)` records `b` as `a`'s relation. It writes the kind both ways through the social port: `parent` and `child` as a pair, and `sibling` and `in_law` the same both ways. `unlink_family` takes a link away. The kinds are saved by the port (the store's or Wyrd's), and family is never courted.

## Jealousy

An agent with a romantic bond (courting or above; never a friend) gets jealous when its partner takes to a third agent. There are two causes, both deterministic:

- **Opinion.** In `update_all`, the partner's opinion of a third agent reaches `jealousy_opinion` (75). This is felt once per (agent, partner, third agent). It can come again only after that opinion has fallen below `jealousy_release` (60) and climbed back. What has been felt is saved, and a breakup forgets it.
- **Interaction.** The host calls `notice(actor, verb, target, mood_of)` for an interaction it has listed in `jealousy_verbs`. That gives one jealousy for each such interaction.

Each time, three things happen:

- **A thought.** The agent gets `jealousy_thought` (timed), with the partner, the rival and the cause in its reason. It is an ordinary timed thought, under its own stack rules.
- **An opinion entry.** The agent's opinion of the rival gets one timed entry of `jealousy_opinion_value` (−5) for `jealousy_opinion_days` (3), with the cause, partner and rival in its reason. It is written through the port's `add_opinion`, which the built-in store has. A port without opinion entries, such as the Wyrd bridge, whose opinions come from deeds, gets none. Set the value to 0 to turn it off.
- **A signal.** `jealous(agent, partner, rival, cause)` fires.

The entry is never toward the partner, and it never changes a status by itself: it only moves the opinion of the rival, which no romance line reads for this pair.

## Affairs

`affairs_enabled` is off by default. There is no affair path at all. Whatever the flag says, an agent who is courting, partnered, engaged or married never starts courting anyone else.

## Ports

- **The social port.** Romance writes kinds only through `set_kind` and `clear_kind`, which `BustleSocialPort` now has (as no-ops in the default, which keeps no kinds; `supports_kinds()` is false). The built-in store and the Wyrd bridge's social port both keep them. With a port that keeps no kinds, `update` does nothing.
- **Kinds it doesn't own.** Romance never writes or clears any kind outside its ladder, so family kinds the host set stay as they are.

## Signals and saving

`status_changed(a, b, old, new, reason)` fires on every change. The reason is `formed`, `confirmed`, `lapsed` or `ended`.

`export_state()` keeps each pair's status, since when, whether it is armed to court again, and its last `history_limit` (10) changes. It also keeps the jealousy already felt over opinions, under `jealousy`. The kinds themselves are saved by the social port: the store's or Wyrd's own save. `import_state` refuses malformed data or a status off the ladder, and changes nothing.

## In the demo

`Colony.build(..., romance)` with `Colony.romance_rules()` turns romance on (it needs the social module). The harness's `enable_romance(rules)` runs `update_all` every step and logs `romance` and `jealous` on the timeline. The colony fixture:

- the third and fourth settlers start fond of each other, so they court on the first morning and are partners two days later;
- the first two are fond too, but are recorded as siblings, so they never court.

The demo lines are lower than the defaults so a week shows this. Without romance, the colony is unchanged.
