# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Wants and fears with the demo data: wants are taken from causes and state, fulfilled with their
## thought or expired on time (across a save too); fears form from their event and lower the scores
## of what they avoid. Nothing is random.

const DIR := "res://demo/aspirations/%s.tres"
const HOUR := 60

var _config: BustleAspirationConfig
var _asp: BustleAspirations


func _person(sliders: Dictionary) -> BustlePersonality:
	var personality := BustlePersonality.new()
	for slider: StringName in sliders:
		personality.set_slider(slider, sliders[slider])
	return personality


func _build() -> void:
	_config = BustleAspirationConfig.new()
	_config.wants = [load(DIR % "share_a_meal"), load(DIR % "tidy_up")] as Array[BustleWantDef]
	_config.fears = [load(DIR % "fear_of_fire")] as Array[BustleFearDef]
	_asp = BustleAspirations.new(&"baker", _config)


func before_each() -> void:
	_build()


func test_the_automatic_want_follows_personality() -> void:
	_asp.update(0, _person({&"sociability": 90.0}))
	assert_eq(_asp.wants().map(func(row: Dictionary) -> String: return row["id"]), ["share_a_meal"])
	assert_eq(_asp.wants()[0]["source"], "auto")
	assert_eq(_asp.wants()[0]["expires"], 12 * HOUR)
	_build()
	_asp.update(0, _person({&"diligence": 90.0}))
	assert_true(_asp.has_want(&"tidy_up"))
	assert_false(_asp.has_want(&"share_a_meal"), "one automatic slot")
	_build()
	_asp.update(0, null)
	assert_true(_asp.has_want(&"share_a_meal"), "equal scores go to the lower id")


func test_the_host_posts_wants_up_to_the_cap() -> void:
	var extra := BustleWantDef.new()
	extra.id = &"rest_well"
	extra.auto = false
	extra.done_fact = &"rested"
	_config.wants.append(extra)
	var other := BustleWantDef.new()
	other.id = &"visit_market"
	other.done_fact = &"visited"
	other.requires = [&"market_open"] as Array[StringName]
	_config.wants.append(other)
	_asp.update(0, _person({&"sociability": 90.0}))
	assert_true(_asp.post_want(&"rest_well", 0), "never automatic, but postable")
	assert_true(_asp.post_want(&"tidy_up", 0))
	assert_false(_asp.post_want(&"visit_market", 0), "the cap of 3")
	assert_false(_asp.post_want(&"tidy_up", 0), "already active")
	assert_false(_asp.post_want(&"nothing", 0))
	assert_eq(_asp.wants().size(), 3)


func test_requires_and_cooldown_gate_the_automatic_slot() -> void:
	var market := BustleWantDef.new()
	market.id = &"visit_market"
	market.weights = {&"curiosity": 1.0}
	market.done_fact = &"visited"
	market.requires = [&"market_open"] as Array[StringName]
	market.cooldown_hours = 6.0
	_config.wants = [market]
	var curious := _person({&"curiosity": 90.0})
	_asp.update(0, curious)
	assert_true(_asp.wants().is_empty(), "the market isn't open")
	_asp.update(HOUR, curious, {"market_open": true})
	_asp.update(2 * HOUR, curious, {"market_open": true, "visited": true})
	assert_false(_asp.has_want(&"visit_market"), "fulfilled, and still done")
	_asp.update(3 * HOUR, curious, {"market_open": true})
	assert_false(_asp.has_want(&"visit_market"), "cooling down")
	_asp.update(8 * HOUR, curious, {"market_open": true})
	assert_true(_asp.has_want(&"visit_market"), "six hours after it ended")


# Acceptance (1): a fulfilled want adds its satisfaction thought.
func test_a_fulfilled_want_adds_its_thought() -> void:
	var mood := BustleMood.new()
	watch_signals(_asp)
	_asp.update(0, _person({&"sociability": 90.0}), {}, [], mood)
	assert_signal_emitted(_asp, "want_added")
	_asp.update(2 * HOUR, null, {"ate_with_company": true}, [], mood)
	assert_eq(mood.count(&"want_met"), 1)
	assert_eq(mood.reasons()[0]["reason"]["want"], "share_a_meal")
	assert_signal_emitted(_asp, "want_fulfilled")
	assert_false(_asp.has_want(&"share_a_meal"))
	_asp.update(3 * HOUR, null, {"ate_with_company": true}, [], mood)
	assert_eq(mood.count(&"want_met"), 1, "once")
	assert_true(_asp.has_want(&"tidy_up"), "the automatic slot refilled")
	assert_true(_asp.fulfill(&"tidy_up", 4 * HOUR, mood), "the host can say so too")
	assert_signal_emit_count(_asp, "want_fulfilled", 2)
	assert_eq(mood.count(&"want_met"), 1, "the shared thought is refreshed, not stacked (its stack limit)")
	assert_false(_asp.fulfill(&"tidy_up", 5 * HOUR, mood), "not active any more")


