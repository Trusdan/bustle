# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Aspiration points, the host reward hook and the want boost.

const HOUR := 60

var _config: BustleAspirationConfig
var _asp: BustleAspirations


func _want(id: StringName, points: int, boosts: Dictionary = {}, option: StringName = &"") -> BustleWantDef:
	var def := BustleWantDef.new()
	def.id = id
	def.auto = false
	def.done_fact = StringName("done." + String(id))
	def.points = points
	for goal: StringName in boosts:
		def.boosts[goal] = boosts[goal]
	def.boost_option = option
	def.thought = load("res://demo/aspirations/want_met.tres")
	return def


func before_each() -> void:
	_config = BustleAspirationConfig.new()
	_config.wants = [_want(&"chat", 5, {&"converse": 1.2}), _want(&"feast", 8, {&"eat": 3.0, &"steal": 2.0}, &"table"),
		_want(&"walk", 0, {&"converse": 1.1})] as Array[BustleWantDef]
	_config.fears = [load("res://demo/aspirations/fear_of_fire.tres")] as Array[BustleFearDef]
	_asp = BustleAspirations.new(&"baker", _config)


# Acceptance (1): a fulfilled want adds its thought and its points.
func test_a_fulfilled_want_adds_its_thought_and_points() -> void:
	var mood := BustleMood.new()
	_asp.post_want(&"chat", 0)
	watch_signals(_asp)
	_asp.update(HOUR, null, {"done.chat": true}, [], mood)
	assert_eq(mood.count(&"want_met"), 1)
	assert_eq(_asp.points(), 5)
	assert_signal_emitted_with_parameters(_asp, "points_changed", [&"baker", 5, &"want:chat", 5])
	_asp.post_want(&"walk", HOUR)
	_asp.fulfill(&"walk", 2 * HOUR, mood)
	assert_eq(_asp.points(), 5, "a want worth 0 earns nothing")
	_asp.post_want(&"chat", 2 * HOUR)
	_asp.update(14 * HOUR, null, {}, [], mood)
	assert_eq(_asp.points(), 5, "an expired want earns nothing")


# Acceptance (2): the host's reward hook fires and can spend points.
func test_the_reward_hook_lets_a_host_spend_points() -> void:
	var rewards: Array = []
	var calls: Array = []
	var host := func(agent: StringName, amount: int, reason: StringName) -> void:
		calls.append([agent, amount, reason])
		while _asp.points() >= 10 and _asp.spend_points(10, &"reward"):
			rewards.append(agent)
	_asp.on_points = host
	_asp.post_want(&"chat", 0)
	_asp.post_want(&"feast", 0)
	_asp.update(HOUR, null, {"done.chat": true})
	assert_eq(calls, [[&"baker", 5, &"want:chat"]])
	assert_true(rewards.is_empty(), "5 is not enough")
	_asp.update(2 * HOUR, null, {"done.feast": true})
	assert_eq(calls.size(), 2, "once per award")
	assert_eq(rewards, [&"baker"], "13 points buy one reward")
	assert_eq(_asp.points(), 3)


func test_points_only_move_by_positive_amounts() -> void:
	watch_signals(_asp)
	assert_false(_asp.add_points(0, &"nothing"))
	assert_false(_asp.add_points(-3, &"nothing"))
	assert_true(_asp.add_points(4, &"host"), "a host may award points itself")
	assert_false(_asp.spend_points(5, &"too much"))
	assert_false(_asp.spend_points(0, &"nothing"))
	assert_true(_asp.spend_points(4, &"reward"))
	assert_signal_emitted_with_parameters(_asp, "points_changed", [&"baker", -4, &"reward", 0])
	assert_eq(_asp.points(), 0)


