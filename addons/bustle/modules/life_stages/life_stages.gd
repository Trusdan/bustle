# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStages
extends BustleLifeStagePort

## The life-stages module: each agent's age in game days, the stage that age falls in, and the
## gates that stage puts on its goals and options. Opt-in: a host makes one with
## [BustleLifeStageRules] and gives it to each brain as [member BustleBrain.life_stages]. Nothing is
## random; a stage comes from the age alone.
## [br][br]
## The host sets ages with [method set_age]. An agent with no age set has no stage and no gates.
## With rules that aren't valid ([method error] says why), the module stays ageless: no ages, no
## stages, no gates.
## @experimental

## The saved-state layout version.
const STATE_VERSION := 1

## [param id]'s stage changed from [param old_stage] to [param new_stage] (either may be empty: no
## stage). Fires once per real change, never when an age stays in the same stage.
signal stage_changed(id: StringName, old_stage: StringName, new_stage: StringName)

## The stages and calendar.
var rules: BustleLifeStageRules

var _ages: Dictionary[StringName, float] = {}
var _stages: Dictionary[StringName, StringName] = {}


func _init(p_rules: BustleLifeStageRules = null) -> void:
	rules = p_rules


## Why [member rules] can't be used, or empty when they can.
## @experimental
func error() -> String:
	return "no rules" if rules == null else rules.validate()


## Sets [param id]'s age to [param days] game days and moves it to the stage that age falls in,
## emitting [signal stage_changed] when that is a different stage. False, changing nothing, for an
## empty id, an age that is negative or not finite, or rules that aren't valid.
## @experimental
func set_age(id: StringName, days: float) -> bool:
	if id == &"" or not is_finite(days) or days < 0.0 or error() != "":
		return false
	_ages[id] = days
	var def := rules.stage_for(days)
	var stage: StringName = def.id if def != null else &""
	var old: StringName = _stages.get(id, &"")
	if stage == old:
		return true
	if stage == &"":
		_stages.erase(id)
	else:
		_stages[id] = stage
	stage_changed.emit(id, old, stage)
	return true


## True when [param id] has an age.
## @experimental
func has_age(id: StringName) -> bool:
	return _ages.has(id)


## [param id]'s age in game days (0 with none).
## @experimental
func age_days(id: StringName) -> float:
	return _ages.get(id, 0.0)


## [param id]'s age in years of [member BustleLifeStageRules.days_per_year] (0 with none or with
## rules that aren't valid).
## @experimental
func age_years(id: StringName) -> float:
	return rules.years_of(age_days(id)) if error() == "" else 0.0


## [param id]'s stage, or empty.
## @experimental
func stage_of(id: StringName) -> StringName:
	return _stages.get(id, &"")


## False when [param id]'s stage blocks any of [param tags] (a goal's id and tags).
## @experimental
func allows_goal(id: StringName, tags: Array[StringName]) -> bool:
	var def := _def(id)
	return def == null or not tags.any(func(tag: StringName) -> bool: return def.blocked_goal_tags.has(tag))


## False when [param id]'s stage blocks any of [param tags] (an option's advertisement tags).
## @experimental
func allows_affordance(id: StringName, tags: Array[StringName]) -> bool:
	var def := _def(id)
	return def == null or not tags.any(func(tag: StringName) -> bool: return def.blocked_affordance_tags.has(tag))


## Every age and stage as plain data, in id order.
## @experimental
func export_state() -> Dictionary:
	var ids: Array[StringName] = []
	ids.assign(_ages.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var ages := {}
	var stages := {}
	for id: StringName in ids:
		ages[String(id)] = _ages[id]
		if _stages.has(id):
			stages[String(id)] = String(_stages[id])
	return {"version": STATE_VERSION, "ages": ages, "stages": stages}


## Restores [method export_state]'s state, without emitting [signal stage_changed]. False, changing
## nothing, for another version, an age that is negative or not finite, a stage for an agent with no
## age, a stage id the rules don't have, or rules that aren't valid. A stage is restored as saved;
## the next [method set_age] moves it on if the rules have changed since.
## @experimental
func import_state(saved: Dictionary) -> bool:
	if error() != "" or int(saved.get("version", -1)) != STATE_VERSION \
			or not saved.get("ages") is Dictionary or not saved.get("stages") is Dictionary:
		return false
	var ages: Dictionary[StringName, float] = {}
	for key: Variant in saved["ages"]:
		var value: Variant = saved["ages"][key]
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 \
				or str(key) == "":
			return false
		ages[StringName(str(key))] = float(value)
	var stages: Dictionary[StringName, StringName] = {}
	for key: Variant in saved["stages"]:
		var stage := StringName(str(saved["stages"][key]))
		if not ages.has(StringName(str(key))) or rules.find(stage) == null:
			return false
		stages[StringName(str(key))] = stage
	_ages = ages
	_stages = stages
	return true


func _def(id: StringName) -> BustleLifeStageDef:
	if not _stages.has(id) or error() != "":
		return null
	return rules.find(_stages[id])
