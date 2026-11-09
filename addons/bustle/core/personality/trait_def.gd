# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTraitDef
extends Resource

## A trait, as data only: a named bundle of modifiers (rates, weights, tag tastes, mood), slider
## shifts, needs and goals it adds, and permanent thoughts. No trait has code; a host or a module
## reads the modifiers by key. A trait may exclude others: an agent can't have both.
## @experimental

## Its id.
@export var id: StringName = &""
## Traits it can't be combined with (either way round).
@export var excludes: Array[StringName] = []
## Modifier key → amount added (for example [code]social.crowd_tolerance[/code] −4).
@export var adds: Dictionary[StringName, float] = {}
## Modifier key → multiplier (for example [code]need.company.rate[/code] ×0.4).
@export var mults: Dictionary[StringName, float] = {}
## Slider → points added (0 to 100 scale).
@export var slider_offsets: Dictionary[StringName, float] = {}
## Needs only agents with this trait have.
@export var needs: Array[BustleNeedDef] = []
## Goals only agents with this trait have.
@export var goals: Array[BustleGoalDef] = []
## Permanent thoughts it holds (thought definitions of the mood module, with no duration). Kept as
## plain resources so the core doesn't depend on that module. A thought the agent already holds
## from elsewhere (the same id) is left to its owner.
@export var thoughts: Array[Resource] = []


## True when it can be used: an id; no exclusion of itself; well-formed modifier keys with finite
## numbers; known sliders with finite shifts; needs and goals with ids; and valid permanent
## thoughts (no duration).
## @experimental
func is_valid() -> bool:
	if id == &"" or excludes.has(id):
		return false
	for table: Dictionary[StringName, float] in [adds, mults]:
		for key: StringName in table:
			if not BustleModifierSet.is_valid_key(key) or not is_finite(table[key]):
				return false
	for slider: StringName in slider_offsets:
		if not BustlePersonality.SLIDERS.has(slider) or not is_finite(slider_offsets[slider]):
			return false
	for need: BustleNeedDef in needs:
		if need == null or need.id == &"":
			return false
	for goal: BustleGoalDef in goals:
		if goal == null or goal.id == &"":
			return false
	for thought: Resource in thoughts:
		if thought == null or not thought.has_method(&"is_valid") or not thought.call(&"is_valid"):
			return false
		var duration: Variant = thought.get(&"duration_hours")
		if duration != null and float(duration) != 0.0:
			return false
	return true


## True when it and [param other] can't be on the same agent.
## @experimental
func clashes_with(other: BustleTraitDef) -> bool:
	return other != null and (excludes.has(other.id) or other.excludes.has(id))
