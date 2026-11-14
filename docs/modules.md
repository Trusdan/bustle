# Module guide

The core (`addons/bustle/core/`) is always there: needs, the brain, affordances, schedules, personality, memory, conflict, crime, jobs and the social rings. Everything in `addons/bustle/modules/` is optional. Each module is off until a host switches it on, and the rest of the addon runs the same without it. The demos prove this with a module-toggle test that leaves each one out in turn, and all of them together.

| Module | What it adds | How a host switches it on | Without it | Guide |
| --- | --- | --- | --- | --- |
| `needs_mood/` | a mood from thoughts, and mental states | a `BustleMood` (and `BustleMentalState`) per agent | no thoughts or moods; needs still drive choices | `docs/mood.md` |
| `perception/` | who notices whom, by sight and sound | a `BustlePerceptionWorld` with an actor per agent | everyone awake nearby counts as noticed | `docs/perception.md` |
| `skills/` | skill levels, practice and passions | `BustleSkills` as the skills port | every skill reads as untrained | `docs/skills.md` |
| `careers/` | career tracks, ranks and reviews | `BustleCareers` over the schedule roster | schedules alone | `docs/careers.md` |
| `environment/` | room thoughts, indoors and outdoors | an environment port with rooms | no room effects | `docs/environment.md` |
| `aspirations/` | short-lived wants, fears and points | `BustleAspirations` per agent | no wants or fears | `docs/aspirations.md` |
| `ambitions/` | long-term ambitions that shape scores | `BustleAmbitions` and its score boost | no ambition boost | `docs/ambitions.md` |
| `romance/` | the courtship ladder, breakups and jealousy | `BustleRomance` over a social port | no courtship | `docs/romance.md` |
| `life_stages/` | ages, stages and their gates, birth and death | `BustleLifeStages` as each brain's gate | everyone ageless and ungated | `docs/life_stages.md` |
| `health/` | reactions to the host's health, and the tend job | `BustleHealthBehaviour` (and `BustleTendJob`) | everyone healthy | `docs/health.md` |
| `director/` | a storyteller that paces host events | `BustleDirector` with event definitions | no story events | `docs/director.md` |

## In the demos

The house demo's full session (`House.session()` in `demo/house/house.gd`) switches on these modules through the shared harness:

- `needs_mood`
- `social` (the built-in social store and conversations)
- `jobs` (the core job board)
- `aspirations`
- `romance`
- `life_stages`
- `director`

`tests/demo/test_house_session.gd` runs it for a week. Each module leaves its own trace on the timeline, and the week still runs with each module left out in turn.

The colony demo covers the rest: perception and environment, and later skills, careers and health.

This guide is a first page. Fuller notes on wiring each module into a demo come with the colony session.