# Acceptance (3): the want boost follows the ambition rules, smaller.
func test_the_want_boost_is_small_and_never_boosts_banned_goals() -> void:
	assert_eq(_asp.boost(&"converse"), 1.0, "no active want")
	_asp.post_want(&"chat", 0)
	assert_almost_eq(_asp.boost(&"converse", &"smith"), 1.2, 1e-9)
	_asp.post_want(&"walk", 0)
	assert_almost_eq(_asp.boost(&"converse"), 1.2, 1e-9, "the largest, not the product")
	_asp.post_want(&"feast", 0)
	assert_almost_eq(_asp.boost(&"eat", &"table"), 1.25, 1e-9, "capped by max_want_boost")
	assert_eq(_asp.boost(&"eat", &"crate"), 1.0, "only its option")
	assert_eq(_asp.boost(&"steal", &"table"), 1.0, "never a never_boost goal")
	assert_eq(_asp.boost(&"rest"), 1.0)
	_asp.fulfill(&"chat", HOUR)
	_asp.fulfill(&"walk", HOUR)
	assert_eq(_asp.boost(&"converse"), 1.0, "gone with the want")
	_asp.update(2 * HOUR, null, {}, [&"fire"])
	assert_almost_eq(_asp.score(&"cook"), 0.2, 1e-9, "the boost times the fear's avoidance")
	assert_almost_eq(_asp.score(&"eat", &"table"), 1.25, 1e-9)


func test_the_want_boost_tips_a_close_choice_but_never_a_band() -> void:
	var library := BustleGoalLibrary.new()
	for row: Array in [[&"converse", 0.45, BustleBands.PERSONAL], [&"rest", 0.5, BustleBands.PERSONAL]]:
		var goal := BustleGoalDef.new()
		goal.id = row[0]
		goal.base_weight = row[1]
		goal.band = row[2]
		library.goals.append(goal)
	var scoring := BustleScoringConfig.new()
	scoring.pick_window = 0.0
	var picks: Array[StringName] = []
	for wanting: bool in [false, true]:
		before_each()
		if wanting:
			_asp.post_want(&"chat", 0)
		var brain := BustleBrain.new(&"baker", library, scoring, 1)
		brain.score_boost = _asp.score
		picks.append(brain.tick(60.0, BustleSenses.new()).goal_id)
	assert_eq(picks, [&"rest", &"converse"] as Array[StringName], "0.45 × 1.2 = 0.54 beats 0.5 (no pick window)")
	var duty := BustleGoalDef.new()
	duty.id = &"work"
	duty.base_weight = 0.1
	duty.band = BustleBands.DUTY
	library.goals.append(duty)
	var brain := BustleBrain.new(&"baker", library, scoring, 1)
	brain.score_boost = _asp.score
	assert_eq(brain.tick(60.0, BustleSenses.new()).goal_id, &"work", "a boosted personal goal stays below duty")


func test_a_boost_below_one_is_refused() -> void:
	var bad := _want(&"shy", 1, {&"converse": 0.5})
	assert_false(bad.is_valid())
	bad.boosts[&"converse"] = 1.5
	bad.points = -1
	assert_false(bad.is_valid())


# Acceptance (4): points survive save and load.
func test_points_survive_save_and_load() -> void:
	_asp.post_want(&"feast", 0)
	_asp.update(HOUR, null, {"done.feast": true})
	_asp.spend_points(3, &"reward")
	var saved: Variant = JSON.parse_string(JSON.stringify(_asp.export_state()))
	before_each()
	assert_true(_asp.import_state(saved))
	assert_eq(_asp.points(), 5)
	var older: Dictionary = (saved as Dictionary).duplicate()
	older.erase("points")
	assert_true(_asp.import_state(older), "a save from before points")
	assert_eq(_asp.points(), 0)
	_asp.add_points(2, &"host")
	for bad: Variant in [-1, 1.5, "five"]:
		var row: Dictionary = (saved as Dictionary).duplicate()
		row["points"] = bad
		assert_false(_asp.import_state(row), str(bad))
		assert_eq(_asp.points(), 2, str(bad))
