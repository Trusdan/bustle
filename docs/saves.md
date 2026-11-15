# Saves across versions

A game saves Bustle by calling `export_state()` on each thing it keeps (the society, and whichever modules it uses), and loads it with `import_state()`. This page covers what each save is, which versions this release reads, and how a save format changes without breaking the players' saves. The rule behind it is in [public-api/VERSIONING.md](public-api/VERSIONING.md): a format change needs a migration from every format written since the last major release.

## The rule

- **Every save has a version.** Most saves have never written one, and for them a missing `"version"` means version 1. The society's version is its `"schema"`. The brain, the director and life stages write `"version"`.
- **An older version is migrated.** It goes one step at a time (version 1 to 2, 2 to 3, and so on) to the current one, then loads as usual. Each step works on a copy: the payload the host passed in is never changed.
- **A newer version is always refused.** Nothing changes, and the reason names both versions. This release can't know what a later one added, so it never guesses.
- **The other refusals each have their own reason:** a missing version where one is required, a version that isn't a whole number, and a version with no step from it. A whole-number float counts as its integer, because JSON reads whole numbers back as floats.

`BustleSaveFormat.check(format, saved)` gives the reason for any save, before or after `import_state()` refuses it. `format` is the class name, such as `&"BustleDirector"`. It returns a `BustleImportReport`: `ok`, `schema` (the version the payload claims, or -1), and `errors`. `BustleSaveFormat.current(format)` is the version this release writes. The society's `import_state()` puts the same reason in its own report. The other imports return `false`, or change nothing for the two that return nothing (`BustleAwareness` and `BustleDetectionMeter`); for those, `check()` is how a host reads why.

```gdscript
var report := BustleSaveFormat.check(&"BustleDirector", saved_director)
if not report.ok:
    show_load_error(report.errors[0])  # "BustleDirector version 2 is newer than this version reads (1)"
```

A save whose `"version"` holds a Dictionary is read as data, not as a version. Some saves are keyed by agent id, so an agent called `version` keeps loading.

## What each save is

| Save | Version key | Current | Reads | 0.8.0 wrote | 0.9.0 wrote |
| --- | --- | --- | --- | --- | --- |
| `BustleSociety` | `"schema"` | 1 | 1 | 1 | 1 |
| `BustleBrain` (inside the society's agents) | `"version"` | 1 | 1 | 1 | 1 |
| `BustleDirector` | `"version"` | 1 | 1 | not present | 1 |
| `BustleLifeStages` | `"version"` | 2 | 1, 2 (a 1 → 2 step) | not present | 2 |
| `BustleAffordance`, `BustleAffordanceSet`, `BustleAmbitions`, `BustleAwareness`, `BustleConflict`, `BustleCrimeWatch`, `BustleDetectionMeter`, `BustleLeisure`, `BustleMemory`, `BustleMentalBehaviour`, `BustleMentalState`, `BustleMood`, `BustleNeedSet`, `BustlePersonality`, `BustlePropertyPort`, `BustleSchedule`, `BustleScheduleRoster`, `BustleSequenceRunner`, `BustleSocialInteractions`, `BustleSocialStore`, `BustleTradePort` | `"version"`, missing = 1 | 1 | 1 | 1 (no key) | 1 (no key) |
| `BustleAspirations`, `BustleCareers`, `BustleEnvironmentPort`, `BustleJobBoard`, `BustleRomance`, `BustleRoomThoughts`, `BustleSkills` | `"version"`, missing = 1 | 1 | 1 | not present | 1 (no key) |

The save code of every class above is the same in 0.8.0, 0.9.0 and this release, so their saves load as they are. Life stages' version 1 was written only between those releases. It still loads through its 1 → 2 step, which anchors each age at minute 0, sets now to 0 and records nobody dead.

## Changing a save format

When a change alters what an `export_state()` returns:

1. **Raise the version.** Raise the class's `STATE_VERSION` (the society's `SCHEMA`). A class that has never had one gets `const STATE_VERSION := 2`, writes `"version": STATE_VERSION`, and moves from the unversioned list in `addons/bustle/core/save_format.gd` to the versioned one. The public API check notes a raised `STATE_VERSION` or `SCHEMA` as a save-format change rather than failing it.
2. **Add the step next to `import_state()`.** It goes in the class's static `_save_format()`, which returns its key, current version and steps:

   ```gdscript
   static func _save_format() -> Dictionary:
       return {"key": "version", "current": STATE_VERSION, "steps": {1: _from_version_1}}

   ## Version 1 had no anchors: each age is anchored at minute 0.
   static func _from_version_1(saved: Dictionary) -> Dictionary:
       saved["version"] = 2
       # ...reshape saved into the version 2 layout...
       return saved
   ```

   A step takes a copy of the version N payload and returns the N + 1 layout, with its version set. It never fails: anything malformed is left for `import_state()`'s own checks, which run on the result. `import_state()` starts with `BustleSaveFormat._read(&"BustleExample", saved, _save_format())` and carries on with its `data`. Keep every step until the next major release; a step for a format older than that can go then.
3. **Keep the old saves.** Don't rewrite anything an older release wrote. Saved files from the release that wrote the old shape are what prove the step works.
4. **Note it in the CHANGELOG** under "Changed", naming the class and both versions.

A format change with no step is a breaking change, and needs a major release.

## Tests

`tests/save/test_save_format.gd` checks the step runner on small payloads, and checks that every save refuses a newer version, changes nothing and gives a reason through `check()`. Each class's own tests cover what its import accepts.
