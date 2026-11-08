# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleGoalLibrary
extends Resource

## The goals an agent chooses from.
## @experimental

## The goals. Ids must be unique; a repeated id is reported by [method problems] and skipped.
@export var goals: Array[BustleGoalDef] = []


## What is wrong with the library: empty or repeated ids, and missing curves. Empty when it is fine.
## @experimental
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for goal: BustleGoalDef in goals:
		if goal == null or goal.id == &"":
			out.append("a goal has no id")
			continue
		if seen.has(goal.id):
			out.append("goal %s is listed twice" % goal.id)
		seen[goal.id] = true
		for consideration: BustleConsideration in goal.considerations:
			if consideration == null or consideration.curve == null:
				out.append("goal %s has a consideration with no curve" % goal.id)
	return out
