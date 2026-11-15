# Errors and bad input

How Bustle answers a host that passes bad input or misconfigures it: one consistent signal, never silence, and never a flooded log. The first part is the policy every public entry point follows. The second is the audit of the frozen public API ([public-api/PUBLIC_API.md](public-api/PUBLIC_API.md)) against it: what each entry point did, and what it does now.

## The policy

Every problem gets exactly one of three answers.

### 1. Refuse, with a reason the host can read

For a call that can fail during play, and that the host is expected to check: an import, a reservation, a payment, adding a definition, adding an agent.

- The call returns its refusal: `false`, `null`, an empty result, or a `BustleImportReport` whose `errors` say why. Its doc comment says when it refuses.
- **A refused call changes nothing.** Validate everything first, then change state. A call that has started changing state must not refuse halfway. When validation needs a dry run, build into a local copy and swap it in at the end, as `BustleSociety.import_state()` does.
- No log line: a refusal is an ordinary outcome, like a full well. The host decides whether it's a mistake.

### 2. Warn once

For a host mistake the call can't report through its return value: a setup problem, such as an invalid config or definition, a hook that returns the wrong type, a non-finite number passed to a per-tick call, or wiring that's missing (no society, no port).

- `push_warning()` once per problem per run, through the shared limiter. The key is the class and the problem, plus a definition id when that's what's wrong, such as `BustleSchedule.invalid_block`. **It is never an agent id or a minute**, so the number of keys stays bounded and a problem in a per-tick path warns once, not every tick.
- The message starts with the class, names the problem and says what Bustle does instead: `BustleHealthBehaviour: the config is invalid (pain_scale isn't finite); health has no effect until it's fixed`.
- The call then does what it did before the warning existed (skips the definition, treats the hook as unset, does nothing). A warning never changes state or results.
- A hook that returns the wrong type, including `null`, is treated **as if it were unset**, whatever kind of hook it is. That holds for gates too: a broken `BustleBrain.gate`, `BustleConversation.accepts`, `BustleCareers.review_hook` or `BustleRomance.ratings_policy` lets everything through, as it does with no hook. Where a hook only overrides a fallback of Bustle's own (an affordance's access or cost, line of sight, compatibility), the fallback is used.
- Warnings print in every build, release included: a misconfigured shipped game is worth one line per problem.
- Tests read whether a key has warned; they don't depend on the log.

### 3. Assert, in debug builds only

For Bustle's own invariants: a state its own code should never reach. `assert()` is stripped from release builds, so it is never the answer to host input; host input is refused or warned about.

### Never

- **Never ignore bad input silently.** A guard that returns early on invalid input either refuses (and its doc comment says so) or warns once.
- **Never warn every tick,** or once per agent.
- **Never `push_error()` for host input.** Errors are for Bustle's own bugs. Host mistakes are refusals or warnings.
- Never mutate on a refused call (see 1).

Writing new code: check the input at the public entry point, pick the one answer that fits, document it in the `##` comment ("False when …", "Warns once when …"), and add a test for the refused or warned path.

## The audit

The frozen public API was checked against the policy at `main` `28aef7d6`. Paths are under `addons/`; line numbers are at that commit. Each group below was one decision, and every group is now done.

### A. Already fine

- **Imports** refuse through their return value or `BustleImportReport`, and a newer save is refused changing nothing (`BustleSaveFormat`). The exceptions are in groups D and E.
- **Adding definitions** refuses invalid ones with `false`, and the doc comments say so: `BustleAffordanceSet.add`, `BustleJobBoard.add_type`, `BustleCareers.add_def`, `BustleSkills.add_def` and `add_passion_def`, `BustleRoomThoughts.add_rule`, `BustleMood.add_thought` and `set_held`, `BustleAspirations.post_want`, `BustleDirector.add_event`, `BustleSociety.lock`.
- **Setters with numbers** refuse a non-finite value with `false`, for example `BustleNeedSet.set_pressure`.
- **Constructors that are handed definitions** (`BustleSkills`, `BustleCareers`, `BustleJobBoard`, `BustleRoomThoughts`) warn about each one they skip. That's once per call, at setup, so it fits the policy as it stands.

