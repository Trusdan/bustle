# Changelog

All notable changes to Bustle. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Before 1.0, any minor version may change the API. Every public class is marked `@experimental` until then.

## [Unreleased]

### Added

- The utility scorer's headless core (`addons/bustle/core/brain/`):
  - `BustleBands`: priority bands as spaced whole numbers; only the highest band with an eligible candidate is chosen from.
  - `BustleInputs`: the fixed input families (`need`, `trait`, `opinion`, `memory`, `distance`, `schedule`, `role`, `fact`, `time`, `health`, `threat`) and `is_valid_input`.
  - `BustleConsideration`, `BustleGoalDef` (band, base weight, `min_score`, `min_commit_minutes`, preconditions, considerations, `uses_advertisements`) and `BustleGoalLibrary` (with `problems()`).
  - `BustleAdvertisement`, `BustleScoringConfig` and `BustleScoreContext`.
  - `BustleUtilityScorer`: goal scores, the signed advertisement score, eligibility with reasons, stable ordering, the 10%-of-best window and a uniform seeded pick, with an IDLE fallback; `BustleCandidate` holds each result.
- `BustleChoiceKeeper`: hysteresis around the scorer. The current choice gets ×1.15 momentum on its selection score (eligibility still uses the raw score), is kept while inside the pick window and through its goal's `min_commit_minutes`, and is interrupted at once by a strictly higher band. Failed goals cool down (`BustleGoalDef.fail_cooldown_minutes`, and at least the minute they failed). Its state exports and imports as plain data.
- `BustleModifierSet`: keyed numbers that sources add to and multiply, applied in sorted source order, with `fill_context` for the scorer's need weights and tag multipliers.
- `BustleGoalLibrary.find` and `BustleGoalDef.fail_cooldown_minutes`.
- Action sequences (`addons/bustle/core/brain/actions/`): `BustleActionStep` (action, params, on fail RETRY/SKIP/ABORT, `max_retries` after the first attempt), `BustleActionSequence`, `BustleActionContext`, `BustleActionHandler` and `BustleSequenceRunner`. The runner does at most one handler tick and one start per tick, cleans up an unfinished attempt exactly once, interrupts and resumes (restarting the step), and saves and restores a step mid-way. Built-in `wait` and `idle` actions run for game minutes.
- `BustleBrain`, `BustleSenses` and `BustleIntent`: a headless brain whose `tick(delta, senses)` scores, chooses with hysteresis, runs the chosen goal's sequence (`BustleGoalDef.sequence`, with the chosen option on `BustleActionContext.option_id`) and returns a typed intent with its reasons and the step's output. A failed sequence cools its goal down. The generator is seeded once from a fixed 64-bit FNV-1a of the world seed and agent id (`seed_for`), and `export_state`/`import_state` save the generator, keeper, runner and running goal so a run continues identically; a state that doesn't fit is refused without half-restoring.
- The ports, each with a standalone default so Bustle runs with no host: `BustleSocialPort` (neutral opinions; deeds known first-hand by the actor and named witnesses, shared one hop), `BustleRolesPort` with `BustleRoleTable`, `BustleWorldPort` (one area, no bodies), `BustleClockPort` (its own minutes, 1440 a day), `BustleCombatPort` (resolves harmlessly), `BustleTradePort` (in-memory balances that never create or lose money), `BustleWorkPort`, `BustleSkillSet`, `BustleLifeStagePort`, `BustleHealthPort`, `BustleEnvironmentPort` and `BustleDirectorPort`. `BustlePorts` holds one of each, `BustleDispositionPort` included (unchanged).
- `BustleSociety`, `BustleNpcState` and `BustleImportReport` (`addons/bustle/society/`): the scene-independent registry of a population. Agents are added from registered archetypes (a goal library and scoring config), each with a brain, an area, a position and module data; bodies attach and detach without touching the state. `export_state` gives plain data with a schema version; `import_state` checks everything first and replaces the population all at once, returning a report and changing nothing when a payload is malformed, another schema version, or doesn't fit. `state_hash` is a SHA-256 of the canonical export. `set_port` replaces a port with one of the right kind.

## [0.2.2] - 2026-11-04

### Changed

- The Wyrd bridge now supports Wyrd 1.0.1. The test-only vendored Wyrd copy moved to v1.0.1. No API changes.

## [0.2.1] - 2026-11-03

### Fixed

- The version strings for the 0.2.0 release: `addons/bustle/VERSION`, `addons/bustle/plugin.cfg`, `BustleInfo.VERSION` and the Wyrd bridge's `VERSION` and `plugin.cfg` still said 0.1.0. They now say 0.2.1. No code changes.

## [0.2.0] - 2026-11-02

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
