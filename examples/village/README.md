# Bustle example: a village

A small, standalone Godot 4.7.x project that shows Bustle running a handful of villagers. Four of them get hungry and tired, work the job that comes with the role they hold, walk between the bakery, their workshops, the square and their homes, and greet each other in the square. Their mood rises with fresh bread and cosy rooms, and their skill grows with practice. The scene draws each villager as a dot coloured by mood, with what it is doing.

It is separate from the demo (`demo/`) and the tests, and uses Bustle's public API only.

## Open it

**From a release:** `bustle-example-<version>.zip` holds this project with the addon already in it. Unzip it, open `bustle-example-<version>/project.godot` in Godot 4.7.x and press Play.

**From the repository:** the example needs a copy of the addon in its own `addons/` folder. That copy isn't committed (the one copy lives in the repository's `addons/bustle/`), so make it first, from the repository root:

```
tools/example.sh
```

Then open `examples/village/project.godot` in Godot 4.7.x and press Play. Without a shell, copying `addons/bustle/` into `examples/village/addons/` by hand does the same.

`tools/example.sh --check` is what CI runs. It loads the example headless and fails on any error or warning: the import, a two-day run with checks (`check.gd`), the main scene for 300 frames, and the editor.

## What is where

| File | What |
| --- | --- |
| `village.gd` | The simulation, headless: the society, its ports, the villagers' needs, moods and brains, and the host's side (walking, eating, working). |
| `village_view.gd`, `village.tscn` | The scene: draws the village each frame. It only reads the simulation. |
| `host/host_clock.gd` | The host's clock, a `BustleClockPort` (Bustle reads the minute; the game moves it). |
| `host/host_world.gd` | The host's map, a `BustleWorldPort` (areas and places). |
| `check.gd` | Runs two game days headless and checks that every part shows up. |

## What it uses

- **Core:** a `BustleSociety` with one archetype; needs (`BustleNeedSet`); brains choosing between using what's on offer (`BustleAdvertisement`) and working; jobs from roles (`BustleRolesPort` with a `BustleRoleTable`, and a `BustleScheduleRoster`); greetings through the built-in social store (`BustleSocialStore`, `BustleSocialInteractions`).
- **Modules:**
  - `needs_mood/`: a `BustleMood` per villager, with a good thought after a meal;
  - `skills/`: `BustleSkills` as the skills port, with practice at work;
  - `environment/`: rooms with scores in the environment port, and `BustleRoomThoughts` for cosy and bare rooms.
- **Ports:** two small host adapters, for the clock and the world. Roles, social, skills and environment use Bustle's own implementations. Every port's contract is in the repository's `docs/ports.md`, and `docs/host-walkthrough.md` connects the same three ports step by step.

## Flavor text

The villagers' names, the places, jobs, skills and thoughts are **PROPOSED** placeholder text, neutral and generic, and may change.
