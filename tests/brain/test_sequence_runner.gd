# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The sequence runner: steps in order, retry, skip, abort, unknown actions, interruption and
## resuming, cleanup exactly once, the built-in wait and idle actions, and saving mid-step.


## Returns its script of results in turn (then DONE), counting starts and cleanups.
class Scripted:
	extends BustleActionHandler
	var results: Array = []
	var starts := 0
	var cancels := 0

	func start(context: BustleActionContext) -> void:
		starts += 1
		context.data["ticks"] = 0

	func tick(context: BustleActionContext, _delta: float) -> Status:
		context.data["ticks"] = int(context.data["ticks"]) + 1
		var result: Status = results.pop_front() if not results.is_empty() else Status.DONE
		if result == Status.FAILED:
			context.failure = &"blocked"
		return result

	func cancel(_context: BustleActionContext) -> void:
		cancels += 1


var _runner: BustleSequenceRunner
var _act: Scripted


func before_each() -> void:
	_runner = BustleSequenceRunner.new()
	_act = Scripted.new()
	_runner.register(&"act", _act)


func _sequence(steps: Array) -> BustleActionSequence:
	var sequence := BustleActionSequence.new()
	for spec: Array in steps:
		var step := BustleActionStep.new()
		step.action = spec[0]
		step.params = spec[1] if spec.size() > 1 else {}
		if spec.size() > 2:
			step.on_fail = spec[2]
		if spec.size() > 3:
			step.max_retries = spec[3]
		sequence.steps.append(step)
	return sequence


func test_an_empty_sequence_succeeds_at_once() -> void:
	_runner.start(BustleActionSequence.new(), &"a", 0)
	assert_eq(_runner.state, BustleSequenceRunner.State.SUCCEEDED)


func test_steps_run_in_order_one_start_per_tick() -> void:
	_runner.start(_sequence([[&"act"], [&"act"]]), &"a", 0)
	assert_eq(_act.starts, 1)
	assert_eq(_runner.tick(0.1, 0), BustleSequenceRunner.State.RUNNING)
	assert_eq([_runner.step_index, _act.starts], [1, 2], "the next step starts but isn't ticked yet")
	assert_eq(_runner.tick(0.1, 0), BustleSequenceRunner.State.SUCCEEDED)
	assert_eq(_act.cancels, 0, "finished steps aren't cleaned up")


func test_retry_counts_attempts_after_the_first_then_aborts() -> void:
	var F := BustleActionHandler.Status.FAILED
	_act.results = [F, F, F]
	_runner.start(_sequence([[&"act", {}, BustleActionStep.OnFail.RETRY, 1]]), &"a", 0)
	_runner.tick(0.1, 0)
	assert_eq([_runner.state, _runner.attempt], [BustleSequenceRunner.State.RUNNING, 2], "one retry")
	_runner.tick(0.1, 0)
	assert_eq(_runner.state, BustleSequenceRunner.State.FAILED, "failing during the retry aborts")
	assert_eq(_runner.failure, {"step": 0, "action": &"act", "reason": &"blocked"})
	assert_eq([_act.starts, _act.cancels], [2, 2], "each failed attempt is cleaned up once")


func test_skip_moves_on_and_abort_stops() -> void:
	_act.results = [BustleActionHandler.Status.FAILED]
	_runner.start(_sequence([[&"act", {}, BustleActionStep.OnFail.SKIP], [&"act"]]), &"a", 0)
	_runner.tick(0.1, 0)
	assert_eq(_runner.step_index, 1)
	assert_eq(_runner.tick(0.1, 0), BustleSequenceRunner.State.SUCCEEDED)
	_runner.start(_sequence([[&"nothing", {}, BustleActionStep.OnFail.RETRY], [&"act"]]), &"a", 0)
	assert_eq(_runner.tick(0.1, 0), BustleSequenceRunner.State.FAILED, "no handler: no point retrying")
	assert_eq(_runner.failure["reason"], &"unknown_action")


func test_interrupt_cleans_up_once_and_resume_restarts_the_step() -> void:
	var R := BustleActionHandler.Status.RUNNING
	_act.results = [R, R]
	_runner.start(_sequence([[&"act"], [&"act"]]), &"a", 0)
	_runner.tick(0.1, 0)
	_runner.interrupt()
	_runner.interrupt()
	assert_eq(_runner.state, BustleSequenceRunner.State.INTERRUPTED)
	assert_eq(_act.cancels, 1, "interrupting twice cleans up once")
	_runner.resume(5)
	assert_eq([_runner.step_index, _act.starts, _runner.context.data["ticks"]], [0, 2, 0], "the step starts again")
	_runner.cancel()
	_runner.cancel()
	assert_eq([_runner.state, _act.cancels], [BustleSequenceRunner.State.IDLE, 2])
	_runner.interrupt()
	_runner.resume(6)
	assert_eq(_runner.state, BustleSequenceRunner.State.IDLE, "nothing to interrupt or resume when idle")


func test_cancelling_a_finished_runner_does_nothing() -> void:
	_runner.start(_sequence([[&"act"]]), &"a", 0)
	_runner.tick(0.1, 0)
	_runner.cancel()
	assert_eq(_act.cancels, 0)


func test_wait_and_idle_run_for_game_minutes_and_refuse_bad_minutes() -> void:
	_runner.start(_sequence([[&"wait", {"minutes": 10}], [&"idle", {"style": &"lean"}]]), &"a", 100)
	assert_eq(_runner.tick(0.1, 109), BustleSequenceRunner.State.RUNNING)
	_runner.tick(0.1, 110)
	assert_eq(_runner.step_index, 1)
	assert_eq(_runner.tick(0.1, 110), BustleSequenceRunner.State.SUCCEEDED, "idle with no minutes: one tick")
	assert_eq(_runner.context.output["animation"], &"lean")
	for bad: Variant in [-1, INF, "ten", null]:
		_runner.start(_sequence([[&"wait", {"minutes": bad}]]), &"a", 0)
		_runner.tick(0.1, 0)
		assert_eq(_runner.failure.get("reason"), &"bad_params", "wait refuses %s" % [bad])


func test_a_runner_saved_mid_step_carries_on_exactly() -> void:
	var sequence := _sequence([[&"wait", {"minutes": 30}], [&"act"]])
	_runner.start(sequence, &"a", 0)
	_runner.tick(0.1, 10)
	var copy := BustleSequenceRunner.new()
	copy.register(&"act", _act)
	assert_true(copy.import_state(sequence, _runner.export_state()))
	assert_eq(copy.export_state(), _runner.export_state())
	assert_eq(copy.tick(0.1, 29), BustleSequenceRunner.State.RUNNING, "still waiting until minute 30")
	copy.tick(0.1, 30)
	assert_eq(copy.step_index, 1)
	assert_false(copy.import_state(_sequence([[&"act"]]), {"state": 1, "step": 3}), "a step the sequence lacks")
	assert_eq(copy.state, BustleSequenceRunner.State.IDLE)
