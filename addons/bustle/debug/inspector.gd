# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleInspector
extends RefCounted

## Reads an agent's state for debugging, from what the brain already holds: the scorer's own
## candidates from the last tick (never recomputed), the last intent, the runner and the order
## queue. Parts that come from modules not installed yet are marked
## [code]{available: false, module: <name>}[/code] instead of being made up. Read-only.
## @experimental

## The modules the inspector marks unavailable, by field: the field → the module that will fill it.
const UNAVAILABLE := {"ring": "rings", "memory": "memory", "schedule": "schedules"}

## How many snapshots this inspector has taken (to check that a disabled overlay does no work).
var snapshots_taken: int = 0


## Everything worth seeing about agent [param agent_id] in [param society]:
## agent, area, autonomy, player control, band, goal, option, order, step, top 3 scores, order
## queue, needs inputs, social deeds and opinions, and the unavailable parts.
## [code]{missing: true}[/code] for an unknown or removed agent.
## @experimental
func snapshot(society: BustleSociety, agent_id: StringName) -> Dictionary:
	snapshots_taken += 1
	var state := society.get_agent(agent_id) if society != null else null
	if state == null:
		return {"agent": agent_id, "missing": true}
	var brain := state.brain
	var intent := brain.last_intent
	var out := {
		"agent": agent_id, "missing": false, "area": state.area,
		"autonomy": BustleBrain.Autonomy.keys()[brain.autonomy], "player_controlled": brain.player_controlled,
		"band": BustleBands.name_of(intent.band) if intent != null else "",
		"goal": intent.goal_id if intent != null else &"", "option": intent.option_id if intent != null else &"",
		"order": intent.order_id if intent != null else &"", "idle": intent.idle if intent != null else false,
		"step": _step(brain), "top": top(brain, 3), "orders": orders(brain), "needs": needs(brain),
		"social": social(society, agent_id),
	}
	for field: String in UNAVAILABLE:
		out[field] = {"available": false, "module": UNAVAILABLE[field]}
	return out


## The [param count] best of the last tick's candidates, in the scorer's order (eligible ones
## first), each with its scores and eligibility.
## @experimental
static func top(brain: BustleBrain, count: int) -> Array[Dictionary]:
	var ranked: Array[BustleCandidate] = []
	for candidate: BustleCandidate in brain.last_candidates:
		if candidate.eligible:
			ranked.append(candidate)
	for candidate: BustleCandidate in brain.last_candidates:
		if not candidate.eligible:
			ranked.append(candidate)
	var out: Array[Dictionary] = []
	for candidate: BustleCandidate in ranked.slice(0, maxi(count, 0)):
		out.append({
			"goal": candidate.goal_id, "option": candidate.option_id, "band": BustleBands.name_of(candidate.band),
			"raw": candidate.raw_score, "selection": candidate.selection_score, "eligible": candidate.eligible,
		})
	return out


## The scorer's breakdown of [param goal_id] / [param option_id] on the agent's last tick:
## its scores, eligibility and reasons. [code]{found: false}[/code] when there was no such candidate.
## @experimental
static func breakdown(brain: BustleBrain, goal_id: StringName, option_id: StringName = &"") -> Dictionary:
	for candidate: BustleCandidate in brain.last_candidates:
		if candidate.goal_id == goal_id and candidate.option_id == option_id:
			return {
				"found": true, "goal": goal_id, "option": option_id, "band": BustleBands.name_of(candidate.band),
				"raw": candidate.raw_score, "selection": candidate.selection_score,
				"eligible": candidate.eligible, "reasons": candidate.reasons.duplicate(true),
			}
	return {"found": false, "goal": goal_id, "option": option_id}


## The agent's order queue, front first: id, forced, and whether it has started.
## @experimental
static func orders(brain: BustleBrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in brain.orders.ids().size():
		var order := brain.orders.peek(i)
		out.append({"id": order.id, "forced": order.forced, "active": i == 0 and brain.orders.is_started()})
	return out


## The agent's recent deeds and its opinions of others with their reasons, from a
## [BustleSocialStore]: [code]{available: true, deeds, opinions}[/code]. With any other social port,
## [code]{available: false, module: social}[/code].
## @experimental
func social(society: BustleSociety, agent_id: StringName, count: int = 5) -> Dictionary:
	var store := society.ports.social as BustleSocialStore if society != null else null
	if store == null:
		return {"available": false, "module": "social"}
	return {"available": true, "deeds": store.deeds_of(agent_id, count), "opinions": store.opinions_of(agent_id)}


## The needs as far as the brain knows them: no needs module yet, so only the raw
## [code]need.*[/code] inputs it was given on its last tick.
## @experimental
static func needs(brain: BustleBrain) -> Dictionary:
	var inputs := {}
	if brain.last_senses != null:
		var keys: Array = brain.last_senses.inputs.keys()
		keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for key: StringName in keys:
			if String(key).begins_with("need."):
				inputs[key] = brain.last_senses.inputs[key]
	return {"available": false, "module": "needs", "inputs": inputs}


static func _step(brain: BustleBrain) -> Variant:
	var runner := brain.orders.runner if brain.last_intent != null and brain.last_intent.order_id != &"" else brain.runner
	if runner.sequence == null or runner.state == BustleSequenceRunner.State.IDLE:
		return null
	var index := runner.step_index
	var action: StringName = runner.sequence.steps[index].action if index < runner.sequence.steps.size() else &""
	return {"index": index, "action": action, "state": BustleSequenceRunner.State.keys()[runner.state]}
