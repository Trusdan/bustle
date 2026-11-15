# Versioning and deprecation

Bustle and its Wyrd bridge follow [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`). This page says what that promises, what counts as a breaking change, and how an API is retired.

- **What it applies to:** the frozen public API in [PUBLIC_API.md](PUBLIC_API.md), with every symbol and signature in [public_api.json](public_api.json). Anything not listed there is internal (the page says how internal code is marked), and has no promise.
- **When it applies:** in full from 1.0.0. Before 1.0 the check below already runs, so a breaking change to the listed surface has to be recorded in [deprecations.json](deprecations.json). It can't slip through unnoticed.

## What each release may change

| Release | May | May not |
| --- | --- | --- |
| Patch (`1.2.3` → `1.2.4`) | Fix bugs. Change internal code. | Change the public API, except to fix a symbol that doesn't do what its doc comment says. |
| Minor (`1.2.x` → `1.3.0`) | Add classes, members, ports, hooks, signals and modules. Deprecate. Change behaviour or tuning defaults, noted in the CHANGELOG. | Break anything listed below. |
| Major (`1.x` → `2.0.0`) | Remove deprecated symbols. Make other breaking changes, each listed under "Breaking changes" in the CHANGELOG. | |

The two addons share one version number (`tests/core/test_versions_agree.gd` checks it), and the bridge follows the same rules for its own classes.

## What counts as breaking

For any frozen symbol:

- **A removed or renamed symbol:** a class, method, property, Callable hook, signal or constant. Moving a frozen symbol back to `@experimental` counts as removing it.
- **A changed method signature:** a parameter added, removed, renamed, retyped or reordered, a changed default value, a changed return type, or a method made static or no longer static. This includes adding an optional parameter. Port methods are overridden by hosts, and GDScript requires an override to match, so any change to one breaks them. Add a new method instead, and deprecate the old one.
- **Changed signal arguments:** an argument added, removed, renamed, retyped or reordered.
- **A changed hook signature:** the call a Callable hook makes (its arguments and what it must return), or the hook's type. The call is the `[code]func(<params>) -> <Return>[/code]` that opens the hook's doc comment, with every parameter named and typed. The manifest records it as the hook's `call`.
- **A changed property type, base class, or constant or enum value.**
- **A save-format change without migration:** a change to what an `export_state()` returns, unless `import_state()` still reads every format written since the last major release. A format change raises that class's `STATE_VERSION` (where it has one) and comes with the code that reads the older shape. [saves.md](../saves.md) says how to add that step.

These are not breaking:

- new classes, members, modules, ports, hooks and signals;
- a new port method with a default that keeps the old behaviour (a host's port that doesn't override it keeps working);
- changed behaviour or tuning defaults within what the doc comments promise, listed under "Changed" in the CHANGELOG;
- anything internal or `@experimental`.

## Deprecating and removing

A frozen symbol is retired in two steps.

1. **Deprecate it, in a minor release.** The symbol keeps working. Then:
   - Its doc comment gets `@deprecated:` with what to use instead.
   - Its entry point calls `BustleDeprecation.warn("BustleExample.old_name", "BustleExample.new_name")`, which pushes a warning once per symbol per run.
   - The CHANGELOG lists it under `### Deprecated`.
   - [deprecations.json](deprecations.json) gets an entry:

   ```json
   {"symbol": "BustleExample.old_name", "since": "1.3.0", "replacement": "BustleExample.new_name", "note": "Why, in one line."}
   ```

   A symbol is a class (`BustleExample`, which covers all its members) or a member (`BustleExample.old_name`). `since` is the release that deprecated it. `replacement` and `note` are optional.
2. **Remove it, only in a major release.** A deprecated symbol must ship, with its deprecation warning, in at least one minor release before the major release that removes it. For example, a symbol deprecated in `1.3.0` can be removed in `2.0.0` at the earliest. The deprecations.json entry stays: it's what lets the check accept the removal, and only in such a major release. The CHANGELOG lists the removal under `### Removed` and "Breaking changes".

A signature change goes the same way: add the new form, deprecate the old one, and remove it in the next major release. The removal needs its deprecations.json entry too.

## The check

`tools/public_api.sh` regenerates the manifest from the `##` doc comments (with Godot's doctool) and compares it with the committed `docs/public-api/public_api.json`. In CI it also compares it with the manifest on the pull request's base branch.

- It **fails** when a frozen symbol is removed, renamed or changed, or stops being frozen, and deprecations.json has no entry for it or its class. It also fails when deprecations.json is malformed, or when PUBLIC_API.md doesn't match the manifest.
- It **fails a covered removal** too (a symbol removed, renamed or moved back to `@experimental`, with an entry for it or its class) unless both of these hold:
  - the current version's major is above the major of the entry's `since`;
  - `since` is a minor release (`x.y.0` or a later patch, with `y` of 1 or more), so the warning shipped in a minor release before the major.

  The current version is the manifest's `version`, which `tools/public_api.sh` takes from `addons/bustle/VERSION`. A `since` of `X.0.0` names a major release with no minor after it, so a removal under it always fails. For example, with `since` 1.3.0, removing the symbol fails at 1.4.0 or 1.3.1 and passes at 2.0.0 or later. Each failure names the symbol, the current version and `since`. A covered signature change is not held to this rule.
- **When a removal can land.** `addons/bustle/VERSION` holds the last released version until the release-prep pull request bumps it. So a removal lands in the pull request that bumps the major version, or after it.
- It **fails a changed hook call**, like any other signature change: an argument added, removed, renamed or retyped, or a changed return type. It also fails a call that disappears from a hook's doc comment. A deprecations.json entry for the hook or its class covers a changed call, as it does any covered signature change.
- It **notes** a call recorded for the first time on a hook whose baseline had none. That documents an existing contract; it doesn't change it.
- It **passes** on new symbols, and notes that the manifest is behind the code.
- CI also runs `tools/save_fixtures.sh --check`: the golden save fixtures of each release must be exactly what that tag writes, and `tests/save/test_save_fixtures.gd` loads every one into the current code ([saves.md](../saves.md)).
- It **notes** a raised `STATE_VERSION` (or the society's `SCHEMA`) as a save-format change, so a reviewer can confirm that `import_state()` still reads the older shape.

```bash
tools/public_api.sh --check                   # against the committed manifest
tools/public_api.sh --check --base origin/main # also against the base branch, as CI does
tools/public_api.sh --write                   # record the current surface (refuses a breaking change with no entry)
```

`tests/api/test_public_api_check.gd`, `tests/api/test_public_api_removals.gd` and `tests/api/test_public_api_hook_calls.gd` prove the rules on fixtures in `tests/api/fixtures/`:
- a removal fails, and the same removal with a deprecation entry passes in the next major release;
- a covered removal in the same major, or one whose `since` was a major release, fails;
- a changed or dropped hook call fails, a covered one passes, and a first-recorded call is a note. Every frozen hook has a call.

## Marking what isn't frozen

- **`@experimental`** on a class's doc comment keeps the whole class out of the frozen surface. On a member's doc comment, it keeps that member out. Give the reason after a colon: `## @experimental: Development tool; its output may change.` Freezing something later is an addition, so it can happen in any minor release.
- A name that starts with `_` is internal, as is a script without a `class_name`.
- A frozen signature never names an experimental class (`tests/api/test_public_api.gd` checks this). A member that needs an experimental type is itself `@experimental`.
