# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleBrain
extends RefCounted

## One agent's brain, headless: [method tick] takes [BustleSenses] and returns a [BustleIntent].
## It never reads the scene and never runs by itself; whoever drives it decides how often to tick.
##
## Each tick:
## 1. The agent's [member modifiers] fill the need weights and tag multipliers the options use.
## 2. [BustleUtilityScorer] scores the [member library]; [BustleChoiceKeeper] chooses with
##    hysteresis, using the brain's own random generator.
## 3. When the choice changes, the old goal's sequence is cancelled and the new goal's
##    [member BustleGoalDef.sequence] starts (with the chosen option). A finished sequence starts
##    again if its goal is chosen again on a later tick.
## 4. The sequence is ticked once. If it fails, the goal is marked failed (it cools down) and the
##    intent carries the failure; the next tick chooses again.
## 5. The intent holds the choice, its reasons and the running step's output.
##
## **Orders.** [method order] queues a [BustleOrder] (see [BustleOrderQueue]). The front order runs
## when its band ([constant BustleBands.ORDERED], or [constant BustleBands.FORCED] when forced) is at
## least the best self-chosen band; otherwise it waits at the front, paused. While an order runs,
## the self-chosen goal's sequence is interrupted; when the order ends, that goal resumes (its step
## starting again) if it is still eligible and in the highest eligible band, and is dropped
## otherwise. Finished orders are reported on the intent and by [signal BustleOrderQueue.finished].
##
## **Autonomy.** [member autonomy] limits self-chosen goals between orders: FULL and NORMAL use the
## whole scorer, LOW only URGENT and CRITICAL goals, OFF none at all (orders only; with no order, the
## IDLE fallback). The brain runs no needs itself, so whatever updates an agent's inputs carries on.
##
## **Player control.** While [member player_controlled] is on the brain never chooses: the intent
## only says so. Turning it on cancels the running goal and every order, and orders are refused.
##
## **Seeding.** The generator is seeded once, from [method seed_for] (a fixed FNV-1a hash of the
## world seed and the agent id, the same on every platform), and its state is saved with the brain,
## so a run repeats exactly from the same seed and inputs.
## @experimental

## The saved-state layout version.
const STATE_VERSION := 1

## How much an agent chooses for itself between orders.
enum Autonomy {
	## Orders only.
	OFF,
	## Only URGENT and CRITICAL goals.
	LOW,
	## The whole scorer.
	NORMAL,
	## The whole scorer (agents not expected to get orders).
	FULL,
}

## The agent's id.
var agent_id: StringName = &""
## The goals it chooses from.
var library: BustleGoalLibrary
## The scorer's curves and settings.
var config: BustleScoringConfig
## Numbers sources add to or multiply (weights and multipliers among them).
var modifiers := BustleModifierSet.new()
## Hysteresis and failure cooldowns.
var keeper := BustleChoiceKeeper.new()
## Runs the chosen goal's sequence. Register action handlers on it.
var runner := BustleSequenceRunner.new()
## The world seed it was made with.
var world_seed: int = 0
## The agent's orders.
var orders := BustleOrderQueue.new()
## How much it chooses for itself between orders.
var autonomy: Autonomy = Autonomy.FULL
## True while a player controls the agent directly. Set it with [method set_player_controlled].
var player_controlled: bool = false
## The senses of the last tick, or null. Kept by reference for inspection; not saved.
var last_senses: BustleSenses
## The scorer's candidates from the last tick, as scored (empty under player control). Kept by
## reference for inspection; not saved.
var last_candidates: Array[BustleCandidate] = []
## The intent of the last tick, or null. Not saved.
var last_intent: BustleIntent

## [code]func(goal_id, option_id) -> float[/code]: multiplies each candidate's score (see
## [member BustleScoreContext.score_boost]), for example [method BustleAmbitions.boost]. Unset: 1.
var score_boost: Callable = Callable()

var _rng := RandomNumberGenerator.new()
var _scorer := BustleUtilityScorer.new()
# The goal and option whose sequence the runner was started for.
var _running_goal: StringName = &""
var _running_option: StringName = &""


func _init(p_agent_id: StringName = &"", p_library: BustleGoalLibrary = null,
		p_config: BustleScoringConfig = null, p_world_seed: int = 0) -> void:
	agent_id = p_agent_id
	library = p_library if p_library != null else BustleGoalLibrary.new()
	config = p_config if p_config != null else BustleScoringConfig.new()
	world_seed = p_world_seed
	_rng.seed = seed_for(world_seed, agent_id)
	orders.runner.share_handlers_with(runner)


## Queues [param order]. Returns an empty reason when queued, otherwise why it is impossible (also
## reported through the queue).
## @experimental
func order(p_order: BustleOrder) -> StringName:
	if player_controlled:
		return orders.refuse(p_order, &"player_controlled")
	return orders.submit(p_order)


