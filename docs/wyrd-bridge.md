# Wyrd bridge

`addons/bustle_wyrd/` is an optional bridge to the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine. With it installed, Wyrd is the one source of opinions, relationship kinds, deeds, rumours and roles for a society, and Wyrd content can ask about an agent's goal, needs and mood.

Bustle's core never refers to the bridge, and Wyrd never refers to Bustle. The bridge calls Wyrd by name, so it compiles, and the core works, with no Wyrd in the project.

## The pinned release

The bridge is written for exactly one Wyrd release, `BustleWyrdBridge.WYRD_VERSION` (1.0.1).

- `BustleWyrdBridge.is_supported()` is true only when `res://addons/wyrd/VERSION` is that release.
- `BustleWyrdBridge.supports(wyrd)` is true only when the Wyrd object you pass reports it through `get_version()`.

When either check fails, `install` does nothing and returns null.

The bridge uses Wyrd's stable calls first. It reaches Wyrd's experimental surface only for the reads that have no stable form; the exact version check is what makes those safe.

| Bridge | Wyrd, stable | Wyrd, experimental |
| --- | --- | --- |
| Recording a deed | `deeds.record` | |
| Opinions | | `social.disposition` |
| Relationship kinds | | the kinds in `social.export_state()` |
| Reasons for an opinion | | the deed log's rows |
| Who knows a deed, passing news on | | the deed log's rows, `deeds.note_believer` |
| Changing a role | `roles.assign`, `roles.vacate` | |
| Who holds a role | | `roles.holder`, `roles.roles_of` |
| Role changes | `role_holder_changed`, `role_vacant`, `election_needed` | `succession_requested`, `roles.history` |
| Dialogue facts | `register_function` | |

## Installing

```gdscript
var bridge := BustleWyrdBridge.install(society, wyrd, mood_of)
```

- `wyrd` is Wyrd's facade (the `Wyrd` node), or anything with the same members.
- `mood_of` is optional: `(id) -> mood`, where a mood has a `mood` number, an `emotion` and `reasons()`, such as a `BustleMood`. Without it, the mood facts report nothing.

`install` sets the society's `social` port to a `BustleWyrdSocialPort` and its `roles` port to a `BustleWyrdRolesPort`, then registers the dialogue facts. The built-in `BustleSocialStore`, and with it `BustleRelationshipRules`, are not used: opinions and kinds come from Wyrd's own rules, which the host configures in Wyrd.

Install once for each Wyrd. Wyrd refuses a host function name that's already registered, so a second install's dialogue facts are refused. `bridge.registered` lists the names Wyrd accepted.

## The social port

`BustleWyrdSocialPort` keeps to the social port's contract (see `addons/bustle/ports/social_port.gd`). Ids are opaque, so a deed's actor, target or witness needn't be a society agent.

- **`record_deed`** records the deed with Wyrd's `deeds.record`: the interaction id as the verb, the witnesses' ids as an explicit list, each id once. The key is `deed_<Wyrd deed id>`.
- **`knows(agent, key)`** is true for the deed's actor, its witnesses, and anyone who believes it, whether from `share_news` or from one of Wyrd's own rumours. A key Wyrd has merged away by compacting its log is no longer known.
- **`share_news(teller, listener, place)`** passes on the deeds the teller did or witnessed and the listener doesn't know yet, oldest first. Each is noted in Wyrd as believed by the listener at Wyrd's current minute. A believer knows the deed second-hand, so it can't pass it on. Nothing is rolled, and `place` isn't used.
- **`opinion(a, b)`** is Wyrd's disposition of `a` toward `b`, 0 to 100.
- **`kinds_between(a, b)`** lists the kinds `a` holds toward `b` in Wyrd, sorted.
- **`reasons(a, b, limit)`** lists, newest first, the deeds `b` did that `a` was the target or a witness of. These are the deeds Wyrd's disposition counts. Each is `{deed, verb, minute, as}`, where `as` is `target` or `witness`.

## The roles port

`BustleWyrdRolesPort` reads and changes Wyrd's role bindings.

- `set_holder(role, id)` assigns with `roles.assign`.
- `set_holder(role, "")` vacates with `roles.vacate`, which runs the role's succession. The role may pass to a successor rather than stay empty.

`holder_changed` repeats every change Wyrd makes, whoever made it:

| Wyrd signal | `holder_changed` |
| --- | --- |
| `role_holder_changed(role, old, new)` | `(role, old, new)` |
| `role_vacant(role)` | `(role, old, "")`, where `old` is the last entry of the role's history |
| `election_needed(role, departed)`, `succession_requested(role, departed)` | `(role, departed, "")`: the role is contested, and empty until someone is assigned |

## Dialogue facts

`BustleWyrdFacts` registers these host functions with `register_function`. Content calls them like any other function, for example `npc_goal(x) == eat`. Wyrd is calling a host callable, never Bustle.

| Function | Returns |
| --- | --- |
| `npc_goal(entity) -> symbol` | The goal the agent chose on its last tick. Empty when idle. |
| `npc_goal_reason(entity) -> symbol` | The need that weighed most in that choice (ties by id). Empty when no need did. |
| `npc_need(entity, symbol) -> float` | That need's pressure on its last tick, 0 to 1. |
| `npc_top_need(entity) -> symbol` | Its most pressing need (ties by id). Empty when none is above 0. |
| `npc_mood_band(entity) -> symbol` | `low`, `normal` or `high`. |
| `npc_emotion(entity) -> symbol` | Its dominant emotion. |
| `npc_mood_reason(entity) -> symbol` | Its strongest active thought. |

An unknown agent, or one with nothing to report, gives an empty symbol or 0.

The mood bands reuse the mental states' own lines, from `BustleWyrdFacts.mood_bands`, a `BustleMentalConfig`:

- **`low`**: below `break_threshold`, where low states start (30 by default).
- **`high`**: above `high_spirits_above`, where high spirits can start (80 by default).
- **`normal`**: everything between.

## What the bridge doesn't do

- **Formulas, policies and timing are the host's.** That covers the disposition formula, rumour policies and how fast news spreads. Register them in Wyrd (`register_disposition_formula`, `register_rumor_policy`, `configure`).
- **Quest stages don't lock agents through the bridge.** A host maps them to `BustleSociety.lock` itself.
- **Saving is Wyrd's.** Deeds, beliefs, kinds and roles are in Wyrd's save. The bridge has no state of its own.

## Testing

`tests/wyrd/` runs against the test-only copy of Wyrd in `addons/wyrd/` (pinned in `tools/wyrd-pin.env`), with anonymous agents. CI's `test-core-only` job deletes the bridge, that copy and those tests, and runs the core alone.
