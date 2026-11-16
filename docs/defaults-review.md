# Defaults review

Every default in the [configuration reference](config.md) was reviewed before 1.0, when defaults become part of the contract. This page records the verdict for each class and the proposals that need a decision. Nothing in the code changed in this review.

## How each default was checked

- **In range:** the default lies inside the field's range in [config.md](config.md).
- **Valid as a whole:** a fresh instance passes the class's own validation, where it has one, unless the class is a definition the host must fill in. Definitions (`...Def`, `BustleScheduleBlock`, `BustleRoomThought`, `BustleHealthEffect`, `BustleHealthThought`, `BustleEventDef`, `BustleEventEffect`) are invalid until their id and references are set; that's by design. `BustleLifeStageRules` is invalid until the host adds stages, also by design. The built-in content was checked too: the seven `BustleMentalConfig.states`, the five `BustleAmbitionConfig.templates` and `BustleHealthConfig.defaults()` are all valid.
- **Consistent:** settings that describe the same thing in two places agree. For example, opinion lines sit on the 0–100 opinion scale around the neutral 50, and slider lines sit on the 0–100 slider scale.
- **Neutral:** a default names no game, and its built-in vocabulary (needs, goals, activities, relationship kinds) is the generic one the docs use.

## Verdicts

Every default is **confirmed**: none needs a new value. The proposals below are about checks and documentation around the defaults, not about the values themselves.

| Class | Verdict | Reason |
| --- | --- | --- |
| Project settings | Confirmed | Crime, ambitions and mental states are on by default, so a population behaves fully out of the box; each switch exists for developers and tests, not players. Instant crime reports are off, so reports, telling the victim and gossip are carried by agents who walk there, which is the designed behaviour. |
| `BustleActionSequence`, `BustleActionStep` | Confirmed | An empty sequence succeeds at once. Abort on failure is the safe default; one retry applies only when a step opts into `RETRY`. |
| `BustleAffordanceDef` | Confirmed | One user at a time, a one-hour hold, free, and no use by others: the conservative choice for an owned thing. A host widens each per place. |
| `BustleAmbitionConfig` | Confirmed | The five templates are generic life goals and all are valid. A seven-day repeat cooldown stops the same ambition coming straight back. The courting line of 60 sits below romance's 70 on purpose: the ambition picks someone liked, and then works the opinion up to where courting starts. `never_boost` keeps ambitions from boosting harmful goals. |
| `BustleAmbitionDef`, `BustleWantDef`, `BustleFearDef` | Confirmed | Host definitions: empty until set. A want lasts 12 game hours with a 24-hour cooldown, and a fear lasts three days at a quarter of the score: short enough to fade, long enough to notice. |
| `BustleAspirationConfig` | Confirmed | One automatic want, a cap of 3, and a boost capped at 1.25, which keeps a want below an ambition's 1.3–2.0 boosts, as documented. Its `never_boost` matches the ambitions list. See proposal 1 (`auto_wants` against `want_cap`). |
| `BustleCareerDef`, `BustleCareerRank` | Confirmed | Weekly reviews, promotion at 0.75 and demotion at 0.35: a wide band, so an average week changes nothing. |
| `BustleConflictConfig` | Confirmed | Fighting needs above-average boldness and temper (60). Quarrel thresholds of 1.4 / 1.0 / 0.6 make calm agents hard to provoke, and a quarter-strength low-mood effect keeps mood secondary. The scuffle floor of 1 health is documented as a stopgap. See proposal 1. |
| `BustleConsideration`, `BustleGoalDef`, `BustleGoalLibrary` | Confirmed | A new goal sits in the lowest band (`IDLE`) with weight 1, no minimum and no commitment: inert until the host places it. |
| `BustleCrimeConfig` | Confirmed | Only `food` drives theft by default. That's the one need in the generic vocabulary every demo has, and a host with no `food` need simply gets no theft from it. The thresholds and weights make an honest agent much harder to tip than a greedy one. |
| `BustleDebugOverlay` | Confirmed | A label 2.2 m up clears a person-sized body. |
| `BustleDirectorRules`, `BustleEventDef`, `BustleEventEffect` | Confirmed | Three days of tension memory, tension bands of 0.3 to 0.7, no beat gap and no tension inputs: the director stays quiet until the host gives it inputs and events. |
| `BustleDispositionTable` | Confirmed | Everyone is neutral, symmetric, until the host says otherwise. |
| `BustleHealthConfig`, `BustleHealthEffect`, `BustleHealthThought` | Confirmed | Downed agents skip work and travel. See proposal 5 for an empty config against the built-in defaults. |
| `BustleInteractionDef` | Confirmed | Effects last three days, and compatibility and mood bend values by moderate shares (0.5 and 0.3) so neither decides alone. |
| `BustleLifeStageDef`, `BustleLifeStageRules` | Confirmed | 1440 minutes a day matches the clock port. A 360-day year is documented as an assumption only; Bustle has no calendar, and a host sets its own. |
| `BustleMemoryConfig` | Confirmed | 32 entries an agent. Half-lives of 6 hours (people), 3 days (items) and 30 days (places) match how fast each goes stale. Hearsay starts weaker than sight. |
| `BustleMentalConfig`, `BustleMentalStateDef` | Confirmed | Low states start below 30 and end at 40, so they don't flicker. High spirits and inspiration enter at 80 and 90 and exit 5 lower. "Disliked" means below the neutral 50. Lash-outs need someone within 30 m and stop after one insult per person. Catharsis is +20 for two days, stacking three times at half strength. See proposal 1 (the entry and exit pairs). |
| `BustleMoodConfig` | Confirmed | A 0–100 scale with a resting mood of 50. Mood rises faster (12/h) than it falls (8/h), so a good event outlasts a small slight. |
| `BustleNeedDef`, `BustleScheduleDay`, `BustleScheduleBlock`, `BustleRoleSchedules`, `BustleRoleTable`, `BustleTraitDef`, `BustleThoughtDef`, `BustlePassionDef`, `BustleSkillDef`, `BustleWorkType` | Confirmed | Host definitions: empty or zero until set. The numbers they do carry are documented starting points: a thought stacks once at half strength, a passion learns 1.5× faster, a skill has 20 levels at 100 XP each, and work gives 10 XP an hour. |
| `BustlePerceivable`, `BustlePerceiver`, `BustlePerceptionSystem` | Confirmed | Fully visible and silent until the host says otherwise; layer 1 for line of sight; running from the start. |
| `BustlePerceptionProfile` | Confirmed | 15 m sight, a 90° inner and 150° outer cone, suspicion at 0.3 and alert at 0.9, eight seconds of search, sensing ten times a second: a guard-like observer that doesn't spot someone instantly. See proposal 1 (`suspicious_at` against `alert_at`). |
| `BustleRelationshipRules` | Confirmed | Friends form at 75 and lapse below 55; rivals form at 25 and lapse above 45. That's symmetric around the neutral 50, with a 20-point gap so ties don't flicker, and three deeds within two weeks. |
| `BustleRomanceRules` | Confirmed | Valid as shipped. Courting starts at 70 and lasts down to 55; partnership comes at 80 after a week and lasts down to 60. Affairs are off. Jealousy needs the host to name its verbs, so it is off until then. |
| `BustleScheduleDef` | Confirmed | A seven-day week starting on weekday 0, with 15 minutes of grace for arriving late. |
| `BustleScoringConfig` | Confirmed | A 10% pick window gives variety without letting a weak option win. |
| `BustleSimRingConfig` | Confirmed | Full simulation within 60 m (plus 15 m of hysteresis), short dwell and away delays so rings don't thrash, thinking at 2 Hz / 1 Hz / hourly, and a week of catch-up. There's no body cap, as documented: the budget is the host's. See proposal 2. |
| `BustleStealthRules` | Confirmed | Crouching and stillness roughly halve visibility, and running raises it. Skill can take visibility down to half and noise down to 0.4. Visibility is clamped to 0.05–1.5, so no one is ever fully invisible. See proposal 1. |
| `BustleWitnessConfig` | Confirmed | Honest, pious and bold witnesses report; fear and liking the thief keep a witness quiet. With no kind weights, kin loyalty is the host's call. |

