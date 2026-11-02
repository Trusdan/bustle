# Changelog

All notable changes to Bustle. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Before 1.0, any minor version may change the API. Every public class is marked `@experimental` until then.

## [0.1.0] - 2026-11-02

The project scaffold.

### Added

- The addon layout: `addons/bustle/` with `core/`, `society/`, `ports/`, `debug/` and `modules/`, and `BustleInfo` (the version and the folders).
- The optional Wyrd bridge's shell, `addons/bustle_wyrd/` (`BustleWyrdBridge`), pinned to Wyrd 1.0.0, with a test-only copy of Wyrd 1.0.0 in `addons/wyrd/`.
- Vendored GUT 9.7.1, the tests, a demo skeleton and the generated API docs.
- CI: Ubuntu, Windows, the core alone, the editor load, the API docs, the Wyrd pin and the content-hygiene check.
