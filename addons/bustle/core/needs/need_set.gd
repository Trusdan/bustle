# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleNeedSet
extends RefCounted

## One agent's needs: each [BustleNeedDef] and its current pressure, from 0 (fine) to 1 (urgent).
## [method advance] moves every pressure on by game minutes under the conditions that hold (the
## host names them: [code]awake[/code], [code]asleep[/code], [code]alone[/code] and so on).
## Changes are linear and clamped, so one long step equals many short ones under the same
## conditions, which is what OFF_SCREEN agents need. Using an option lowers ([method relieve]) or
## raises ([method raise]) a pressure. [method fill_inputs] gives the scorer its
## [code]need.<id>[/code] inputs.
## [br][br]
## [b]The social pair.[/b] Two needs cover loners and extroverts with the same rules: one that
## rises while [code]alone[/code] (company) and one that rises while [code]crowded[/code] (too many
## people). [method social_conditions] names which holds from how many people are near and the
## agent's crowd tolerance (the [code]social.crowd_tolerance[/code] modifier, base
## [constant DEFAULT_CROWD_TOLERANCE]).
## @experimental

## No one else near.
const ALONE := &"alone"
## Some people near, no more than the agent's crowd tolerance.
const IN_COMPANY := &"in_company"
## More people near than the agent's crowd tolerance.
const CROWDED := &"crowded"
## The crowd tolerance when no modifier sets one.
const DEFAULT_CROWD_TOLERANCE := 6.0
## The modifier key for the crowd tolerance.
const CROWD_TOLERANCE_KEY := &"social.crowd_tolerance"

var _defs: Dictionary[StringName, BustleNeedDef] = {}
var _pressures: Dictionary[StringName, float] = {}


## Adds [param def] at its [member BustleNeedDef.start] pressure (a trait adding a need, for
## example). False when its id is empty or already there.
## @experimental
func add_need(def: BustleNeedDef) -> bool:
	if def == null or def.id == &"" or _defs.has(def.id):
		return false
	_defs[def.id] = def
	_pressures[def.id] = clampf(BustleNeedDef._finite(def.start), 0.0, 1.0)
	return true


## Removes need [param id].
## @experimental
func remove_need(id: StringName) -> void:
	_defs.erase(id)
	_pressures.erase(id)


## True when the agent has need [param id].
## @experimental
func has_need(id: StringName) -> bool:
	return _defs.has(id)


## The need ids, sorted.
## @experimental
func ids() -> Array[StringName]:
	var out: Array[StringName] = _defs.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Need [param id]'s pressure, or 0 when the agent doesn't have it.
## @experimental
func pressure(id: StringName) -> float:
	return _pressures.get(id, 0.0)


## Sets need [param id]'s pressure, clamped to 0..1. False for an unknown need or a non-finite value.
## @experimental
func set_pressure(id: StringName, value: float) -> bool:
	if not _defs.has(id) or not is_finite(value):
		return false
	_pressures[id] = clampf(value, 0.0, 1.0)
	return true


## Moves every need on by [param minutes] of game time under [param conditions]. Each need's rise
## is scaled by the [code]need.<id>.rate[/code] modifier in [param modifiers] (base 1). Negative or
## non-finite minutes do nothing.
## @experimental
func advance(minutes: float, conditions: Array[StringName], modifiers: BustleModifierSet = null) -> void:
	if not is_finite(minutes) or minutes <= 0.0:
		return
	var hours := minutes / 60.0
	for id: StringName in ids():
		var mult := modifiers.value(StringName("need.%s.rate" % id), 1.0) if modifiers != null else 1.0
		var rate := _defs[id].rate_under(conditions, mult)
		_pressures[id] = clampf(_pressures[id] + rate * hours, 0.0, 1.0)


## Lowers need [param id] by [param amount] (using something that meets it). Ignored for an unknown
## need or a negative or non-finite amount.
## @experimental
func relieve(id: StringName, amount: float) -> void:
	if _defs.has(id) and is_finite(amount) and amount > 0.0:
		_pressures[id] = clampf(_pressures[id] - amount, 0.0, 1.0)


## Raises need [param id] by [param amount] (a side effect). Ignored as for [method relieve].
## @experimental
func raise(id: StringName, amount: float) -> void:
	if _defs.has(id) and is_finite(amount) and amount > 0.0:
		_pressures[id] = clampf(_pressures[id] + amount, 0.0, 1.0)


## Writes each pressure into [param inputs] as [code]need.<id>[/code] (for [member BustleSenses.inputs]).
## @experimental
func fill_inputs(inputs: Dictionary[StringName, float]) -> void:
	for id: StringName in ids():
		inputs[StringName("need.%s" % id)] = _pressures[id]


## Copies each need's curve into [param config]'s [member BustleScoringConfig.need_curves]. Needs
## without a curve are left as they are.
## @experimental
func apply_curves(config: BustleScoringConfig) -> void:
	for id: StringName in ids():
		if _defs[id].curve != null:
			config.need_curves[id] = _defs[id].curve


## [constant ALONE] when no one is near, [constant CROWDED] when more than [param crowd_tolerance]
## people are, else [constant IN_COMPANY]. Use [method crowd_tolerance] for the agent's tolerance.
## @experimental
static func social_conditions(people_near: int, crowd_tolerance: float) -> Array[StringName]:
	if people_near <= 0:
		return [ALONE]
	if float(people_near) > crowd_tolerance:
		return [CROWDED]
	return [IN_COMPANY]


## The agent's crowd tolerance from [param modifiers] (base [constant DEFAULT_CROWD_TOLERANCE]).
## @experimental
static func crowd_tolerance(modifiers: BustleModifierSet) -> float:
	if modifiers == null:
		return DEFAULT_CROWD_TOLERANCE
	return modifiers.value(CROWD_TOLERANCE_KEY, DEFAULT_CROWD_TOLERANCE)


## The pressures as plain data: [code]{"pressures": {id: value}}[/code], ids sorted.
## @experimental
func export_state() -> Dictionary:
	var pressures := {}
	for id: StringName in ids():
		pressures[String(id)] = _pressures[id]
	return {"pressures": pressures}


## Restores pressures from [method export_state]. Needs the set doesn't have are skipped, and needs
## missing from [param saved] keep their pressure. False (and nothing changes) when the data is
## malformed: not a dictionary, or a pressure that isn't a finite number.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("pressures") is Dictionary:
		return false
	var pressures: Dictionary = saved["pressures"]
	var staged: Dictionary[StringName, float] = {}
	for key: Variant in pressures:
		var value: Variant = pressures[key]
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
		var id := StringName(str(key))
		if _defs.has(id):
			staged[id] = clampf(float(value), 0.0, 1.0)
	for id: StringName in staged:
		_pressures[id] = staged[id]
	return true