func test_without_a_mood_fulfilling_still_signals() -> void:
	_asp.post_want(&"tidy_up", 0)
	watch_signals(_asp)
	_asp.update(HOUR, null, {"tidied": true})
	assert_signal_emitted(_asp, "want_fulfilled")
	assert_push_error_count(0)


# Acceptance (3): wants expire on time.
func test_a_want_expires_on_time_with_no_thought() -> void:
	var mood := BustleMood.new()
	_asp.post_want(&"tidy_up", 30)
	watch_signals(_asp)
	_asp.update(30 + 8 * HOUR - 1, null, {}, [], mood)
	assert_true(_asp.has_want(&"tidy_up"), "a minute to go")
	_asp.update(30 + 8 * HOUR, null, {}, [], mood)
	assert_false(_asp.has_want(&"tidy_up"))
	assert_signal_emitted(_asp, "want_expired")
	assert_signal_not_emitted(_asp, "want_fulfilled")
	assert_eq(mood.count(), 0)


func test_a_want_expires_on_time_across_a_save() -> void:
	_asp.post_want(&"tidy_up", 0)
	_asp.update(HOUR, null)
	var saved: Variant = JSON.parse_string(JSON.stringify(_asp.export_state()))
	_build()
	assert_true(_asp.import_state(saved))
	var tidy: Array = _asp.wants().filter(func(row: Dictionary) -> bool: return row["id"] == "tidy_up")
	assert_eq(tidy[0]["expires"], 8 * HOUR)
	watch_signals(_asp)
	_asp.update(8 * HOUR - 1, null)
	assert_true(_asp.has_want(&"tidy_up"))
	_asp.update(8 * HOUR, null)
	assert_false(_asp.has_want(&"tidy_up"), "expires at the saved minute")
	assert_signal_emitted_with_parameters(_asp, "want_expired",
			[&"baker", &"tidy_up", {"id": "tidy_up", "since": 0, "expires": 8 * HOUR, "source": "posted"}])


# Acceptance (2): a fear forms from its event and biases avoidance.
func test_a_fear_forms_from_its_event() -> void:
	var mood := BustleMood.new()
	watch_signals(_asp)
	_asp.update(0, null, {}, [&"rain"], mood)
	assert_false(_asp.has_fear(&"fear_of_fire"), "not its trigger")
	assert_eq(_asp.avoidance(&"cook", &"stove"), 1.0)
	_asp.update(HOUR, null, {"fire_source": "stove"}, [&"fire"], mood)
	assert_true(_asp.has_fear(&"fear_of_fire"))
	assert_signal_emitted(_asp, "fear_formed")
	assert_eq(mood.count(&"frightened"), 1)
	assert_eq(_asp.fears()[0], {"id": "fear_of_fire", "since": HOUR, "until": HOUR + 72 * HOUR, "target": "stove"})
	assert_almost_eq(_asp.avoidance(&"cook"), 0.2, 1e-9, "the goal it avoids")
	assert_almost_eq(_asp.avoidance(&"warm_up", &"stove"), 0.2, 1e-9, "the option named when it formed")
	assert_almost_eq(_asp.avoidance(&"cook", &"stove"), 0.2, 1e-9, "once per fear")
	assert_eq(_asp.avoidance(&"rest", &"bed"), 1.0, "everything else untouched")


