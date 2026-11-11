# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLock
extends RefCounted

## A host's pin on one agent: a place to stay at, a goal (or sequence) to run, or both, under a
## [member lock_id]. [method BustleSociety.lock] holds it; while any lock is held the agent is
## locked ([method BustleSociety.is_locked]). A lock is just a lock: what it's for is the host's.
## @experimental

## How an agent is protected from being killed: [method BustleSociety.is_protected] reports it, and
## the host's combat or health honours it. Bustle never harms or heals anyone itself.
enum Protection {
	NONE, ## Never protected.
	QUEST_LOCKED, ## Protected only while it holds at least one lock.
	ESSENTIAL, ## Always protected.
}

## The lock's id, unique for its agent. Locking again with the same id replaces that pin.
var lock_id: StringName = &""
## The area to stay at, or empty.
var place: StringName = &""
## The goal to run, from the agent's library, or empty.
var goal: StringName = &""
## A sequence to run instead of a goal, or null.
var sequence: BustleActionSequence


## A lock with these pins.
## @experimental
static func make(p_id: StringName, p_place: StringName = &"", p_goal: StringName = &"",
		p_sequence: BustleActionSequence = null) -> BustleLock:
	var lock := BustleLock.new()
	lock.lock_id = p_id
	lock.place = p_place
	lock.goal = p_goal
	lock.sequence = p_sequence
	return lock


## True when it has an id and pins something.
## @experimental
func is_valid() -> bool:
	return lock_id != &"" and (place != &"" or goal != &"" or sequence != null)


## The lock as plain data: [code]{lock_id, place, goal, steps}[/code], [code]steps[/code] being
## the sequence's [code]{action, params}[/code] or null.
## @experimental
func to_dict() -> Dictionary:
	var steps: Variant = null
	if sequence != null:
		steps = []
		for step: BustleActionStep in sequence.steps:
			steps.append({"action": String(step.action), "params": step.params.duplicate(true)})
	return {"lock_id": String(lock_id), "place": String(place), "goal": String(goal), "steps": steps}


## A lock from [method to_dict]'s data, or null when it's malformed.
## @experimental
static func from_dict(saved: Variant) -> BustleLock:
	if not saved is Dictionary:
		return null
	for key: String in ["lock_id", "place", "goal"]:
		if not saved.get(key) is String:
			return null
	var sequence: BustleActionSequence = null
	var steps: Variant = saved.get("steps")
	if steps is Array:
		sequence = BustleActionSequence.new()
		for row: Variant in steps:
			if not row is Dictionary or not row.get("action") is String or not row.get("params", {}) is Dictionary:
				return null
			var step := BustleActionStep.new()
			step.action = StringName(row["action"])
			step.params = (row.get("params", {}) as Dictionary).duplicate(true)
			sequence.steps.append(step)
	elif steps != null:
		return null
	var lock := make(StringName(saved["lock_id"]), StringName(saved["place"]), StringName(saved["goal"]), sequence)
	return lock if lock.is_valid() else null
