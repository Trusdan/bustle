# Changelog

All notable changes to Bustle. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Before 1.0, any minor version may change the API. Every public class is marked `@experimental` until then.

## [Unreleased]

### Added

- The perception module's headless core (`addons/bustle/modules/perception/`):
  - `BustleStealthRules`, `BustleVisibilityModel` and `BustleNoiseModel` with `BustleNoiseEvent`;
  - `BustleLightProbe`, `BustleLightSample`, `BustleLightSource` and `BustlePointLightProbe`;
  - `BustleSenseTarget`, `BustlePerceptionProfile` (with `sight_light` and `perception_hz`) and `BustleDetectionMeter` (with `seen_now`, `heard_now`, `since_sensed` and `sight_cone`).

  See `docs/perception.md`.
- The perception world:
  - `BustlePerceptionWorld`: any actor perceives any actor, with throttled and staggered senses and sight rays only for candidates. It has the queries `known_nearby`, `last_known`, `perceives`, `perceivers_of`, `awareness` and `known_with`, plus `broadcast` and `perception_changed`;
  - `BustlePerceptionActor`, `BustleAwareness` and `BustleAwarenessEntry`.
- Dispositions: `BustleDispositionPort` (`ports/`, neutral by default) and `BustleDispositionTable` (`society/`).
- Scene components: `BustlePerceptionSystem` (ticks the world, physics sight rays), `BustlePerceiver` and `BustlePerceivable`.
- The perception bench (`bench/perception_bench.gd`) and `docs/perf.md`. 40 actors average under 1.0 ms per frame.

## [0.1.0] - 2026-11-02

The project scaffold.

### Added

- The addon layout: `addons/bustle/` with `core/`, `society/`, `ports/`, `debug/` and `modules/`, and `BustleInfo` (the version and the folders).
- The optional Wyrd bridge's shell, `addons/bustle_wyrd/` (`BustleWyrdBridge`), pinned to Wyrd 1.0.0, with a test-only copy of Wyrd 1.0.0 in `addons/wyrd/`.
- Vendored GUT 9.7.1, the tests, a demo skeleton and the generated API docs.
- CI: Ubuntu, Windows, the core alone, the editor load, the API docs, the Wyrd pin and the content-hygiene check.
