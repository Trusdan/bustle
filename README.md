# Bustle

A generic addon for living non-player populations in Godot: the people of a place and their daily life. MIT licensed.

**Supported Godot:** Godot 4.7.x (CI tests 4.7.2-stable on Linux and Windows). Other Godot versions and macOS are not tested.

**Status: 0.9.0.** It has the project scaffold (0.1.0), the perception module (0.2.0: senses for every actor, awareness queries and dispositions) and the headless simulation core (0.3.0: the utility scorer, brains with action sequences, the host ports, the society registry with save and load, orders, debug tools and simulation rings). 0.4.0 adds needs, mood and thoughts, affordances, schedules with roles, jobs and wages, personality sliders and trait bundles, memory and FindPerson, social opinions, greetings, conversations and comfort, and trade-port buying, with owners taking from their own stock for free. 0.5.0 adds cause-driven conflict: fight, flee or fetch help, an intent to subdue or kill only for a reason, non-lethal scuffles, quarrels, and assaulted and killed events, with the combat port taking an intent and reporting how a fight ended. 0.6.0 adds guarded theft, witnesses and reporting, mental states, ambitions, and host locks with protection levels. 0.7.0 adds the optional Wyrd bridge, social ports for interactions and conversations, recording a theft by an outsider, and the house and colony demos. 0.8.0 adds a stuck watch and thought entries on the demo timeline, a 30-day demo soak, a 40 / 40 / 200 population bench, and rings that re-sort only when something calls for it. 0.9.0 adds a job board, skills and passions, careers, rooms and indoors/outdoors, wants and fears, romance, life stages, reactions to the host's health with a tend job, and a causal storyteller, all opt-in; full house and colony demo sessions with a module-toggle matrix, a tutorial and a module guide; and a bounded off-screen catch-up and an optional FULL cap on the simulation rings. APIs remain experimental before 1.0. More features come in later releases.

## Layout

| Folder | What |
| --- | --- |
| `addons/bustle/` | The addon. Depends only on Godot. |
| `addons/bustle/core/` | Plain data and rules with no nodes, tested headless. `needs/`: the needs engine ([docs/needs.md](docs/needs.md)). `affordances/`: smart objects ([docs/affordances.md](docs/affordances.md)). `schedules/`: daily routines ([docs/schedules.md](docs/schedules.md)). `personality/`: sliders and traits ([docs/personality.md](docs/personality.md)). `memory/`: memory and FindPerson ([docs/memory.md](docs/memory.md)). `conflict/`: fight, flee and fetch help ([docs/conflict.md](docs/conflict.md)). `crime/`: theft, witnesses and reporting ([docs/crime.md](docs/crime.md)). |
| `addons/bustle/society/` | How the members of a population relate to each other. The built-in social store ([docs/social.md](docs/social.md)) and locks ([docs/locks.md](docs/locks.md)). |
| `addons/bustle/ports/` | The interfaces a host project implements to connect Bustle to its world: each port's contract, a minimal implementation and common mistakes are in [docs/ports.md](docs/ports.md), and [docs/host-walkthrough.md](docs/host-walkthrough.md) connects the clock, world and roles from an empty project. |
| `addons/bustle/debug/` | Tools for inspecting a running population. |
| `addons/bustle/modules/` | Optional features, each usable on its own. `perception/`: senses for every actor ([docs/perception.md](docs/perception.md)). `needs_mood/`: mood, thoughts and mental states ([docs/mood.md](docs/mood.md)). `ambitions/`: long-term aims ([docs/ambitions.md](docs/ambitions.md)). |
| `addons/bustle_wyrd/` | Optional bridge to the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine, pinned to Wyrd 1.0.1. |
| `addons/wyrd/` | A test-only copy of Wyrd 1.0.1 for the bridge tests (`tools/wyrd-pin.env`). Not part of a release. |
| `addons/gut/` | Vendored [GUT](https://github.com/bitwes/Gut) 9.7.1, for the tests only. |
| `demo/` | A small neutral demo: the house and colony scenes and a headless harness ([demo/README.md](demo/README.md)). |
| `examples/village/` | A small standalone example project: four villagers with needs, jobs from roles, a mood, skills and room thoughts, in a visible scene. It uses the public API only. Run `tools/example.sh` first to copy the addon in ([examples/village/README.md](examples/village/README.md)). |
| `docs/api/` | The API reference, generated from the `##` doc comments. |
| `docs/upgrading.md` | What to check or change when moving up a release, one section per release. |
| `docs/config.md` | Every config field and project setting with its type, default, range and effect, generated; the review of the defaults is in [docs/defaults-review.md](docs/defaults-review.md). |

## Install

Copy `addons/bustle/` into your project's `addons/` folder and enable **Bustle** under Project Settings → Plugins. If you also use Wyrd 1.0.1, you can copy `addons/bustle_wyrd/` too, and install it on a society (see `docs/wyrd-bridge.md`).

## Develop

```bash
tools/run_tests.sh          # import the project and run GUT headless (Godot from tools/pins.env on PATH)
tools/gen_api_docs.sh       # regenerate docs/api/ after changing doc comments
tools/config_reference.sh   # regenerate docs/config.md after changing an @export field or its range
tools/check_wyrd_pin.sh     # check addons/wyrd/ against tools/wyrd-pin.env
tools/test_check_hygiene.sh # self-test of the content-hygiene check
tools/check_godot_range.sh  # check the supported Godot range in README.md and plugin.cfg against tools/pins.env
tools/check_source_archive.sh # check that a source archive holds only the addons, LICENSE and README.md
godot --headless --path . -s res://bench/perception_bench.gd  # perception performance (docs/perf.md)
```

CI runs the GUT suite with the pinned Godot (`GODOT_TAG` in `tools/pins.env`) on Linux (Ubuntu) and Windows, checks that the supported Godot range above matches that pin (`tools/check_godot_range.sh`), runs the core alone with the bridge and Wyrd removed, checks the API docs and that the editor loads the project cleanly, and checks every change against a private deny-list of terms.

See [CHANGELOG.md](CHANGELOG.md) and [docs/RELEASE.md](docs/RELEASE.md).
