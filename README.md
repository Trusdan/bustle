# Bustle

A generic addon for living non-player populations in Godot 4 (4.7 or newer): the people of a place and their daily life. MIT licensed.

**Status: 0.1.0 is the project scaffold only.** It has the addon layout, the optional Wyrd bridge's shell, the tests, a demo skeleton and CI. The features come in later releases.

## Layout

| Folder | What |
| --- | --- |
| `addons/bustle/` | The addon. Depends only on Godot. |
| `addons/bustle/core/` | Plain data and rules with no nodes, tested headless. |
| `addons/bustle/society/` | How the members of a population relate to each other. |
| `addons/bustle/ports/` | The interfaces a host project implements to connect Bustle to its world. |
| `addons/bustle/debug/` | Tools for inspecting a running population. |
| `addons/bustle/modules/` | Optional features, each usable on its own. `perception/`: senses for every actor ([docs/perception.md](docs/perception.md)). |
| `addons/bustle_wyrd/` | Optional bridge to the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine, pinned to Wyrd 1.0.0. |
| `addons/wyrd/` | A test-only copy of Wyrd 1.0.0 for the bridge tests (`tools/wyrd-pin.env`). Not part of a release. |
| `addons/gut/` | Vendored [GUT](https://github.com/bitwes/Gut) 9.7.1, for the tests only. |
| `demo/` | A small neutral demo (a skeleton in 0.1.0). |
| `docs/api/` | The API reference, generated from the `##` doc comments. |

## Install

Copy `addons/bustle/` into your project's `addons/` folder and enable **Bustle** under Project Settings → Plugins. If you also use Wyrd 1.0.0, you can copy `addons/bustle_wyrd/` too.

## Develop

```bash
tools/run_tests.sh          # import the project and run GUT headless (Godot from tools/pins.env on PATH)
tools/gen_api_docs.sh       # regenerate docs/api/ after changing doc comments
tools/check_wyrd_pin.sh     # check addons/wyrd/ against tools/wyrd-pin.env
tools/test_check_hygiene.sh # self-test of the content-hygiene check
```

CI runs on Ubuntu and Windows, runs the core alone with the bridge and Wyrd removed, checks the API docs and that the editor loads the project cleanly, and checks every change against a private deny-list of terms.

See [CHANGELOG.md](CHANGELOG.md) and [docs/RELEASE.md](docs/RELEASE.md).