func test_a_fear_steers_the_brain_away() -> void:
	var library := BustleGoalLibrary.new()
	for pair: Array in [[&"cook", 1.0], [&"snack", 0.5]]:
		var goal := BustleGoalDef.new()
		goal.id = pair[0]
		goal.band = BustleBands.PERSONAL
		goal.base_weight = pair[1]
		library.goals.append(goal)
	var picks: Array[StringName] = []
	for afraid: bool in [false, true]:
		_build()
		if afraid:
			_asp.update(0, null, {}, [&"fire"])
		var brain := BustleBrain.new(&"baker", library, BustleScoringConfig.new(), 1)
		brain.score_boost = _asp.avoidance
		picks.append(brain.tick(60.0, BustleSenses.new()).goal_id)
	assert_eq(picks, [&"cook", &"snack"] as Array[StringName], "1.0 × 0.2 falls below 0.5")


func test_a_fear_ends_on_time_or_when_cleared_and_renews() -> void:
	watch_signals(_asp)
	_asp.update(0, null, {}, [&"fire"])
	_asp.update(48 * HOUR, null, {}, [&"fire"])
	assert_eq(_asp.fears()[0]["until"], 120 * HOUR, "renewed by its trigger")
	_asp.update(120 * HOUR - 1, null)
	assert_true(_asp.has_fear(&"fear_of_fire"))
	_asp.update(120 * HOUR, null)
	assert_false(_asp.has_fear(&"fear_of_fire"))
	assert_signal_emitted_with_parameters(_asp, "fear_ended", [&"baker", &"fear_of_fire", &"expired"])
	_asp.update(121 * HOUR, null, {}, [&"fire"])
	_asp.update(122 * HOUR, null, {"fire_safe": true})
	assert_false(_asp.has_fear(&"fear_of_fire"), "cleared by its fact")
	assert_eq(_asp.avoidance(&"cook"), 1.0)


func test_save_round_trip_and_refusals() -> void:
	_asp.update(0, _person({&"sociability": 90.0}), {"fire_source": "stove"}, [&"fire"])
	_asp.post_want(&"tidy_up", 30)
	_asp.update(HOUR, null, {"tidied": true})
	var saved: Variant = JSON.parse_string(JSON.stringify(_asp.export_state()))
	var before := _asp.export_state()
	_build()
	assert_true(_asp.import_state(saved))
	assert_eq(_asp.export_state(), before)
	assert_almost_eq(_asp.avoidance(&"warm_up", &"stove"), 0.2, 1e-9, "the fear's target survives")
	var bad: Array = [null, {}, {"wants": [{"id": "nap"}], "fears": [], "ended": {}},
		{"wants": [{"id": "tidy_up", "since": 0, "expires": "soon", "source": "auto"}], "fears": [], "ended": {}},
		{"wants": [{"id": "tidy_up", "since": 0, "expires": 5, "source": "gift"}], "fears": [], "ended": {}},
		{"wants": [], "fears": [{"id": "fear_of_dark", "since": 0, "until": -1, "target": ""}], "ended": {}},
		{"wants": [], "fears": [], "ended": {"nap": 3}}]
	for row: Variant in bad:
		assert_false(_asp.import_state(row), str(row))
		assert_eq(_asp.export_state(), before, str(row))


func test_same_causes_give_the_same_wants_and_fears() -> void:
	var runs: Array = []
	for run: int in 2:
		_build()
		var person := _person({&"sociability": 70.0, &"diligence": 75.0})
		for hour: int in 30:
			var events: Array[StringName] = []
			if hour % 11 == 3:
				events.append(&"fire")
			_asp.update(hour * HOUR, person, {"tidied": hour % 9 == 5, "fire_source": "hearth"}, events)
		runs.append(_asp.export_state())
	assert_eq(runs[0], runs[1])


func test_invalid_defs_are_never_used() -> void:
	var fear := BustleFearDef.new()
	fear.id = &"fear_of_heights"
	fear.trigger = &"fall"
	assert_false(fear.is_valid(), "nothing to avoid")
	fear.avoid_goals = [&"climb"] as Array[StringName]
	fear.avoid_mult = 1.5
	assert_false(fear.is_valid())
	fear.avoid_mult = 0.0
	fear.duration_hours = 0.0
	assert_false(fear.is_valid(), "no way to end")
	fear.cleared_fact = &"ground_safe"
	assert_true(fear.is_valid())
	var want := BustleWantDef.new()
	want.id = &"nap"
	want.duration_hours = 0.0
	assert_false(want.is_valid())
	_config.wants.append(want)
	assert_false(_asp.post_want(&"nap", 0))
