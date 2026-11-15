# Module guide

The core (`addons/bustle/core/`) is always there: needs, the brain, affordances, schedules, personality, memory, conflict, crime, jobs and the social rings. Everything in `addons/bustle/modules/` is optional. Each module is off until a host switches it on, and the rest of the addon runs the same without it. The demos prove this with a module-toggle test that leaves each one out in turn, and all of them together. How the core's and each module's saves load across Bustle versions is in [saves.md](saves.md). How every public entry point answers bad input (refuse, warn once, or assert) is in [errors.md](errors.md).

| Module | What it adds | How a host switches it on | Without it | Guide |
| --- | --- | --- | --- | --- |
| `needs_mood/` | a mood from thoughts, and mental states | a `BustleMood` (and `BustleMentalState`) per agent | no thoughts or moods; needs still drive choices | `docs/mood.md` |
| `perception/` | who notices whom, by sight and sound | a `BustlePerceptionWorld` with an actor per agent | everyone awake nearby counts as noticed | `docs/perception.md` |
| `skills/` | skill levels, practice and passions | `BustleSkills` as the skills port | every skill reads as untrained | `docs/skills.md` |
| `careers/` | career tracks, ranks and reviews | `BustleCareers` over the schedule roster | schedules alone | `docs/careers.md` |
| `environment/` | room thoughts, indoors and outdoors | an environment port with rooms | no room effects | `docs/environment.md` |
| `aspirations/` | short-lived wants, fears and points | `BustleAspirations` per agent | no wants or fears | `docs/aspirations.md` |
| `ambitions/` | long-term ambitions that shape scores | `BustleAmbitions` and its score boost | no ambition boost | `docs/ambitions.md` |
| `romance/` | the courtship ladder, breakups and jealousy | `BustleRomance` over a social port (it needs social: with social off, romance stays off) | no courtship | `docs/romance.md` |
| `life_stages/` | ages, stages and their gates, birth and death | `BustleLifeStages` as each brain's gate | everyone ageless and ungated | `docs/life_stages.md` |
| `health/` | reactions to the host's health, and the tend job | `BustleHealthBehaviour` (and `BustleTendJob`) | everyone healthy | `docs/health.md` |
| `director/` | a storyteller that paces host events | `BustleDirector` with event definitions | no story events | `docs/director.md` |

## In the demos

Both demos switch modules on through the shared harness (`demo/harness/demo_harness.gd`). Each module either has its own `enable_*` call or, where the harness has no switch, is wired in an agent hook (`agent_hooks`: a call made for each agent just before its brain ticks). Each full session takes a list of modules, so a test can leave any of them out.

- **The house week:** `House.session()` in `demo/house/house.gd`, run for 7 days by `tests/demo/test_house_session.gd`. It switches on `needs_mood`, `social`, `jobs`, `aspirations`, `romance`, `life_stages` and `director`.
- **The colony's 15 days:** `Colony.session()` in `demo/colony/colony.gd`, run by `tests/demo/test_colony_session.gd`. It switches on all eleven optional modules, plus social and jobs.

Each test checks that every module leaves its own trace on the timeline, and that the run still holds with each module left out in turn and with all of them out. That is the module-toggle rule. `House.build()` and `Colony.build()` are unchanged and keep their own tests.

## Each module in the colony session

The trace is what the session logs on the timeline when the module is on.

- **`needs_mood`:** `enable_mood()` with need thoughts, plus thoughts for meals, sleep and work. Trace: `thought`, `state`.
- **social:** `enable_social()` with the built-in store, conversations and the comfort goal; two pairs of friends. Conversations start through comfort, so they need `needs_mood` too. Trace: `talk`.
- **`perception/`:** `enable_perception()` with an all-round profile. A hook logs the first time each settler notices each other one. Without it, everyone awake in the same area counts as noticed. Trace: `notice`.
- **jobs:** `enable_jobs()` with the demo work types and three errands posted at the start. Trace: `job`.
- **`skills/`:** a `BustleSkills` with farming, set as the skills port. A hook gives farming practice for each step at the field and logs each new level. Trace: `skill`.
- **`careers/`:** a farming career for settler A, who holds the farmer role. It reads attendance from the harness's own schedules through a small roster subclass, and a hook updates it each step. A due promotion is granted. Trace: `career` (each review).
- **`environment/`:** an environment port where home is a room (indoors) and the field isn't (outdoors). A hook moves settlers between them and logs each change. Trace: `room`.
- **`aspirations/`:** `enable_aspirations()` with the demo wants and fears. Trace: `want`.
- **`ambitions/`:** settler A is pinned to the ambition to be promoted, which the career can complete. Trace: `ambition`.
- **`romance/`:** `enable_romance()` over the social store; settlers C and D court. It needs social: with social off, romance stays off. Trace: `romance`.
- **`life_stages/`:** `enable_life_stages()` with the demo child, adult and elder table. The child never works the field. Trace: `stage`.
- **`health/`:** a demo health port where settler C is ill from day 5 to day 8. `BustleHealthBehaviour` adds its thoughts and inputs, and gates every brain. Trace: `health`.
- **`director/`:** `enable_director()` with the small neutral story deck, beside the fixed cold snap. Trace: `director`, `effect`.

`ambitions` and `careers` are listed separately: with careers off, the ambition still starts but has no promotion to complete it.
