# Asset Library listing (draft)

The text for Bustle's entry in the [Godot Asset Library](https://godotengine.org/asset-library/asset), one field per heading, in the order of the submission form. **This is a draft: nothing has been submitted.** Submitting is a separate step that needs the maintainer's go-ahead; [RELEASE.md](../RELEASE.md#the-asset-library-listing) has the steps.

Fields marked *at submission* are filled in from the release being listed.

## Asset Name

Bustle

## Category

Scripts (an Addons category, so it shows in a project's AssetLib tab, not the Project Manager's).

## Godot version

4.7

The form takes one Godot version per entry. Bustle supports Godot 4.7.x and CI tests 4.7.2-stable.

## Version

1.1.0 (the release's version from `addons/bustle/VERSION`; check it against the tag at submission).

## Repository host

GitHub

## Repository URL

https://github.com/Trusdan/bustle

## Issues URL

Left empty: the repository's own GitHub issues.

## Download Commit

*At submission:* the full commit hash of the release tag (`git rev-parse vX.Y.Z^{commit}`). The Asset Library downloads GitHub's archive of that commit, which `.gitattributes` limits to the addons, `LICENSE` and `README.md`.

## Icon URL

*At submission:* `https://raw.githubusercontent.com/Trusdan/bustle/<download commit>/docs/asset-library/icon.png`

A direct link to the 256 × 256 PNG, pinned to the same commit so it never changes under the entry.

## License

MIT

## Description

Plain text (the form doesn't render Markdown):

```text
Bustle gives a Godot game a living population: the people of a place and their daily life. Each person has needs, a mood, a personality, memories, opinions of others and a daily schedule, and picks what to do next from what the world offers. It runs headless, so it works in 2D or 3D and with any movement, animation or dialogue system.

Optional modules, each switched on or off on its own: perception (sight, hearing and awareness), jobs and wages, skills and careers, social life and conversations, romance, life stages, ambitions, rooms and indoors, reactions to health (seeking care, resting when sick and fetching a healer), cause-driven conflict, theft with witnesses and reporting, and a storyteller that fires the game's own events when the story needs them.

The game connects Bustle to its world through small ports (the clock, the map, roles, combat, trade and others). A walkthrough, a guide to every port and a standalone example project are in the repository. A society saves and loads as plain data.

Written in GDScript only, with static typing, no native code and no other addons required. An optional bridge to the Wyrd narrative engine is included in addons/bustle_wyrd; it does nothing unless Wyrd is installed and the bridge is set up, and can be left out.

The public API is stable from 1.0: listed classes and methods are deprecated with a warning before they are removed, and removed only in a major release.

Supports Godot 4.7. MIT licensed.
```

## Previews

None yet. Up to three images or videos can be added later.