### B. Silently ignored at run time: done, warn once with no other change

The call keeps doing what it did; it also warns once.

| Entry point | Before (now also warns once) | Where |
| --- | --- | --- |
| `BustleHealthBehaviour` `apply`, `chosen`, `sync`, `recovered` with an invalid `BustleHealthConfig` | does nothing, or nothing chosen, every tick (`illness_began` refuses with `false` and is fine) | `bustle/modules/health/health_behaviour.gd:72, 94, 121, 178` |
| `BustleHealthBehaviour.fill_inputs` with no health port | does nothing | `health_behaviour.gd:136` |
| `BustleHealthBehaviour.recovered`, `BustleSkills.apply` with a mood lacking `set_held` | does nothing | `health_behaviour.gd:178`, `bustle/modules/skills/skills.gd:191` |
| `BustleDirector` `tension`, `eligible` and `update` with invalid `BustleDirectorRules` | 0, nothing eligible, no event | `bustle/modules/director/director.gd:81, 111` |
| `BustleLifeStages` with invalid rules (`error()` not empty) | every call does nothing | `bustle/modules/life_stages/life_stages.gd:88, 102, 124, 156, 348` |
| `BustleRomance` with invalid `BustleRomanceRules` | no romance updates | `bustle/modules/romance/romance.gd:125` |
| `BustleAffordance` `reserve`, `advertise`, `use` with an invalid definition | nothing, no ad | `bustle/core/affordances/affordance.gd:100, 118, 138` |
| `BustleSchedule` with an invalid block in the plan | the block is skipped, every query | `bustle/core/schedules/schedule.gd:214` |
| `BustleAspirations.choose` with an invalid want definition | skipped, every call | `bustle/modules/aspirations/aspirations.gd:107` |
| `BustleConversation` with an invalid interaction definition | skipped, every call | `bustle/society/conversation.gd:151` |
| `BustleSocialInteractions.interact` with an invalid definition | nothing | `bustle/society/social_interactions.gd:81` |
| `BustleNeedSet.advance`, `BustleLeisure.advance` with non-finite minutes | nothing | `bustle/core/needs/need_set.gd:82`, `bustle/core/needs/leisure.gd:76` |
| `BustleSimRings.tick` and `update` with no society | nothing | `bustle/core/rings/sim_rings.gd:126, 228` |
| `BustleCombatPort.engage` with an empty id or an agent engaging itself | nothing | `bustle/ports/combat_port.gd:25` |
| `BustleRolesPort.set_holder` with an empty role | nothing | `bustle/ports/roles_port.gd:42` |
| `BustleScheduleRoster.add_agent` with an empty id | nothing | `bustle/core/schedules/schedule_roster.gd:35` |
| `BustleSocialStore.set_kind` with an empty id or kind, or an agent and itself | nothing | `bustle/society/social_store.gd:115` |
| `BustleSocialStore.set_time` with a time earlier than its own | the clock stays | `social_store.gd:36` |
| `BustleWyrdRolesPort.set_holder` with no roles port | nothing | `bustle_wyrd/bustle_wyrd_roles_port.gd:60` |

### C. Hooks that return the wrong type: done, warn once and treat the hook as unset

A Callable hook's call (its `func(...) -> T` in the doc comment) promises a type. Before, 27 of the 53 frozen hooks had whatever came back coerced: `bool()`, `float()`, `int()`, `StringName()`. Tested on Godot 4.7.2:

- A hook that returns `null` (for example a lambda that forgets its `return`) or a type with no conversion stops the calling function with `SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor` (or `int`, `float`, `StringName`), at every call, which can be every tick.
- A String where a number is expected silently becomes `0.0`.

Now: the type is checked, the hook warns once (key `<Class>.<hook>.wrong_type`), and the call uses what it uses for an unset hook. A hook returning `null` warns once and never raises a script error, however often it is called. A bool hook accepts an int, a number hook an int or float, an int hook a whole float, a name hook a String. The check is one `typeof` comparison on the valid path.