## Proposals awaiting a decision

None of these is coded. Proposals 1, 2 and 5 change observable behaviour; proposals 3 and 4 change only documentation.

1. **Check the configs that don't check themselves.** 15 classes have number fields marked *unchecked* in [config.md](config.md). In most of them a value outside its range is harmless, but a few pairs give silently wrong behaviour when they're out of order:
   - `BustlePerceptionProfile`: `suspicious_at` at or above `alert_at`;
   - `BustleMentalConfig`: `extreme_fraction` above `major_fraction`, or an exit line above its entry line;
   - `BustleStealthRules`: `min_visibility` above `max_visibility`;
   - `BustleRelationshipRules`: a release line on the wrong side of its forming line;
   - `BustleAspirationConfig`: `auto_wants` above `want_cap`.

   The proposal: add a `validate()` to each of those classes that warns once, per [errors.md](errors.md), and keep today's behaviour. The only visible change is the new warnings.
2. **`BustleSimRingConfig.offscreen_interval_game_minutes` at 0 or below.** Catch-up clamps it to 1 minute, but a live tick thinks every tick. The proposal: clamp both paths to 1. This only changes behaviour for a value that isn't valid.
3. **"Experimental default" wording.** About 15 doc comments call their numbers experimental defaults. Once these verdicts are accepted, drop that wording for 1.0. This is documentation only, but it regenerates `docs/api/`.
4. **Tunables that aren't exports.** A few runtime classes have public tuning variables that aren't `@export` and so aren't in this reference: passion settings on `BustleSkills`, performance weights on `BustleCareers`, the base appeal on `BustleJobBoard`, and `BustleCrimeWatch.instant`. The proposal: add them to the reference as a second section, with the same check.
5. **An empty `BustleHealthConfig`.** `BustleHealthBehaviour.new(null)` uses `BustleHealthConfig.defaults()`, which has four effects and four thoughts, but a new `BustleHealthConfig` resource starts empty and so has no effect. Options:
   - keep this, and document that a new resource starts empty;
   - make a new resource start with the defaults. This changes behaviour for a host that made an empty one on purpose.
