# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends BustleHealthPort

## A host health port for tests: readings are set directly, per agent. It stores readings only;
## the module under test stores nothing.

var capacities: Dictionary = {}
var pains: Dictionary = {}
var care_needed: Dictionary = {}
var contagious: Array[StringName] = []
var downed: Array[StringName] = []
var tags: Dictionary = {}


func capacity(id: StringName, name: StringName) -> float:
	return capacities.get(id, {}).get(name, 1.0)


func pain(id: StringName) -> float:
	return pains.get(id, 0.0)


func needs_care(id: StringName) -> float:
	return care_needed.get(id, 0.0)


func is_contagious(id: StringName) -> bool:
	return contagious.has(id)


func is_incapacitated(id: StringName) -> bool:
	return downed.has(id)


func visible_tags(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(tags.get(id, []))
	return out
