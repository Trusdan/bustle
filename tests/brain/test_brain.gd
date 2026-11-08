# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The brain, headless: senses in, a typed intent out; sequences started, changed, finished and
## failed; the IDLE fallback; modifiers; seeding; and saving mid-action.


## Moves toward params.to for params.ticks ticks, then is done (or fails when params.fail).
class Walk:
	extends BustleActionHandler
	var cancels := 0

	func start(context: BustleActionContext) -> void:
		context.data["left"] = int(context.params.get("ticks", 1))

	func tick(context: BustleActionContext, _delta: float) -> Status:
		if context.params.get("fail", false):
			context.failure = &"blocked"
			return Status.FAILED
		context.output["move_to"] = context.params.get("to", Vector3.ZERO)
		context.output["speed"] = "fast"
		context.output["use_affordance"] = context.option_id
		context.data["left"] = int(context.data["left"]) - 1
		return Status.DONE if int(context.data["left"]) <= 0 else Status.RUNNING

	func cancel(_context: BustleActionContext) -> void:
		cancels += 1


var _walk: Walk


func before_each() -> void:
	_walk = Walk.new()


func _sequence(params: Dictionary) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = &"walk"
	step.params = params
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _goal(id: StringName, input: StringName, params: Dictionary = {"ticks": 3}) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.PERSONAL
	var consideration := BustleConsideration.new()
	consideration.input = input
	consideration.curve = Curve.new()
	consideration.curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	consideration.curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	goal.considerations.append(consideration)
	goal.sequence = _sequence(params)
	return goal


func _brain(goals: Array, seed: int = 7, id: StringName = &"agent_a") -> BustleBrain:
	var library := BustleGoalLibrary.new()
	for goal: BustleGoalDef in goals:
		library.goals.append(goal)
	var brain := BustleBrain.new(id, library, BustleScoringConfig.new(), seed)
	brain.runner.register(&"walk", _walk)
	return brain


func _senses(now: int, inputs: Dictionary, ads: Array = []) -> BustleSenses:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	for key: Variant in inputs:
		senses.inputs[StringName(str(key))] = float(inputs[key])
	for ad: BustleAdvertisement in ads:
		senses.advertisements.append(ad)
	return senses


func test_a_tick_with_no_host_returns_a_typed_intent_with_reasons() -> void:
	var brain := _brain([_goal(&"rest", &"need.sleep", {"ticks": 3, "to": Vector3(1, 0, 2)})])
	var intent := brain.tick(0.1, _senses(0, {"need.sleep": 0.8}))
	assert_eq([intent.goal_id, intent.band, intent.action, intent.idle], [&"rest", BustleBands.PERSONAL, &"walk", false])
	assert_almost_eq(intent.score, 0.8, 1e-6)
	assert_true(intent.has_move_to)
	assert_eq(intent.move_to, Vector3(1, 0, 2))
	assert_eq(intent.speed, 0.0, "a wrongly typed speed is ignored")
	assert_true(intent.reasons.any(func(r: Dictionary) -> bool: return r["kind"] == &"consideration"))


func test_nothing_eligible_gives_the_idle_fallback_and_stops_the_sequence() -> void:
	var brain := _brain([_goal(&"rest", &"need.sleep")])
	brain.tick(0.1, _senses(0, {"need.sleep": 0.8}))
	var intent := brain.tick(0.1, _senses(1, {"need.sleep": 0.0}))
	assert_true(intent.idle)
	assert_eq([intent.goal_id, intent.action], [&"idle", &""])
	assert_eq(_walk.cancels, 1, "the running sequence is cleaned up")


func test_a_new_choice_cancels_the_old_sequence_and_passes_the_option_on() -> void:
	var use := _goal(&"use", &"need.sleep")
	use.considerations.clear()
	use.uses_advertisements = true
	var brain := _brain([_goal(&"rest", &"need.food"), use])
	brain.tick(0.1, _senses(0, {"need.food": 0.3, "need.sleep": 0.5}))
	var bed := BustleAdvertisement.new(&"bed", {&"sleep": 2.0})
	var intent := brain.tick(0.1, _senses(1, {"need.food": 0.3, "need.sleep": 0.5}, [bed]))
	assert_eq([intent.goal_id, intent.option_id, intent.use_affordance], [&"use", &"bed", &"bed"])
	assert_eq(_walk.cancels, 1)


