# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePersonality
extends RefCounted

## One agent's personality: 8 sliders every agent has, from 0 to 100 (50 is average), and up to
## [constant MAX_TRAITS] traits on top. Sliders reach the scorer as the inputs
## [code]trait.<slider>[/code], from 0 to 1. Traits are data ([BustleTraitDef]); [method apply]
## puts them into effect: their modifiers into a [BustleModifierSet] (one source per trait), their
## needs into a [BustleNeedSet], their goals into a [BustleGoalLibrary] and their permanent thoughts
## into a mood (anything with [code]set_held(def, held, details)[/code]). Applying again after a
## change adds what is new and takes away what a removed trait brought, and nothing else.
## @experimental

## The sliders.
const SLIDERS: Array[StringName] = [&"sociability", &"diligence", &"boldness", &"curiosity",
	&"kindness", &"cheer", &"calm", &"thrift"]
## The most traits an agent can have.
const MAX_TRAITS := 3
## [method can_add]'s answers.
const OK := &""
const INVALID := &"invalid"
const ALREADY := &"already"
const EXCLUDED := &"excluded"
const FULL := &"full"

var _sliders: Dictionary[StringName, float] = {}
var _traits: Array[BustleTraitDef] = []
# What the last apply put in place, to undo exactly that.
var _applied_sources: Array[StringName] = []
var _applied_needs: Array[StringName] = []
var _applied_goals: Array[BustleGoalDef] = []
var _applied_thoughts: Array[Resource] = []


## Slider [param name]'s value with every trait's shift, clamped to 0..100. 50 for unset.
## @experimental
func slider(name: StringName) -> float:
	var value: float = _sliders.get(name, 50.0)
	for def: BustleTraitDef in _traits:
		value += def.slider_offsets.get(name, 0.0)
	return clampf(value, 0.0, 100.0)


## Sets slider [param name] (clamped to 0..100). False for an unknown slider or a value that
## isn't finite.
## @experimental
func set_slider(name: StringName, value: float) -> bool:
	if not SLIDERS.has(name) or not is_finite(value):
		return false
	_sliders[name] = clampf(value, 0.0, 100.0)
	return true


## The traits, in the order they were added.
## @experimental
func traits() -> Array[BustleTraitDef]:
	return _traits.duplicate()


## True when the agent has trait [param id].
## @experimental
func has_trait(id: StringName) -> bool:
	return _find(id) != null


## Whether [param def] could be added: [constant OK], or why not ([constant INVALID],
## [constant ALREADY], [constant EXCLUDED] by a trait the agent has, or [constant FULL]).
## @experimental
func can_add(def: BustleTraitDef) -> StringName:
	if def == null or not def.is_valid():
		return INVALID
	if has_trait(def.id):
		return ALREADY
	for other: BustleTraitDef in _traits:
		if def.clashes_with(other):
			return EXCLUDED
	if _traits.size() >= MAX_TRAITS:
		return FULL
	return OK


## Adds [param def] when [method can_add] allows it. Call [method apply] to put it into effect.
## @experimental
func add_trait(def: BustleTraitDef) -> StringName:
	var verdict := can_add(def)
	if verdict == OK:
		_traits.append(def)
	return verdict


## Removes trait [param id]. Call [method apply] to take its effects away.
## @experimental
func remove_trait(id: StringName) -> void:
	var def := _find(id)
	if def != null:
		_traits.erase(def)


## Writes every slider into [param inputs] as [code]trait.<slider>[/code], from 0 to 1.
## @experimental
func fill_inputs(inputs: Dictionary[StringName, float]) -> void:
	for name: StringName in SLIDERS:
		inputs[StringName("trait.%s" % name)] = slider(name) / 100.0


## Puts the traits into effect (see the class description). Any argument may be null to skip it.
## @experimental
func apply(modifiers: BustleModifierSet, needs: BustleNeedSet = null, library: BustleGoalLibrary = null, mood: Object = null) -> void:
	if modifiers != null:
		for source: StringName in _applied_sources:
			modifiers.remove_source(source)
		_applied_sources.clear()
		for def: BustleTraitDef in _traits:
			var source := StringName("trait_%s" % def.id)
			var keys: Array[StringName] = def.adds.keys()
			for key: StringName in def.mults:
				if not keys.has(key):
					keys.append(key)
			for key: StringName in keys:
				modifiers.set_source(source, key, def.adds.get(key, 0.0), def.mults.get(key, 1.0))
			_applied_sources.append(source)
	if needs != null:
		var wanted: Array[StringName] = []
		for def: BustleTraitDef in _traits:
			for need: BustleNeedDef in def.needs:
				if not wanted.has(need.id):
					wanted.append(need.id)
					if not needs.has_need(need.id):
						needs.add_need(need)
		for id: StringName in _applied_needs:
			if not wanted.has(id):
				needs.remove_need(id)
		_applied_needs = wanted
	if library != null:
		var goals: Array[BustleGoalDef] = []
		for def: BustleTraitDef in _traits:
			goals.append_array(def.goals)
		for goal: BustleGoalDef in _applied_goals:
			if not goals.has(goal):
				library.goals.erase(goal)
		for goal: BustleGoalDef in goals:
			if not library.goals.has(goal):
				library.goals.append(goal)
		_applied_goals = goals
	if mood != null and mood.has_method(&"set_held"):
		var held: Array[Resource] = []
		for def: BustleTraitDef in _traits:
			for thought: Resource in def.thoughts:
				held.append(thought)
				mood.call(&"set_held", thought, true, {"trait": String(def.id)})
		for thought: Resource in _applied_thoughts:
			if not held.has(thought):
				mood.call(&"set_held", thought, false, {})
		_applied_thoughts = held


## The sliders and trait ids as plain data.
## @experimental
func export_state() -> Dictionary:
	var sliders := {}
	for name: StringName in SLIDERS:
		if _sliders.has(name):
			sliders[String(name)] = _sliders[name]
	var ids: Array = []
	for def: BustleTraitDef in _traits:
		ids.append(String(def.id))
	return {"sliders": sliders, "traits": ids}


## Restores [method export_state], finding traits by id in [param defs]. False (and nothing
## changes) when malformed, a trait is unknown, or the traits couldn't be combined. Call
## [method apply] afterwards.
## @experimental
func import_state(saved: Variant, defs: Array[BustleTraitDef]) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("sliders") is Dictionary \
			or not (saved as Dictionary).get("traits") is Array:
		return false
	var staged := BustlePersonality.new()
	var sliders: Dictionary = saved["sliders"]
	for key: Variant in sliders:
		var value: Variant = sliders[key]
		if not key is String or not (value is float or value is int) or not staged.set_slider(StringName(key), float(value)):
			return false
	for id: Variant in saved["traits"]:
		var found: BustleTraitDef = null
		for def: BustleTraitDef in defs:
			if def != null and String(def.id) == str(id) and id is String:
				found = def
		if found == null or staged.add_trait(found) != OK:
			return false
	_sliders = staged._sliders
	_traits = staged._traits
	return true


func _find(id: StringName) -> BustleTraitDef:
	for def: BustleTraitDef in _traits:
		if def.id == id:
			return def
	return null
