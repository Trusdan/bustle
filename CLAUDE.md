# CLAUDE.md

Rules for AI coding agents (and humans) working in this repository. Read this before every task.
If a task description and this file disagree, follow this file and say so in the pull request.

## What this project is

Bustle is a **generic addon for living non-player populations in Godot 4** (4.7 or newer): the people of a place and their daily life. Any Godot game should be able to use it. It is MIT licensed.

- `addons/bustle/` is the addon. It depends **only on Godot**. Its folders: `core/` (plain data and rules, no nodes), `society/` (how members relate), `ports/` (interfaces the host implements), `debug/` (inspection tools) and `modules/` (optional features).
- `addons/bustle_wyrd/` is an **optional** bridge to the Wyrd narrative engine, pinned to one exact Wyrd release. Nothing in `addons/bustle/` refers to it.
- `addons/wyrd/` is a **test-only** copy of that Wyrd release (`tools/wyrd-pin.env`). Do not edit it.
- `addons/gut/` is vendored GUT (`tools/pins.env`). Do not edit it.
- `demo/` is a small neutral demo; `tests/` holds the GUT tests; `docs/api/` is generated.

## Generic only (no host-game terms)

- Never put a host game's names, places, characters, lore, story, ticket keys or links to its trackers in code, comments, tests, fixtures, docs, commit messages, branch names or pull request text.
- Examples and fixtures use neutral names only (a village, a baker, a smith, a well).
- No behaviour tied to one character or kind of character in code: differences come from data and profiles.
- CI checks every change against a private deny-list (the `BUSTLE_HYGIENE_TERMS` secret). The log never shows the term. If the check fails, find and remove the host-specific wording.

## Code style

- GDScript only. **No C#, no .NET, no GDExtension or other native code**, and no third-party addons except the vendored GUT (and the test-only Wyrd).
- **Static typing everywhere**: variables, parameters and return types.
- Public classes use the **`Bustle` prefix** (`class_name BustleInfo`). File names are **`snake_case`**.
- Indent with **tabs**.
- Every public class and method gets a **`##` doc comment**. API before 1.0 is marked **`@experimental`**.
- Put logic in plain **`RefCounted`** classes so GUT can test it headless. **`plugin.gd` stays thin.**

## Workflow

- **One pull request per task.** Branch from the latest `main` as **`claude/<short-slug>`**.
- **Never push to `main`, never merge, never force-push, never tag**, and never change repository settings, secrets or branch protection. The maintainer reviews, merges and tags.
- Change only the files the task allows. If another file needs a change, stop and describe it in the pull request.
- Commit messages use **[Conventional Commits](https://www.conventionalcommits.org/)** (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`).
- Aim for about **300 to 600 changed lines per pull request**, tests included (vendored folders and generated API docs don't count). If a task clearly needs more, stop at a clean point and propose a split.
- **Never commit secrets, tokens, credentials or `user://` files.**

## Before opening a pull request

1. Run **`tools/run_tests.sh`** with `godot` (the version in `tools/pins.env`) on `PATH`. All GUT tests must pass, with no new warnings or script errors.
2. If a `##` doc comment in `addons/bustle/` changed, run **`tools/gen_api_docs.sh`** and commit `docs/api/`.
3. Fill in every section of the pull request template.
4. Check that CI is green.

## When unsure

Take the smallest reasonable choice, keep going, and list the question under **Open questions** in the pull request description. Do not widen the scope of a task.
