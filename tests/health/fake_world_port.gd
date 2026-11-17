# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends BustleWorldPort

## A host world port for tests: each agent's area is set directly ([member areas]), each area has a
## position (its name as a place), and places are set with [method BustleWorldPort.set_place].

var areas: Dictionary = {}


func area_of(id: StringName) -> StringName:
	return areas.get(id, &"square")
