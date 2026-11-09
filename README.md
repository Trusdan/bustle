# Bustle

A generic addon for living non-player populations in Godot 4 (4.7 or newer): the people of a place and their daily life. MIT licensed.

**Status: 0.5.0.** It has the project scaffold (0.1.0), the perception module (0.2.0: senses for every actor, awareness queries and dispositions) and the headless simulation core (0.3.0: the utility scorer, brains with action sequences, the host ports, the society registry with save and load, orders, debug tools and simulation rings). 0.4.0 adds needs, mood and thoughts, affordances, schedules with roles, jobs and wages, personality sliders and trait bundles, memory and FindPerson, social opinions, greetings, conversations and comfort, and trade-port buying, with owners taking from their own stock for free. 0.5.0 adds cause-driven conflict: fight, flee or fetch help, an intent to subdue or kill only for a reason, non-lethal scuffles, quarrels, and assaulted and killed events, with the combat port taking an intent and reporting how a fight ended. APIs remain experimental before 1.0. More features come in later releases.

## Layout

| Folder | What |
| --- | --- |
| `addons/bustle/` | The addon. Depends only on Godot. |
| `addons/bustle/core/` | Plain data and rules with no nodes, tested headless. `needs/`: the needs engine ([docs/needs.md](docs/needs.md)). `affordances/`: smart objects ([docs/affordances.md](docs/affordances.md)). `schedules/`: daily routines ([docs/schedules.md](docs/schedules.md)). `personality/`: sliders and traits ([docs/personality.md](docs/personality.md)). `memory/`: memory and FindPerson ([docs/memory.md](docs/memory.md)). `conflict/`: fight, flee and fetch help ([docs/conflict.md](docs/conflict.md)). |
| `addons/bustle/society/` | How the members of a population relate to each other. The built-in social store ([docs/social.md](docs/social.md)). |
| `addons/bustle/ports/` | The interfaces a host project implements to connect Bustle to its world. |
| `addons/bustle/debug/` | Tools for inspecting a running population. |
| `addons/bustle/modules/` | Optional features, each usable on its own. `perception/`: senses for every actor ([docs/perception.md](docs/perception.md)). `needs_mood/`: mood and thoughts ([docs/mood.md](docs/mood.md)). |
| `addons/bustle_wyrd/` | Optional bridge to the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine, pinned to Wyrd 1.0.1. |
| `addons/wyrd/` | A test-only copy of Wyrd 1.0.1 for the bridge tests (`tools/wyrd-pin.env`). Not part of a release. |
| `addons/gut/` | Vendored [GUT](https://github.com/bitwes/Gut) 9.7.1, for the tests only. |
| `demo/` | A small neutral demo (a skeleton in 0.1.0). |
| `docs/api/` | The API reference, generated from the `##` doc comments. |

## Install

Copy `addons/bustle/` into your project's `addons/` folder and enable **Bustle** under Project Settings → Plugins. If you also use Wyrd 1.0.1, you can copy `addons/bustle_wyrd/` too.

## Develop

```bash
tools/run_tests.sh          # import the project and run GUT headless (Godot from tools/pins.env on PATH)
tools/gen_api_docs.sh       # regenerate docs/api/ after changing doc comments
tools/check_wyrd_pin.sh     # check addons/wyrd/ against tools/wyrd-pin.env
tools/test_check_hygiene.sh # self-test of the content-hygiene check
godot --headless --path . -s res://bench/perception_bench.gd  # perception performance (docs/perf.md)
```

CI runs on Ubuntu and Windows, runs the core alone with the bridge and Wyrd removed, checks the API docs and that the editor loads the project cleanly, and checks every change against a private deny-list of terms.

See [CHANGELOG.md](CHANGELOG.md) and [docs/RELEASE.md](docs/RELEASE.md).
