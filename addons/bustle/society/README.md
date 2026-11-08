# society

The population and how its members relate to each other.

- `BustleSociety`: the registry of a population, independent of any scene.
  - **Archetypes:** register each one once (a goal library and scoring config). Add agents from them.
  - **Agents and bodies:** each agent's `BustleNpcState` holds its brain, area, position and module data. Bodies attach and detach without touching the state.
  - **Ports:** start as defaults; `set_port` replaces one with a port of the right kind.
  - **Saving:** `export_state` gives plain data with a schema version. `import_state` is all or nothing and returns a `BustleImportReport`. Only the current schema is accepted (no migrations yet). Saves store archetype ids, never resource paths. 64-bit ints (seeds, generator states) must stay exact in whatever format a host writes.
- `BustleDispositionTable`: who regards whom as hostile, neutral or friendly, as data.
