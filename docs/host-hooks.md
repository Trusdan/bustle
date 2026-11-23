# Wiring the 1.1 hooks

Short host snippets for what 1.1 added, one section per hook. Each snippet is a few functions a host can lift into its own code, in the style of the [walkthrough](host-walkthrough.md). Every one is opt-in: a host that doesn't call it runs as it did on 1.0. All of these hooks are `@experimental` ([public-api/PUBLIC_API.md](public-api/PUBLIC_API.md)), so they may still change in a minor release. Each section links to its module's guide for the full rules.

`tests/docs/test_host_hooks.gd` compiles every snippet on this page in Godot 4.7.2 and calls it against real objects, so the page stays true.

## Career reviews by period, and a window reset after a break

A rank can review differently in a period the host names, such as a busy season ([careers.md](careers.md#periods)). Days off pause the review window by default. After a long leave the host can start a fresh window instead ([careers.md](careers.md#after-a-break)).

```gdscript
## A rank that reviews every 2 working days, and promotes only above 0.9, in a busy season.
func add_busy_season(rank: BustleCareerRank) -> void:
	var busy := BustleCareerPeriod.new()
	busy.review_days = 2
	busy.promote_if = 0.9
	rank.periods = {&"busy_season": busy}


## The day's career update, judged by the season's rules. An empty season uses the rank's own, like
## update(). A window keeps the period it started in until it is reviewed: window_period() names it.
func end_of_day(careers: BustleCareers, id: StringName, now: int, season: StringName) -> Array[Dictionary]:
	return careers.update_in_period(id, now, season)


## Back from a long leave: close the days up to the break, then judge only the days from here on.
## The rank, wage and start are kept, and nothing is reviewed.
func back_from_leave(careers: BustleCareers, id: StringName, now: int) -> bool:
	careers.update(id, now)
	return careers.reset_window(id)
```

## Stolen goods after they change hands

`stolen_goods_of(agent)` follows goods only while the thief holds them. These two follow them after they are sold, given or traded on ([crime.md](crime.md#after-a-theft-bustlecrimewatch)). They only read; what the host does with the answer is its own.

```gdscript
## True when [param item] comes from a deed nobody has found yet, whoever holds it now.
func is_from_an_open_deed(watch: BustleCrimeWatch, item: StringName) -> bool:
	return not watch.deed_of_item(item).is_empty()


## The stolen items [param agent] holds now, whoever stole them.
func stolen_items_on(watch: BustleCrimeWatch, agent: StringName) -> Array[StringName]:
	var items: Array[StringName] = []
	for record: Dictionary in watch.stolen_goods_held_by(agent):
		items.append(StringName(record["item"]))
	return items
```

## A cap on aspiration points

Points grow without limit by default. A cap stops earning at it, and `points_changed` and `on_points` report the amount actually added ([aspirations.md](aspirations.md#an-optional-cap)).

```gdscript
## A copy of [param config] whose agents earn no more than [param cap] points. A negative cap (the
## default, -1) is no cap. Points above the cap, from a save or a lowered cap, are kept.
func with_point_cap(config: BustleAspirationConfig, cap: int) -> BustleAspirationConfig:
	var capped := config.duplicate() as BustleAspirationConfig
	capped.max_points = cap
	return capped
```

## Work that needs a minimum capacity

A work type can name minimum health capacities. An agent below one isn't offered the work and can't claim it, and a claim it holds is released once it drops below ([health.md](health.md#work-that-needs-a-minimum-capacity), [work.md](work.md)).

```gdscript
## Hauling needs moving at 0.5 and manipulation at 0.3 or more. No minimums is the default.
func make_haul_work() -> BustleWorkType:
	var haul := BustleWorkType.new()
	haul.id = &"haul"
	haul.minutes = 60
	haul.min_capacities = {&"moving": 0.5, &"manipulation": 0.3}
	return haul


## Why [param agent] can't claim [param job], for example &"capacity:moving"; empty when it can.
func why_not(board: BustleJobBoard, agent: StringName, job: StringName) -> StringName:
	return board.refusal(BustleJobSeeker.new(agent), job)


## After the health port changes, let go of claims held below a minimum. settle() and work() do
## this too; the board's changed signal reports each one as released.
func release_the_unfit(board: BustleJobBoard) -> Array[StringName]:
	return board.release_unfit()
```

## Fetching a healer

A bystander who sees a downed or urgent patient, with no healer near, goes for the nearest healer by the same movement rule as fetching help in a fight (`BustleFetchHelpAction.approach()`). Then the tend job does the rest ([health.md](health.md#fetching-a-healer)).

```gdscript
## Gives [param brain] the fetch-healer goal and its action. Healers are the holders of the healer
## role; [param where] is func(id) -> Vector3, or null when a position is unknown.
func add_fetch_healer(health: BustleHealthBehaviour, library: BustleGoalLibrary, brain: BustleBrain,
		where: Callable) -> BustleFetchHealer:
	var fetch := BustleFetchHealer.new(health, [&"healer"] as Array[StringName])
	fetch.where = where
	library.goals.append(BustleFetchHealer.goal_def())
	brain.runner.register(BustleFetchHealer.ACTION, BustleFetchHealerAction.new(fetch))
	return fetch


## Each tick: start an errand if [param bystander] sees an urgent patient, set the goal's inputs,
## and tick the brain. While the errand runs, the intent asks the host to move the bystander
## (has_move_to, move_to); the host moves it, and on arrival the healer is summoned.
func tick_bystander(fetch: BustleFetchHealer, brain: BustleBrain, patient: StringName, now: int) -> BustleIntent:
	fetch.notice(brain.agent_id, patient, now)
	var senses := BustleSenses.new()
	senses.now_minutes = now
	fetch.fill_inputs(brain.agent_id, senses.inputs)
	return brain.tick(1.0, senses)
```

## Seeking care and resting when sick

Two more opt-in health goals. An agent who needs care goes to a healer or a care place, and one who is ill rests instead of working until the port says it is better ([health.md](health.md#the-seek-care-goal), [health.md](health.md#the-rest-when-sick-goal)). With `rest.seek_care` set, seeking care comes first.

```gdscript
## Gives [param brain] both goals and their actions, with seeking care first.
func add_care_goals(health: BustleHealthBehaviour, library: BustleGoalLibrary, brain: BustleBrain) -> BustleRestSick:
	var seek := BustleSeekCare.new(health, [&"healer"] as Array[StringName])
	var rest := BustleRestSick.new(health, [&"sick"] as Array[StringName])
	rest.seek_care = seek
	library.goals.append(BustleSeekCare.goal_def())
	library.goals.append(BustleRestSick.goal_def())
	brain.runner.register(BustleSeekCare.ACTION, BustleSeekCareAction.new(seek))
	brain.runner.register(BustleRestSick.ACTION, BustleRestSickAction.new(rest))
	return rest


## Each tick, before the brain thinks: the goals' inputs.
func fill_care_inputs(rest: BustleRestSick, id: StringName, senses: BustleSenses) -> void:
	rest.seek_care.fill_inputs(id, senses.inputs)
	rest.fill_inputs(id, senses.inputs)
```

## Also in 1.1

- **Frozen:** `validate()` on `BustleAspirationConfig`, `BustleMentalConfig`, `BustlePerceptionProfile`, `BustleRelationshipRules` and `BustleStealthRules`, and `BustleCrimeWatch.prune()`, are now frozen public API. Calling them is unchanged.
- **Demo only:** a small room set (`demo/environment/demo_rooms.gd`) and an opt-in demo of these hooks (`House.NEW_HOOKS`, in `demo/hooks/demo_hooks.gd`); see [environment.md](environment.md) and `demo/README.md`.
- **Releases:** an example-project zip beside the addon zips ([RELEASE.md](RELEASE.md)).
