# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleOrderQueue
extends RefCounted

## One agent's orders, first in, first out, with the runner for the front one. A [BustleBrain]
## owns it and decides each tick whether the front order runs.
##
## - **Submitting** checks the order and refuses it, with a reason, when its id is empty or already
##   queued, it has no sequence, or a step's action has no handler. A refused order is reported
##   IMPOSSIBLE and never queued.
## - **Running:** only the front order runs. When something outranks it, [method pause] interrupts
##   it and it stays at the front; when it runs again its step starts again.
## - **Finishing:** every order ends once, reported with [signal finished] and kept for
##   [method take_results]: DONE, FAILED (with the step's reason) or CANCELLED. Cancelling a queued
##   order removes it before it ever starts; cancelling the running one cleans its step up once.
## @experimental

## How an order ended.
enum Outcome { DONE, FAILED, CANCELLED, IMPOSSIBLE }

## Order [param order_id] ended in [param outcome], for [param reason] (empty when DONE).
signal finished(order_id: StringName, outcome: Outcome, reason: StringName)

## Runs the front order. [BustleBrain] shares its action handlers with it.
var runner := BustleSequenceRunner.new()

var _orders: Array[BustleOrder] = []
var _results: Array[Dictionary] = []
# The id of the order the runner was started for.
var _started: StringName = &""


## Queues [param order], at the back, or at the front when [param first] (an order running there
## is interrupted and starts its step again later). Returns an empty reason when queued, otherwise
## why it was refused.
## @experimental
func submit(order: BustleOrder, first: bool = false) -> StringName:
	var reason := _refusal(order)
	if reason != &"":
		_report(order.id if order != null else &"", Outcome.IMPOSSIBLE, reason)
		return reason
	if first:
		if is_started():
			runner.cancel()
			_started = &""
		_orders.push_front(order)
	else:
		_orders.append(order)
	return &""


## Refuses [param order] as impossible for [param reason] (for checks the queue can't make itself).
## @experimental
func refuse(order: BustleOrder, reason: StringName) -> StringName:
	_report(order.id if order != null else &"", Outcome.IMPOSSIBLE, reason)
	return reason


## The front order, or null.
## @experimental
func front() -> BustleOrder:
	return _orders[0] if not _orders.is_empty() else null


## The order at [param index] (0 is the front), or null.
## @experimental
func peek(index: int) -> BustleOrder:
	return _orders[index] if index >= 0 and index < _orders.size() else null


## The queued orders' ids, front first.
## @experimental
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for order: BustleOrder in _orders:
		out.append(order.id)
	return out


## The band [param order] competes in.
## @experimental
static func band_of(order: BustleOrder) -> int:
	return BustleBands.FORCED if order.forced else BustleBands.ORDERED


## Runs the front order for one tick (starting or resuming it as needed). Returns the runner's
## state, or IDLE when the queue is empty.
## @experimental
func run(delta: float, now_minutes: int, agent_id: StringName) -> BustleSequenceRunner.State:
	var order := front()
	if order == null:
		return BustleSequenceRunner.State.IDLE
	if _started != order.id:
		runner.start(order.sequence, agent_id, now_minutes, order.option_id)
		_started = order.id
	elif runner.state == BustleSequenceRunner.State.INTERRUPTED:
		runner.resume(now_minutes)
	var state := runner.tick(delta, now_minutes)
	if state == BustleSequenceRunner.State.SUCCEEDED:
		_finish(Outcome.DONE, &"")
	elif state == BustleSequenceRunner.State.FAILED:
		_finish(Outcome.FAILED, StringName(str(runner.failure.get("reason", "failed"))))
	return state


## Interrupts the running front order (it stays at the front).
## @experimental
func pause() -> void:
	runner.interrupt()


## True while the front order has been started and not finished.
## @experimental
func is_started() -> bool:
	return front() != null and _started == front().id


## Cancels order [param order_id], queued or running. False when it isn't queued.
## @experimental
func cancel(order_id: StringName, reason: StringName = &"cancelled") -> bool:
	for i in _orders.size():
		if _orders[i].id == order_id:
			if i == 0 and _started == order_id:
				runner.cancel()
				_started = &""
			_orders.remove_at(i)
			_report(order_id, Outcome.CANCELLED, reason)
			return true
	return false


## Cancels every order, front first.
## @experimental
func clear(reason: StringName = &"cancelled") -> void:
	while not _orders.is_empty():
		cancel(_orders[0].id, reason)


## The results reported since the last call, oldest first, each
## [code]{order, outcome, reason}[/code].
## @experimental
func take_results() -> Array[Dictionary]:
	var out := _results
	_results = []
	return out


func _finish(outcome: Outcome, reason: StringName) -> void:
	var order: BustleOrder = _orders.pop_front()
	_started = &""
	runner.cancel()
	_report(order.id, outcome, reason)


func _report(order_id: StringName, outcome: Outcome, reason: StringName) -> void:
	_results.append({"order": order_id, "outcome": outcome, "reason": reason})
	finished.emit(order_id, outcome, reason)


func _refusal(order: BustleOrder) -> StringName:
	if order == null or order.id == &"":
		return &"no_id"
	if ids().has(order.id):
		return &"duplicate_id"
	if order.sequence == null:
		return &"no_sequence"
	for step: BustleActionStep in order.sequence.steps:
		if step == null or not runner.has_handler(step.action):
			return StringName("unknown_action:%s" % (step.action if step != null else &""))
	return &""