| Hooks | Where |
| --- | --- |
| `BustleAffordance.access_hook`, `cost_hook` | `bustle/core/affordances/affordance.gd` |
| `BustleAmbitionTargets.is_gone`, `settlement_of`; `BustleAmbitions.is_locked` | `bustle/modules/ambitions/` |
| `BustleBrain.gate` | `bustle/core/brain/brain.gd` |
| `BustleCareers.review_hook` | `bustle/modules/careers/careers.gd` |
| `BustleComfort.low_state_of` | `bustle/society/comfort.gd` |
| `BustleConflict.cornered_of`, `group_of`, `lethal_reason_of` | `bustle/core/conflict/conflict.gd` |
| `BustleConversation.accepts` | `bustle/society/conversation.gd` |
| `BustleCrime.is_locked`, `is_observed` | `bustle/core/crime/crime.gd` |
| `BustleCrimeWatch.can_reach`, `can_travel`, `gossip_to`, `perceives`, `should_report` | `bustle/core/crime/crime_watch.gd` |
| `BustleMemoryFeed.area_of`, `clock` | `bustle/modules/perception/memory_feed.gd` |
| `BustleMentalBehaviour.indulgence_of`, `is_locked` | `bustle/modules/needs_mood/mental_behaviour.gd` |
| `BustleRomance.compatibility`, `confirm_hook`, `ratings_policy` | `bustle/modules/romance/romance.gd` |
| `BustleScoringConfig.expected_thought_gain` | called in `bustle/core/brain/utility_scorer.gd` |

Of the other 26:
- 14 check what comes back (`is BustleX`, `is Array`, `is Vector3`) and treat a mismatch as unset: the brain's `score_boost`, the `mood_of`, `personality_of`, `memory_of` and `position_of` hooks, `BustleCrime.needs_of` and `BustleTendJob.nearby`.
- 12 use the result as it comes: `BustleAspirations.on_points` (void), `BustleConversation.modifiers_of`, `BustleCrimeWatch.where`, `BustleDirectorEffects.agents`, `brain_of` and `tags_of`, `BustleMentalBehaviour.home_of` and `wander_to`, `BustlePerceptionWorld.line_of_sight`, `BustlePointLightProbe.occluded`, and `BustleSimRings.senses_provider` and `summary_hook`.

These 26 already treat a mismatch as unset or use the value as it is, so they are unchanged.

### D. Changed state before refusing: done, validate first and change nothing

| Entry point | Before | Where |
| --- | --- | --- |
| `BustleBrain.import_state` | Resets the brain, then refuses another agent, a running goal the library lacks, or a runner state that doesn't fit. Its doc comment says the brain is left "as freshly made". | `bustle/core/brain/brain.gd:252` |
| `BustleSequenceRunner.import_state` | Sets itself idle, takes the new sequence, then refuses a bad state or step. | `bustle/core/brain/actions/sequence_runner.gd:145` |

Now: both check everything first (the brain dry-runs the runner import), then reset and load, so a refused import leaves the brain or runner as it was. A host that relied on a refused import clearing the brain sees the old state kept.

### E. Imports that can't refuse: done, option A

`BustleAwareness.import_state()` and `BustleDetectionMeter.import_state()` return `void` and the signatures are frozen. They coerce bad values (an unknown awareness state becomes unaware, a malformed position becomes zero) and skip rows that aren't dictionaries. They now also warn once (`BustleDetectionMeter.bad_value`, `BustleAwareness.bad_row`) and keep importing as before.

### F. Messages that repeated: done

| Entry point | Before | Where |
| --- | --- | --- |
| `BustleModifierSet.set_source` | `push_error` on every refused call, which can be every tick | `bustle/core/modifier_set.gd:21` |
| `BustleSociety.register_archetype` and `add_agent` | `push_error` on every refused call | `bustle/society/society.gd:63, 89` |

Now: the refusal (`false` or `null`) stays and the message is a once-per-problem warning, per "never `push_error()` for host input". `register_archetype` returns nothing, so the warning is its only signal.

### G. Warnings in release builds: done

Warnings print in every build; there is no `OS.is_debug_build()` check.

## Tests

Each change has a test for its refused or warned path in `tests/errors/`, reading the limiter's state rather than the log. The limiter is an internal script with no `class_name` (`bustle/core/warn_once.gd`); tests call its `reset()` before each case. The perf benches were run against [perf.md](perf.md) with no regression.