## Turns direct player control on or off. Turning it on cancels the running goal and every order.
## @experimental
func set_player_controlled(on: bool) -> void:
	if on and not player_controlled:
		_stop()
		orders.clear(&"player_controlled")
	player_controlled = on


## The generator seed for [param p_agent_id] in a world seeded [param p_world_seed]: 64-bit FNV-1a
## over the world seed's 8 bytes (little-endian) and the id's UTF-8 bytes.
## @experimental
static func seed_for(p_world_seed: int, p_agent_id: StringName) -> int:
	var h := -3750763034362895579 # 0xcbf29ce484222325 as a signed 64-bit int
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, p_world_seed)
	bytes.append_array(String(p_agent_id).to_utf8_buffer())
	for b: int in bytes:
		h = (h ^ b) * 1099511628211
	return h


## Thinks for one tick of [param delta] seconds and returns what the agent should do.
## @experimental
func tick(delta: float, senses: BustleSenses) -> BustleIntent:
	last_senses = senses
	last_candidates = []
	last_intent = _think(delta, senses)
	return last_intent


func _think(delta: float, senses: BustleSenses) -> BustleIntent:
	if player_controlled:
		var held := BustleIntent.new()
		held.player_controlled = true
		held.order_results = orders.take_results()
		return held
	var context := BustleScoreContext.new()
	context.inputs = senses.inputs
	context.advertisements = senses.advertisements
	context.score_boost = score_boost
	var needs: Array[StringName] = []
	var tags: Array[StringName] = []
	for ad: BustleAdvertisement in senses.advertisements:
		if ad == null:
			continue
		for need: StringName in ad.relief.keys() + ad.adds.keys():
			if not needs.has(need):
				needs.append(need)
		for tag: StringName in ad.tags:
			if not tags.has(tag):
				tags.append(tag)
	modifiers.fill_context(context, needs, tags)
	var candidates := _scorer.evaluate(library, context, config)
	last_candidates = candidates
	var top := _apply_autonomy(candidates)
	var front := orders.front()
	if front != null and front.held:
		top = _hold(candidates, front, senses)
	if front != null and BustleOrderQueue.band_of(front) >= top:
		return _run_order(delta, senses, front)
	if orders.is_started():
		orders.pause()
	var choice := _resumed(candidates, top, senses.now_minutes)
	if choice == null:
		choice = keeper.choose(candidates, library, config, _rng, senses.now_minutes)
	var intent := BustleIntent.new()
	intent.order_results = orders.take_results()
	intent.goal_id = choice.goal_id
	intent.option_id = choice.option_id
	intent.band = choice.band
	intent.score = choice.raw_score
	intent.idle = choice.fallback
	intent.reasons = choice.reasons.duplicate(true)
	if choice.fallback:
		_stop()
		return intent
	if choice.goal_id != _running_goal or choice.option_id != _running_option \
			or runner.state in [BustleSequenceRunner.State.SUCCEEDED, BustleSequenceRunner.State.FAILED, BustleSequenceRunner.State.IDLE]:
		_stop()
		var goal := library.find(choice.goal_id)
		if goal != null and goal.sequence != null:
			runner.start(goal.sequence, agent_id, senses.now_minutes, choice.option_id)
			_running_goal = choice.goal_id
			_running_option = choice.option_id
	if _running_goal == &"":
		return intent
	if runner.state == BustleSequenceRunner.State.INTERRUPTED:
		runner.resume(senses.now_minutes)
	intent.action = runner.sequence.steps[runner.step_index].action if runner.state == BustleSequenceRunner.State.RUNNING else &""
	var state := runner.tick(delta, senses.now_minutes)
	intent.read_output(runner.context.output)
	if state == BustleSequenceRunner.State.FAILED:
		intent.failure = runner.failure.duplicate(true)
		keeper.mark_failed(_running_goal, library, senses.now_minutes)
		_running_goal = &""
		_running_option = &""
	return intent


## The brain's whole state as plain data: the generator, the keeper, the runner and which goal the
## runner is running. The generator state is a 64-bit int.
## @experimental
func export_state() -> Dictionary:
	return {
		"version": STATE_VERSION, "agent": String(agent_id), "world_seed": world_seed,
		"autonomy": int(autonomy), "player_controlled": player_controlled,
		"rng_state": _rng.state, "keeper": keeper.export_state(), "runner": runner.export_state(),
		"running_goal": String(_running_goal), "running_option": String(_running_option),
	}