func test_modifiers_change_the_choice_through_weights_and_multipliers() -> void:
	var use := BustleGoalDef.new()
	use.id = &"use"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	use.sequence = _sequence({"ticks": 9})
	var brain := _brain([use])
	var ads := [BustleAdvertisement.new(&"hall", {&"company": 1.0}, {}, [&"social"]),
		BustleAdvertisement.new(&"path", {&"company": 0.5}, {}, [&"solitary"])]
	assert_eq(brain.tick(0.1, _senses(0, {"need.company": 0.5}, ads)).option_id, &"hall")
	brain.keeper.clear()
	brain.modifiers.set_source(&"loner", &"tag.social.mult", 0.0, 0.2)
	assert_eq(brain.tick(0.1, _senses(1, {"need.company": 0.5}, ads)).option_id, &"path")


func test_a_finished_sequence_starts_again_and_a_failed_one_cools_down() -> void:
	var brain := _brain([_goal(&"rest", &"need.sleep", {"ticks": 1})])
	brain.tick(0.1, _senses(0, {"need.sleep": 0.8}))
	assert_eq(brain.runner.state, BustleSequenceRunner.State.SUCCEEDED)
	assert_eq(brain.tick(0.1, _senses(1, {"need.sleep": 0.8})).action, &"walk", "chosen again: started again")
	var failing := _brain([_goal(&"rest", &"need.sleep", {"fail": true})])
	var intent := failing.tick(0.1, _senses(5, {"need.sleep": 0.8}))
	assert_eq(intent.failure, {"step": 0, "action": &"walk", "reason": &"blocked"})
	assert_true(failing.tick(0.1, _senses(5, {"need.sleep": 0.8})).idle, "it sits out the minute it failed")
	assert_eq(failing.tick(0.1, _senses(6, {"need.sleep": 0.8})).goal_id, &"rest")


func test_seeding_is_fixed_and_a_run_repeats() -> void:
	# Reference values from an independent 64-bit FNV-1a, as signed 64-bit ints.
	assert_eq(BustleBrain.seed_for(0, &""), -6284781860667377211)
	assert_eq(BustleBrain.seed_for(42, &"agent_a"), 3392253134814888880)
	assert_ne(BustleBrain.seed_for(42, &"agent_a"), BustleBrain.seed_for(42, &"agent_b"))
	var runs: Array = []
	for run in 2:
		var brain := _brain([_goal(&"a", &"need.food", {"ticks": 1}), _goal(&"b", &"need.food", {"ticks": 1}),
			_goal(&"c", &"need.food", {"ticks": 1})], 42)
		var picks: Array = []
		for t in 200:
			brain.keeper.clear()
			picks.append(brain.tick(0.1, _senses(t, {"need.food": 0.5})).goal_id)
		runs.append(picks)
	assert_eq(runs[0], runs[1], "same seed, same inputs: the same 200 choices")


func test_a_brain_saved_mid_action_continues_identically() -> void:
	var goals := [_goal(&"a", &"need.food", {"ticks": 4}), _goal(&"b", &"need.food", {"ticks": 4})]
	var one := _brain(goals, 3)
	for t in 3:
		one.tick(0.1, _senses(t, {"need.food": 0.5}))
	var saved := one.export_state()
	var two := _brain(goals, 3)
	assert_true(two.import_state(saved))
	assert_eq(two.export_state(), saved)
	for t in range(3, 40):
		var inputs := {"need.food": 0.5 + 0.01 * (t % 5)}
		assert_eq(two.tick(0.1, _senses(t, inputs)).to_dictionary(), one.tick(0.1, _senses(t, inputs)).to_dictionary())


func test_a_state_that_doesnt_fit_is_refused_and_leaves_a_fresh_brain() -> void:
	var one := _brain([_goal(&"a", &"need.food")])
	one.tick(0.1, _senses(0, {"need.food": 0.5}))
	var saved := one.export_state()
	var fresh := _brain([_goal(&"a", &"need.food")]).export_state()
	var other := _brain([_goal(&"z", &"need.food")])
	assert_false(other.import_state(saved), "the running goal isn't in this library")
	assert_eq(other.export_state()["running_goal"], "")
	var wrong_agent := _brain([_goal(&"a", &"need.food")], 7, &"agent_b")
	assert_false(wrong_agent.import_state(saved))
	var bad := saved.duplicate(true)
	bad["version"] = 99
	var same := _brain([_goal(&"a", &"need.food")])
	assert_false(same.import_state(bad))
	assert_eq(same.export_state(), fresh, "nothing half-restored")
