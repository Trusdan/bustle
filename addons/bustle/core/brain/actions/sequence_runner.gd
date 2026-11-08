# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSequenceRunner
extends RefCounted

## Runs one [BustleActionSequence] for one agent, a step at a time, with registered
## [BustleActionHandler]s. [code]wait[/code] and [code]idle[/code] are registered from the start.
##
## - **Each tick** ticks the current step once. DONE moves on and starts the next step (ticked from
##   the next tick on); the last step DONE makes the sequence SUCCEEDED. So one tick does at most one
##   handler tick and one start: there are no loops within a tick.
## - **A failed step** is cleaned up ([method BustleActionHandler.cancel], once), then its
##   [member BustleActionStep.on_fail] applies: RETRY starts it again until [member attempt] passes
##   [member BustleActionStep.max_retries] (then ABORT), SKIP starts the next step, ABORT ends the
##   sequence FAILED with [member failure]. A step with no handler fails with
##   [code]unknown_action[/code].
## - **[method interrupt]** cleans up the running step and keeps its place; [method resume] starts
##   that step again from the beginning. **[method cancel]** cleans up and returns to IDLE. Both do
##   nothing unless there is something to stop, so calling them twice is safe.
## - **Saving:** [method export_state] holds the status, step, attempt, failure and the step's
##   [member BustleActionContext.data]; [method import_state] (with the same sequence) restores
##   them, so a running step carries on exactly where it was.
## @experimental

## Where the sequence is.
enum State { IDLE, RUNNING, SUCCEEDED, FAILED, INTERRUPTED }

## Where the sequence is.
var state: State = State.IDLE
## The sequence.
var sequence: BustleActionSequence
## The current step's index.
var step_index: int = 0
## The current step's attempt, from 1.
var attempt: int = 0
## Why it failed: [code]{step, action, reason}[/code], or empty.
var failure: Dictionary = {}
## The current step's context.
var context := BustleActionContext.new()

var _handlers: Dictionary[StringName, BustleActionHandler] = {}
# True while the current attempt has started and not yet finished or been cleaned up.
var _active: bool = false


func _init() -> void:
	register(&"wait", BustleWaitAction.new())
	register(&"idle", BustleIdleAction.new())


## Registers [param handler] for [param action], replacing any earlier one.
## @experimental
func register(action: StringName, handler: BustleActionHandler) -> void:
	_handlers[action] = handler


## Starts [param p_sequence] for [param agent_id] (using [param option_id], if the goal chose one),
## cleaning up anything still running first. An empty sequence succeeds at once.
## @experimental
func start(p_sequence: BustleActionSequence, agent_id: StringName, now_minutes: int, option_id: StringName = &"") -> void:
	cancel()
	sequence = p_sequence
	context = BustleActionContext.new()
	context.agent_id = agent_id
	context.option_id = option_id
	context.now_minutes = now_minutes
	failure = {}
	step_index = 0
	if sequence == null or sequence.steps.is_empty():
		state = State.SUCCEEDED
		return
	state = State.RUNNING
	_start_step(1)


## Works on the sequence at [param now_minutes] for [param delta] seconds. Returns the state.
## @experimental
func tick(delta: float, now_minutes: int) -> State:
	if state != State.RUNNING:
		return state
	context.now_minutes = now_minutes
	context.output = {}
	var handler: BustleActionHandler = _handlers.get(_step().action, null)
	var status := BustleActionHandler.Status.FAILED
	if handler == null:
		context.failure = &"unknown_action"
	else:
		status = handler.tick(context, delta)
	if status == BustleActionHandler.Status.DONE:
		_active = false
		if step_index + 1 >= sequence.steps.size():
			state = State.SUCCEEDED
		else:
			step_index += 1
			_start_step(1)
	elif status == BustleActionHandler.Status.FAILED:
		_on_failed()
	return state


## Stops the running step (cleaning it up) and keeps its place for [method resume].
## @experimental
func interrupt() -> void:
	if state != State.RUNNING:
		return
	_cleanup()
	state = State.INTERRUPTED


## Starts the interrupted step again from its beginning.
## @experimental
func resume(now_minutes: int) -> void:
	if state != State.INTERRUPTED:
		return
	context.now_minutes = now_minutes
	state = State.RUNNING
	_start_step(1)


## Stops whatever is running (cleaning it up) and returns to IDLE.
## @experimental
func cancel() -> void:
	_cleanup()
	state = State.IDLE


## The runner's state as plain data.
## @experimental
func export_state() -> Dictionary:
	return {
		"state": int(state), "step": step_index, "attempt": attempt, "active": _active,
		"failure": failure.duplicate(true), "data": context.data.duplicate(true),
		"agent": String(context.agent_id), "option": String(context.option_id), "now": context.now_minutes,
	}


## Restores [method export_state]'s state for [param p_sequence], the same sequence it was saved
## with. False, leaving the runner IDLE, when the saved state doesn't fit that sequence.
## @experimental
func import_state(p_sequence: BustleActionSequence, saved: Dictionary) -> bool:
	_active = false
	state = State.IDLE
	sequence = p_sequence
	var saved_state := int(saved.get("state", -1))
	var step := int(saved.get("step", -1))
	var steps := sequence.steps.size() if sequence != null else 0
	if saved_state < State.IDLE or saved_state > State.INTERRUPTED \
			or (saved_state in [State.RUNNING, State.INTERRUPTED] and (step < 0 or step >= steps)) \
			or not saved.get("data", {}) is Dictionary or not saved.get("failure", {}) is Dictionary:
		return false
	context = BustleActionContext.new()
	context.agent_id = StringName(str(saved.get("agent", "")))
	context.option_id = StringName(str(saved.get("option", "")))
	context.now_minutes = int(saved.get("now", 0))
	context.data = (saved["data"] as Dictionary).duplicate(true) if saved.has("data") else {}
	failure = (saved["failure"] as Dictionary).duplicate(true) if saved.has("failure") else {}
	step_index = step
	attempt = int(saved.get("attempt", 0))
	state = saved_state as State
	if state == State.RUNNING:
		context.params = _step().params
		_active = bool(saved.get("active", false))
	return true


func _step() -> BustleActionStep:
	return sequence.steps[step_index]


func _start_step(p_attempt: int) -> void:
	attempt = p_attempt
	context.params = _step().params
	context.data = {}
	context.failure = &""
	var handler: BustleActionHandler = _handlers.get(_step().action, null)
	if handler != null:
		handler.start(context)
		_active = true


func _on_failed() -> void:
	var step := _step()
	var reason := context.failure if context.failure != &"" else &"failed"
	_cleanup()
	if step.on_fail == BustleActionStep.OnFail.RETRY and attempt <= step.max_retries and _handlers.has(step.action):
		_start_step(attempt + 1)
	elif step.on_fail == BustleActionStep.OnFail.SKIP:
		if step_index + 1 >= sequence.steps.size():
			state = State.SUCCEEDED
		else:
			step_index += 1
			_start_step(1)
	else:
		failure = {"step": step_index, "action": step.action, "reason": reason}
		state = State.FAILED


# Cleans up the current attempt once.
func _cleanup() -> void:
	if not _active:
		return
	_active = false
	var handler: BustleActionHandler = _handlers.get(_step().action, null) if sequence != null else null
	if handler != null:
		handler.cancel(context)