## Restores [method export_state]'s state into a brain made for the same agent and library. False,
## leaving the brain as freshly made, when the state doesn't fit (another version or agent, a
## running goal the library lacks, or a runner state that doesn't fit its sequence).
## @experimental
func import_state(saved: Dictionary) -> bool:
	_reset()
	if int(saved.get("version", -1)) != STATE_VERSION or StringName(str(saved.get("agent", ""))) != agent_id \
			or typeof(saved.get("rng_state")) != TYPE_INT or not saved.get("keeper") is Dictionary \
			or not saved.get("runner") is Dictionary:
		return false
	var goal_name := StringName(str(saved.get("running_goal", "")))
	var sequence: BustleActionSequence = null
	if goal_name != &"":
		var goal := library.find(goal_name)
		if goal == null or goal.sequence == null:
			return false
		sequence = goal.sequence
	if not runner.import_state(sequence, saved["runner"]):
		_reset()
		return false
	world_seed = int(saved.get("world_seed", world_seed))
	_rng.seed = seed_for(world_seed, agent_id)
	_rng.state = saved["rng_state"]
	keeper.import_state(saved["keeper"])
	var level := int(saved.get("autonomy", Autonomy.FULL))
	autonomy = (level if level >= Autonomy.OFF and level <= Autonomy.FULL else Autonomy.FULL) as Autonomy
	player_controlled = saved.get("player_controlled", false) == true
	_running_goal = goal_name
	_running_option = StringName(str(saved.get("running_option", "")))
	return true


# Makes self-chosen candidates the autonomy level rules out ineligible. Returns the highest
# eligible band left, or -1.
func _apply_autonomy(candidates: Array[BustleCandidate]) -> int:
	var top := -1
	for candidate: BustleCandidate in candidates:
		var allowed := autonomy == Autonomy.NORMAL or autonomy == Autonomy.FULL \
				or (autonomy == Autonomy.LOW and candidate.band >= BustleBands.URGENT)
		if candidate.eligible and not allowed:
			candidate.eligible = false
			candidate.reasons.append({"kind": &"autonomy", "level": autonomy})
		if candidate.eligible:
			top = maxi(top, candidate.band)
	return top


# The paused goal, when it should resume: still eligible and in the highest eligible band. Drops
# it otherwise.
func _resumed(candidates: Array[BustleCandidate], top: int, now_minutes: int) -> BustleCandidate:
	if _running_goal == &"" or runner.state != BustleSequenceRunner.State.INTERRUPTED:
		return null
	for candidate: BustleCandidate in candidates:
		if candidate.goal_id == _running_goal and candidate.option_id == _running_option \
				and candidate.eligible and candidate.band == top:
			candidate.reasons.append({"kind": &"resumed"})
			keeper.goal_id = candidate.goal_id
			keeper.option_id = candidate.option_id
			keeper.band = candidate.band
			return candidate
	_stop()
	return null


func _run_order(delta: float, senses: BustleSenses, front: BustleOrder) -> BustleIntent:
	if runner.state == BustleSequenceRunner.State.RUNNING:
		runner.interrupt()
	var intent := BustleIntent.new()
	intent.order_id = front.id
	intent.option_id = front.option_id
	intent.band = BustleOrderQueue.band_of(front)
	intent.reasons = [{"kind": &"order", "forced": front.forced}]
	if not front.sequence.steps.is_empty():
		var index := orders.runner.step_index if orders.is_started() else 0
		intent.action = front.sequence.steps[index].action
	orders.run(delta, senses.now_minutes, agent_id)
	intent.read_output(orders.runner.context.output)
	if front.held and front.position is Vector3 and not intent.has_move_to:
		intent.move_to = front.position
		intent.has_move_to = true
	intent.order_results = orders.take_results()
	return intent


# A held order at the front: candidates above ORDERED may only interrupt it from CRITICAL, or from
# URGENT when the order has no place or the option is advertised within its reach. Others are
# made ineligible. Returns the highest eligible band left, or -1.
func _hold(candidates: Array[BustleCandidate], front: BustleOrder, senses: BustleSenses) -> int:
	var top := -1
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and candidate.band > BustleBands.ORDERED and candidate.band < BustleBands.CRITICAL:
			var keeps := candidate.band >= BustleBands.URGENT and (front.place == &"" or _within(candidate.option_id, senses, front.reach))
			if not keeps:
				candidate.eligible = false
				candidate.reasons.append({"kind": &"held", "order": front.id})
		if candidate.eligible:
			top = maxi(top, candidate.band)
	return top


func _within(option_id: StringName, senses: BustleSenses, reach: float) -> bool:
	for ad: BustleAdvertisement in senses.advertisements:
		if ad != null and option_id != &"" and ad.option_id == option_id:
			return ad.distance <= reach
	return false


func _stop() -> void:
	runner.cancel()
	_running_goal = &""
	_running_option = &""


func _reset() -> void:
	_stop()
	keeper = BustleChoiceKeeper.new()
	_rng.seed = seed_for(world_seed, agent_id)
