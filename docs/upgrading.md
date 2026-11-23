# Upgrading

One section per release, newest first: what a host has to check or change when it moves up. The full list of changes is in `CHANGELOG.md`. What counts as breaking, and how deprecations work from 1.0 on, is in [public-api/VERSIONING.md](public-api/VERSIONING.md).

## 1.0 to 1.1

**Nothing to change.** No port, public class, method, signal or setting was removed or renamed, no frozen signature or default changed, and every save written by 0.8.0, 0.9.0 or 1.0.0 still loads (CI loads golden saves from all three). Everything new is opt-in: a 1.0 host that doesn't call it runs exactly as before, and the demo and soak hashes are unchanged.

**Check one thing:** a host class that extends `BustleCareers`, `BustleCrimeWatch`, `BustleJobBoard`, `BustleWorkType`, `BustleCareerRank`, `BustleAspirationConfig` or `BustleFetchHelpAction`, and declares a member with one of the names below, must rename it. The new members would clash with it.

**New, all `@experimental`** ([public-api/PUBLIC_API.md](public-api/PUBLIC_API.md)). Each has a snippet in [host-hooks.md](host-hooks.md):

- **Careers:**
  - `BustleCareerRank.periods`, `BustleCareerPeriod`, `BustleCareers.update_in_period()` and `BustleCareers.window_period()` review by a period the host names. `update()` is unchanged.
  - `BustleCareers.reset_window()` starts a fresh review window after a break. Days off still pause the window by default.
- **Crime:** `BustleCrimeWatch.deed_of_item()` and `BustleCrimeWatch.stolen_goods_held_by()` follow stolen goods after they change hands. `stolen_goods_of()` is unchanged.
- **Aspirations:** `BustleAspirationConfig.max_points` caps points. It's unset (-1) by default.
- **Work:**
  - `BustleWorkType.min_capacities` (empty by default) and `BustleWorkType.short_capacity()` name and test minimum health capacities.
  - `BustleJobBoard.refusal()` says why a claim would be refused.
  - `BustleJobBoard.release_unfit()` lets go of claims held below a minimum. `settle()` and `work()` call it, and with no minimums it releases nothing.
- **Health:** three opt-in goals, `BustleSeekCare`, `BustleRestSick` and `BustleFetchHealer`, with their actions. Fetching a healer moves by the conflict's fetch-help rule, now shared as `BustleFetchHelpAction.approach()`; the conflict's own fetch-help is unchanged. `BustleFetchHealer` saves its errands (version 1).

**Now frozen.** `validate()` on `BustleAspirationConfig`, `BustleMentalConfig`, `BustlePerceptionProfile`, `BustleRelationshipRules` and `BustleStealthRules`, and `BustleCrimeWatch.prune()`, were experimental in 1.0. They now follow the frozen rules, with the same behaviour.

**Demo and releases.** The demo has a small room set (`demo/environment/demo_rooms.gd`) and an opt-in demo of the new hooks (`demo/hooks/demo_hooks.gd`). Neither is part of the addon. A release adds an example-project zip beside the two addon zips ([RELEASE.md](RELEASE.md)).

## 0.9.x to 1.0

There was no 0.9.1, so this covers everything since 0.9.0. **No port, public class, method, signal or setting was removed or renamed, no port signature changed, and every save written by 0.8.0 or 0.9.0 still loads.** What changes is mostly what Bustle says about bad input, and that the API now makes promises.

**What 1.0 promises**

