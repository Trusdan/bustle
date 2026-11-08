# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Hysteresis: momentum, the keep window, minimum commitment, interruption by a higher band,
## dropping an ineligible choice, failure cooldowns and the keeper's saved state.

var _scorer := BustleUtilityScorer.new()
var _config := BustleScoringConfig.new()
var _rng := RandomNumberGenerator.new()
var _keeper: BustleChoiceKeeper


func before_each() -> void:
	_keeper = BustleChoiceKeeper.new()
	_rng.seed = 1


func _goal(id: StringName, band: int, commit: int = 0) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.min_commit_minutes = commit
	return goal


## Scores are the goals' base weights.
func _decide(goals: Array, scores: Dictionary, now: int) -> BustleCandidate:
	var library := BustleGoalLibrary.new()
	for goal: BustleGoalDef in goals:
		goal.base_weight = float(scores.get(goal.id, 0.0))
		library.goals.append(goal)
	return _keeper.choose(_scorer.evaluate(library, BustleScoreContext.new(), _config), library, _config, _rng, now)


func test_two_near_equal_goals_never_flicker() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL)
	var b := _goal(&"b", BustleBands.PERSONAL)
	var first := _decide([a, b], {&"a": 0.50, &"b": 0.52}, 0).goal_id
	var switches := 0
	for tick in 100:
		var scores := {&"a": 0.50, &"b": 0.52} if tick % 2 == 0 else {&"a": 0.52, &"b": 0.50}
		if _decide([a, b], scores, tick).goal_id != first:
			switches += 1
	assert_eq(switches, 0, "momentum keeps the current goal inside the window")


func test_a_challenger_beyond_the_kept_window_takes_over() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL)
	var b := _goal(&"b", BustleBands.PERSONAL)
	assert_eq(_decide([a, b], {&"a": 0.50}, 0).goal_id, &"a")
	# 0.50 × 1.15 = 0.575; 0.60 puts the cutoff at 0.54, so a is still in the window and is kept.
	assert_eq(_decide([a, b], {&"a": 0.50, &"b": 0.60}, 1).goal_id, &"a")
	# At exactly 0.575 / 0.9 the cutoff is 0.575: the edge is inclusive, so a is kept.
	assert_eq(_decide([a, b], {&"a": 0.50, &"b": 0.575 / 0.9}, 2).goal_id, &"a")
	# 0.65 puts the cutoff at 0.585, above 0.575: b takes over.
	assert_eq(_decide([a, b], {&"a": 0.50, &"b": 0.65}, 3).goal_id, &"b")


func test_commitment_holds_off_the_same_band_but_not_a_higher_one() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL, 20)
	var b := _goal(&"b", BustleBands.PERSONAL)
	var danger := _goal(&"danger", BustleBands.CRITICAL)
	assert_eq(_decide([a, b, danger], {&"a": 0.5}, 0).goal_id, &"a")
	assert_eq(_decide([a, b, danger], {&"a": 0.5, &"b": 0.9}, 19).goal_id, &"a", "inside its 20 minutes")
	assert_eq(_decide([a, b, danger], {&"a": 0.5, &"b": 0.9, &"danger": 0.1}, 19).goal_id, &"danger",
		"a higher band interrupts at once")
	_keeper.clear()
	assert_eq(_decide([a, b, danger], {&"a": 0.5}, 0).goal_id, &"a")
	assert_eq(_decide([a, b, danger], {&"a": 0.5, &"b": 0.9}, 20).goal_id, &"b", "after its 20 minutes")


func test_an_ineligible_current_goal_is_dropped_and_momentum_cant_save_it() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL, 60)
	a.min_score = 0.5
	var b := _goal(&"b", BustleBands.PERSONAL)
	assert_eq(_decide([a, b], {&"a": 0.5}, 0).goal_id, &"a")
	# 0.45 × 1.15 would clear 0.5, but eligibility uses the raw score.
	var picked := _decide([a, b], {&"a": 0.45, &"b": 0.1}, 1)
	assert_eq(picked.goal_id, &"b", "dropped at once, even inside its commitment")
	assert_eq(_decide([a, b], {}, 2).goal_id, &"idle", "nothing eligible: the IDLE fallback")


func test_a_failed_goal_cools_down() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL)
	a.fail_cooldown_minutes = 30
	var b := _goal(&"b", BustleBands.PERSONAL)
	var library := BustleGoalLibrary.new()
	library.goals = [a, b]
	assert_eq(_decide([a, b], {&"a": 0.9, &"b": 0.1}, 0).goal_id, &"a")
	_keeper.mark_failed(&"a", library, 0)
	assert_eq(_keeper.goal_id, &"", "the current choice is cleared")
	assert_eq(_decide([a, b], {&"a": 0.9, &"b": 0.1}, 29).goal_id, &"b")
	assert_eq(_decide([a, b], {&"a": 0.9, &"b": 0.1}, 30).goal_id, &"a", "back after 30 minutes")


func test_with_no_cooldown_a_failed_goal_still_sits_out_the_minute_it_failed() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL)
	var library := BustleGoalLibrary.new()
	library.goals = [a]
	_keeper.mark_failed(&"a", library, 5)
	assert_true(_decide([a], {&"a": 0.9}, 5).fallback, "no fail, choose, fail loop within a minute")
	assert_eq(_decide([a], {&"a": 0.9}, 6).goal_id, &"a")


func test_the_keeper_state_round_trips() -> void:
	var a := _goal(&"a", BustleBands.PERSONAL, 20)
	var b := _goal(&"b", BustleBands.PERSONAL)
	var library := BustleGoalLibrary.new()
	library.goals = [a, b]
	_decide([a, b], {&"a": 0.5}, 3)
	_keeper.mark_failed(&"b", library, 4)
	var copy := BustleChoiceKeeper.new()
	copy.import_state(_keeper.export_state())
	assert_eq(copy.export_state(), _keeper.export_state())
	_keeper = copy
	assert_eq(_decide([a, b], {&"a": 0.5, &"b": 0.9}, 10).goal_id, &"a", "commitment survives the round trip")
	copy.import_state({"cooldowns": "nonsense", "since": "x"})
	assert_eq(copy.cooldowns.size(), 0, "malformed state is dropped")
