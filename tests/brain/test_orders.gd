# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Orders and autonomy: the queue, bands (orders below urgent self-care, forced above danger),
## interrupting and resuming the self-chosen goal, completion, failure, cancellation, autonomy
## levels and player control.


## Counts starts and cleanups per action; ends after params.ticks ticks, or fails when params.fail.
class Counted:
	extends BustleActionHandler
	var starts := 0
	var cancels := 0

	func start(context: BustleActionContext) -> void:
		starts += 1
		context.data["left"] = int(context.params.get("ticks", 1))

	func tick(context: BustleActionContext, _delta: float) -> Status:
		if context.params.get("fail", false):
			context.failure = &"blocked"
			return Status.FAILED
		context.data["left"] = int(context.data["left"]) - 1
		return Status.DONE if int(context.data["left"]) <= 0 else Status.RUNNING

	func cancel(_context: BustleActionContext) -> void:
		cancels += 1


var _work: Counted
var _task: Counted
var _brain: BustleBrain
var _results: Array = []


func before_each() -> void:
	_work = Counted.new()
	_task = Counted.new()
	_results = []
	var library := BustleGoalLibrary.new()
	library.goals = [_goal(&"shift", BustleBands.DUTY, &"schedule.on_shift"),
		_goal(&"eat", BustleBands.URGENT, &"need.food"), _goal(&"flee", BustleBands.CRITICAL, &"threat.near")]
	_brain = BustleBrain.new(&"agent_a", library, BustleScoringConfig.new(), 1)
	_brain.runner.register(&"work", _work)
	_brain.runner.register(&"task", _task)
	_brain.orders.finished.connect(func(id: StringName, outcome: int, reason: StringName) -> void:
		_results.append([id, outcome, reason]))


func _sequence(action: StringName, params: Dictionary) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = action
	step.params = params
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _goal(id: StringName, band: int, input: StringName) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.preconditions = [{"kind": &"input", "input": input}]
	goal.sequence = _sequence(&"work", {"ticks": 100})
	return goal


func _order(id: StringName, ticks: int = 2, forced: bool = false, fail: bool = false) -> BustleOrder:
	return BustleOrder.new(id, _sequence(&"task", {"ticks": ticks, "fail": fail}), &"target", forced)


func _tick(now: int, inputs: Dictionary = {"schedule.on_shift": 1.0}) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	for key: Variant in inputs:
		senses.inputs[StringName(str(key))] = float(inputs[key])
	return _brain.tick(0.1, senses)


func test_impossible_orders_are_refused_with_a_reason() -> void:
	assert_eq(_brain.order(BustleOrder.new(&"", _sequence(&"task", {}))), &"no_id")
	assert_eq(_brain.order(BustleOrder.new(&"o", null)), &"no_sequence")
	assert_eq(_brain.order(BustleOrder.new(&"o", _sequence(&"dance", {}))), &"unknown_action:dance")
	assert_eq(_brain.order(_order(&"o")), &"")
	assert_eq(_brain.order(_order(&"o")), &"duplicate_id")
	assert_eq(_brain.orders.ids(), [&"o"])
	assert_eq(_results.filter(func(r: Array) -> bool: return r[1] == BustleOrderQueue.Outcome.IMPOSSIBLE).size(), 4)


func test_an_order_preempts_the_goal_which_resumes_after_it_is_done() -> void:
	assert_eq(_tick(0).goal_id, &"shift")
	_brain.order(_order(&"a"))
	_brain.order(_order(&"b", 1))
	var intent := _tick(1)
	assert_eq([intent.order_id, intent.band, intent.action, intent.option_id], [&"a", BustleBands.ORDERED, &"task", &"target"])
	assert_eq(_work.cancels, 1, "the goal's step was cleaned up once")
	intent = _tick(2)
	assert_eq(intent.order_results, [{"order": &"a", "outcome": BustleOrderQueue.Outcome.DONE, "reason": &""}])
	assert_eq(_tick(3).order_id, &"b", "first in, first out")
	intent = _tick(4)
	assert_eq(intent.goal_id, &"shift", "back to the previous goal")
	assert_true(intent.reasons.any(func(r: Dictionary) -> bool: return r["kind"] == &"resumed"))
	assert_eq(_work.starts, 2, "its step started again")


func test_a_paused_goal_that_is_no_longer_eligible_is_dropped() -> void:
	_tick(0)
	_brain.order(_order(&"a", 1))
	_tick(1)
	var intent := _tick(2, {})
	assert_true(intent.idle, "off shift: nothing to resume")
	assert_eq(_brain.runner.state, BustleSequenceRunner.State.IDLE)


func test_urgent_self_care_and_danger_preempt_an_order_which_then_resumes() -> void:
	_brain.order(_order(&"a", 3))
	assert_eq(_tick(0).order_id, &"a")
	var intent := _tick(1, {"need.food": 1.0})
	assert_eq(intent.goal_id, &"eat", "orders sit below urgent self-care")
	assert_eq(_task.cancels, 1, "the order's step was cleaned up")
	assert_eq(_tick(2, {"threat.near": 1.0}).goal_id, &"flee", "danger preempts an unforced order")
	intent = _tick(3)
	assert_eq(intent.order_id, &"a", "the order comes back")
	assert_eq(_task.starts, 2, "its step started again")


