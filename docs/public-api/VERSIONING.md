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
- **A changed hook signature:** the call a Callable hook makes (its arguments and what it must return, as its doc comment states), or the hook's type.
- **A changed property type, base class, or constant or enum value.**
- **A save-format change without migration:** a change to what an `export_state()` returns, unless `import_state()` still reads every format written since the last major release. A format change raises that class's `STATE_VERSION` (where it has one) and comes with the code that reads the older shape.

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
2. **Remove it, only in a major release.** The deprecations.json entry stays: it's what lets the check accept the removal. The CHANGELOG lists the removal under `### Removed` and "Breaking changes".

A signature change goes the same way: add the new form, deprecate the old one, and remove it in the next major release. The removal needs its deprecations.json entry too.

## The check

`tools/public_api.sh` regenerates the manifest from the `##` doc comments (with Godot's doctool) and compares it with the committed `docs/public-api/public_api.json`. In CI it also compares it with the manifest on the pull request's base branch.

- It **fails** when a frozen symbol is removed, renamed or changed, or stops being frozen, and deprecations.json has no entry for it or its class. It also fails when deprecations.json is malformed, or when PUBLIC_API.md doesn't match the manifest.
- It **passes** on new symbols, and notes that the manifest is behind the code.
- It **notes** a raised `STATE_VERSION` as a save-format change, so a reviewer can confirm that `import_state()` still reads the older shape.

```bash
tools/public_api.sh --check                   # against the committed manifest
tools/public_api.sh --check --base origin/main # also against the base branch, as CI does
tools/public_api.sh --write                   # record the current surface (refuses a breaking change with no entry)
```

`tests/api/test_public_api_check.gd` proves the rules on fixtures in `tests/api/fixtures/`: a removal fails, and the same removal with a deprecation entry passes.

## Marking what isn't frozen

- **`@experimental`** on a class's doc comment keeps the whole class out of the frozen surface. On a member's doc comment, it keeps that member out. Give the reason after a colon: `## @experimental: Development tool; its output may change.` Freezing something later is an addition, so it can happen in any minor release.
- A name that starts with `_` is internal, as is a script without a `class_name`.
- A frozen signature never names an experimental class (`tests/api/test_public_api.gd` checks this). A member that needs an experimental type is itself `@experimental`.