- **The public API is frozen.** [public-api/PUBLIC_API.md](public-api/PUBLIC_API.md) lists every frozen class, port, Callable hook, signal and save-state call. Anything not listed, and anything still marked `@experimental` (the debug tools and the brain's internals), may change in a minor release. A host that reaches into a member with a leading `_` or an unlisted class should move to a listed one.
- **Deprecation before removal.** A frozen symbol is deprecated in a minor release, warns once through `BustleDeprecation`, and is removed only in the next major release.
- **Supported Godot:** 4.7.x. CI tests 4.7.2-stable on Linux and Windows. Other versions and macOS are not tested.

**Bad input now warns or refuses the same way everywhere** ([errors.md](errors.md))

- **New one-time warnings.** An invalid config or definition, missing wiring, a non-finite number and the like used to be ignored silently. Now each warns once per run with `push_warning()`, then behaves as before. A test suite that fails on any warning may see new ones from its own bad-input tests.
- **Hooks of the wrong type.** A Callable hook that returns the wrong type, `null` included, used to raise a script error on every call. Now it warns once and the call acts as if the hook were unset. For a gate (`BustleBrain.gate`, `BustleConversation.accepts`, `BustleCareers.review_hook`, `BustleRomance.ratings_policy`) that means a broken gate lets everything through: check that every hook returns its documented type.
- **Refused imports keep the old state.** `BustleBrain.import_state()` and `BustleSequenceRunner.import_state()` used to clear the brain or runner before refusing a save that didn't fit. Now they check first, so a refused import leaves everything as it was. A host that relied on a refusal clearing the brain should clear it itself.
- **No `push_error()` for host input.** `BustleModifierSet.set_source()`, `BustleSociety.register_archetype()` and `BustleSociety.add_agent()` warn once instead. Their return values are unchanged. A test that counted their errors now sees none.
- **The void imports warn.** `BustleAwareness.import_state()` and `BustleDetectionMeter.import_state()` still import what they can, and now warn once about a bad row or value.

**Saves** ([saves.md](saves.md))

- Every `import_state()` reads its save's version and migrates older ones one step at a time. A save from a **newer** version is refused and changes nothing. `BustleSaveFormat.check(format, saved)` gives the reason, and `BustleSaveFormat.current(format)` the version this release writes.
- Exports are unchanged. Golden saves from 0.8.0 and 0.9.0 load in CI.

**Configuration** ([config.md](config.md), [defaults-review.md](defaults-review.md))

- Every default was reviewed and kept; no value changed.
- `BustlePerceptionProfile`, `BustleMentalConfig`, `BustleStealthRules`, `BustleRelationshipRules` and `BustleAspirationConfig` gain a `validate()` (experimental). A pair out of order (for example `suspicious_at` above `alert_at`) now warns once; the values are still used as they are.
- `BustleSimRingConfig.offscreen_interval_game_minutes` at 0 or below now counts as 1 game minute on the live tick, as it already did in catch-up. Valid values are unchanged.

**Ports**

- **No new port methods and no signature changes.**
- `BustleRolesPort` and `BustleCombatPort` now declare a private constant, `_Warn`. A host subclass of either that declares a member named `_Warn` fails to load: rename it.
- The data the default ports keep (`BustleTradePort`, `BustleEnvironmentPort`, `BustlePropertyPort`) loads through the same version check as every other save, so their saves from 0.9.0 load and a newer one is refused.

**Checklist**

1. Read the new warnings in a debug run and fix each cause (a config, a definition, a hook's return type).
2. Make every Callable hook return its documented type, so no broken gate passes silently.
3. If anything relied on a refused brain import clearing the brain, clear it yourself.
4. Rename any `_Warn` member in a subclass of `BustleRolesPort` or `BustleCombatPort`.
5. Move off any internal (unlisted) class or `_`-prefixed member.

## 0.8.0 to 0.9.0

No public class, method, signal or setting was removed or renamed, and every new setting defaults to the 0.8.0 behaviour. Every new module is opt-in. Four changes can still affect a 0.8.0 host.

- **Long clock jumps.** `BustleSimRings.tick()` no longer replays an off-screen backlog longer than `catch_up_cap_game_days` hour by hour. The older time goes to `summary_hook`, with a `caught_up` report, as `catch_up()` already did. A host that relied on every missed hour being thought after a long jump now gets the summary instead.
- **`BustleSchedule.report()`** takes an optional fourth argument, `activity`. Callers are unaffected, but a subclass that overrides `report()` must add the parameter.
- **New methods on existing ports,** each with a default that keeps the 0.8.0 behaviour:
  - `BustleSocialPort`: `supports_kinds`, `set_kind`, `clear_kind`;
  - `BustleWorkPort`: `board`, `can_do`, `claimed_of`, and a second, optional `_init()` argument for the board;
  - `BustleEnvironmentPort`: `scores`, `is_indoors`, `conditions`, `conditions_of`, and the built-in store (`set_room`, `set_scores`, `export_state`, `import_state`);
  - `BustleLifeStagePort`: `allows_goal`, `allows_affordance`;
  - `BustleHealthPort`: `capacity`, `pain`, `needs_care`, `is_contagious`, `visible_tags`, `care`;
  - `BustleWorldPort`: `request_spawn`.

  A host subclass that already defines a method with one of these names and a different signature must rename it.
- **`BustleEnvironmentPort` keeps data.** Its default `room_of()` now reads a built-in store, kept in the private members `_rooms` and `_scores`. A host subclass that declares either name must rename it.

**Checklist**

1. Check any code that expected every off-screen hour to be replayed after a long clock jump.
2. Add the `activity` parameter to any override of `BustleSchedule.report()`.
3. Rename any method in a port subclass that clashes with a new port method, and any `_rooms` or `_scores` member in a `BustleEnvironmentPort` subclass.