func test_a_forced_order_holds_through_danger() -> void:
	_brain.order(_order(&"drafted", 3, true))
	var intent := _tick(0, {"threat.near": 1.0, "need.food": 1.0})
	assert_eq([intent.order_id, intent.band], [&"drafted", BustleBands.FORCED])
	assert_eq(_tick(1, {"threat.near": 1.0}).order_id, &"drafted")


func test_a_failed_order_reports_why_and_the_goal_resumes() -> void:
	_tick(0)
	_brain.order(_order(&"a", 1, false, true))
	var intent := _tick(1)
	assert_eq(intent.order_results, [{"order": &"a", "outcome": BustleOrderQueue.Outcome.FAILED, "reason": &"blocked"}])
	assert_eq(_tick(2).goal_id, &"shift")


func test_cancelled_orders_never_run_or_are_cleaned_up_once() -> void:
	_brain.order(_order(&"a", 5))
	_brain.order(_order(&"b", 5))
	assert_true(_brain.orders.cancel(&"b"))
	assert_false(_brain.orders.cancel(&"b"))
	_tick(0)
	assert_true(_brain.orders.cancel(&"a"))
	assert_eq([_task.starts, _task.cancels], [1, 1], "b never started; a was cleaned up once")
	assert_eq(_results.map(func(r: Array) -> Array: return [r[0], r[1]]),
		[[&"b", BustleOrderQueue.Outcome.CANCELLED], [&"a", BustleOrderQueue.Outcome.CANCELLED]])
	assert_eq(_tick(1).goal_id, &"shift")


func test_autonomy_off_runs_only_orders_and_low_only_urgent_goals() -> void:
	_brain.autonomy = BustleBrain.Autonomy.OFF
	var intent := _tick(0, {"schedule.on_shift": 1.0, "threat.near": 1.0})
	assert_true(intent.idle, "orders only, danger included")
	_brain.order(_order(&"a", 1))
	assert_eq(_tick(1, {"threat.near": 1.0}).order_id, &"a", "an order still runs")
	_brain.autonomy = BustleBrain.Autonomy.LOW
	assert_true(_tick(2).idle, "LOW: no duty")
	assert_eq(_tick(3, {"schedule.on_shift": 1.0, "need.food": 1.0}).goal_id, &"eat")
	_brain.autonomy = BustleBrain.Autonomy.NORMAL
	assert_eq(_tick(4).goal_id, &"shift", "NORMAL uses the whole scorer, as FULL does")


func test_off_still_scores_and_explains_while_choosing_nothing() -> void:
	_brain.autonomy = BustleBrain.Autonomy.OFF
	var library := _brain.library
	var context := BustleScoreContext.new()
	context.inputs = {&"schedule.on_shift": 1.0}
	var candidates := BustleUtilityScorer.new().evaluate(library, context, _brain.config)
	assert_true(candidates.any(func(c: BustleCandidate) -> bool: return c.eligible), "the scorer still sees it")
	assert_true(_tick(0).idle)


func test_a_player_controlled_agent_never_chooses_and_refuses_orders() -> void:
	_tick(0)
	_brain.order(_order(&"a", 5))
	_brain.order(_order(&"b", 5))
	_tick(1)
	var rng_state: int = _brain.export_state()["rng_state"]
	_brain.set_player_controlled(true)
	var intent := _tick(2)
	assert_true(intent.player_controlled)
	assert_eq([intent.goal_id, intent.order_id, intent.action], [&"", &"", &""])
	assert_eq(intent.order_results.map(func(r: Dictionary) -> StringName: return r["reason"]),
		[&"player_controlled", &"player_controlled"])
	for t in 100:
		assert_eq(_tick(3 + t, {"schedule.on_shift": 1.0, "threat.near": 1.0}).goal_id, &"")
	assert_eq(_brain.order(_order(&"c")), &"player_controlled")
	assert_eq(_brain.export_state()["rng_state"], rng_state, "the generator wasn't touched")
	_brain.set_player_controlled(false)
	assert_eq(_tick(200).goal_id, &"shift")


func test_autonomy_player_control_and_a_paused_goal_are_saved() -> void:
	_tick(0)
	_brain.order(_order(&"a", 5))
	_tick(1)
	_brain.autonomy = BustleBrain.Autonomy.LOW
	var saved := _brain.export_state()
	var copy := BustleBrain.new(&"agent_a", _brain.library, _brain.config, 1)
	copy.runner.register(&"work", _work)
	assert_true(copy.import_state(saved))
	assert_eq(copy.autonomy, BustleBrain.Autonomy.LOW)
	assert_eq(copy.runner.state, BustleSequenceRunner.State.INTERRUPTED, "the paused goal is kept")
	assert_eq(copy.orders.ids(), [], "orders aren't saved")
	saved.erase("autonomy")
	saved.erase("player_controlled")
	assert_true(copy.import_state(saved), "older states without the fields still load")
	assert_eq([copy.autonomy, copy.player_controlled], [BustleBrain.Autonomy.FULL, false])
	var society := BustleSociety.new()
	society.register_archetype(&"worker", _brain.library)
	society.add_agent(&"agent_a", &"worker")
	assert_eq(society.order(&"nobody", _order(&"x")), &"no_agent")
	assert_eq(society.order(&"agent_a", BustleOrder.new(&"x", null)), &"no_sequence")
