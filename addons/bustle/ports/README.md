# ports

The interfaces a host project implements to connect Bustle to its own world (places, time, relations). Bustle calls them; it never reaches into the host directly. Each has a safe standalone default, so Bustle runs with no host. `BustlePorts` holds one of each, starting with the defaults; a host replaces the ones it implements with its own subclass.

| Port | What | Standalone default |
| --- | --- | --- |
| `BustleSocialPort` | opinions, relationship kinds, deeds and who knows them | neutral opinion (50), no kinds; deeds kept in memory, known first-hand by the actor and named witnesses, shared one hop only |
| `BustleRolesPort` | who holds which role | a static table (`BustleRoleTable`), changed with `set_holder` |
| `BustleWorldPort` | areas, places, the player's area and position, paths, travel time, bodies | one area, places set with `set_place`, no travel time, no bodies (headless) |
| `BustleClockPort` | game minutes and the day | its own minute count; 1440 minutes a day |
| `BustleCombatPort` | fighting | resolves at once, harmlessly |
| `BustleTradePort` | money and buying | in-memory balances and a price list; never creates or loses money |
| `BustleDispositionPort` | how actors regard each other | a `BustleDispositionTable`, or neutral |
| `BustleWorkPort` | jobs | none |
| `BustleSkillSet` | skill levels | everyone equal (0) |
| `BustleLifeStagePort` | life stages | ageless |
| `BustleHealthPort` | injured, incapacitated | everyone healthy |
| `BustleEnvironmentPort` | rooms | none |
| `BustleDirectorPort` | event pacing | allows everything |
