# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSkills
extends BustleSkillSet

## The skills module: skill levels that grow with practice and fade without it. Install it as the
## society's skill set with [code]society.set_port(&"skills", skills)[/code]; a host that doesn't
## keeps the default, where everyone's level is 0.
## [br][br]
## Each agent keeps XP per skill, as a float, and its level is worked out from that XP with the
## skill's [BustleSkillDef]. XP is added only by [method add_xp] (practice the host or another
## module reports) and lost only by decay in [method advance]. Nothing is random, so the same
## practice and time always give the same levels. The skills come from the host's defs; Bustle
## has none of its own.
## @experimental

var _defs: Dictionary[StringName, BustleSkillDef] = {}
## Agent id → skill id → XP.
var _xp: Dictionary[StringName, Dictionary] = {}


## Starts with [param defs]; invalid or repeated ones are skipped with a warning.
func _init(defs: Array[BustleSkillDef] = []) -> void:
	for def: BustleSkillDef in defs:
		if not add_def(def):
			push_warning("BustleSkills: skipped skill def %s" % (def.id if def != null else &"<null>"))


## Adds [param def]. False (and no change) when it's null, invalid or its id is taken.
## @experimental
func add_def(def: BustleSkillDef) -> bool:
	if def == null or not def.is_valid() or _defs.has(def.id):
		return false
	_defs[def.id] = def
	return true


## The def for [param skill], or null.
## @experimental
func def_of(skill: StringName) -> BustleSkillDef:
	return _defs.get(skill)


## The skill ids, sorted.
## @experimental
func skill_ids() -> Array[StringName]:
	var out: Array[StringName] = _defs.keys()
	return _sorted(out)


## [param id]'s level in [param skill], from its XP: 0.0 for an unknown skill or no practice.
## @experimental
func level(id: StringName, skill: StringName) -> float:
	var def: BustleSkillDef = _defs.get(skill)
	return def.level_for(xp_of(id, skill)) if def != null else 0.0


## [param id]'s XP in [param skill]; 0.0 when it has none.
## @experimental
func xp_of(id: StringName, skill: StringName) -> float:
	return float(_xp.get(id, {}).get(skill, 0.0))


## Sets [param id]'s [param skill] to [param new_level] (clamped to [code]0..max_level[/code]) by
## setting its XP. False (and no change) for an unknown skill, an empty id or a non-finite level.
## @experimental
func set_level(id: StringName, skill: StringName, new_level: float) -> bool:
	var def: BustleSkillDef = _defs.get(skill)
	if def == null or id == &"" or not is_finite(new_level):
		return false
	_set_xp(id, skill, def.xp_for(new_level))
	return true


## Adds [param amount] XP of practice to [param id]'s [param skill], up to the XP at the top level.
## False (and no change) for an unknown skill, an empty id, or an amount that is negative or not
## finite.
## @experimental
func add_xp(id: StringName, skill: StringName, amount: float) -> bool:
	var def: BustleSkillDef = _defs.get(skill)
	if def == null or id == &"" or not is_finite(amount) or amount < 0.0:
		return false
	_set_xp(id, skill, minf(xp_of(id, skill) + amount, def.max_xp()))
	return true


## Moves [param id]'s skills on by [param minutes] of game time without practice: each skill above
## its decay floor loses [member BustleSkillDef.decay_per_day] levels a day, never going below the
## floor. Skills at or below the floor don't change. One long call gives the same levels as many
## short ones. False (and no change) when [param minutes] is negative.
## @experimental
func advance(id: StringName, minutes: int) -> bool:
	if minutes < 0:
		return false
	if minutes == 0 or not _xp.has(id):
		return true
	var days := float(minutes) / BustleClockPort.MINUTES_PER_DAY
	for skill: StringName in _xp[id].keys():
		var def: BustleSkillDef = _defs[skill]
		var now := level(id, skill)
		if def.decay_per_day <= 0.0 or now <= def.decay_floor:
			continue
		_set_xp(id, skill, def.xp_for(maxf(def.decay_floor, now - def.decay_per_day * days)))
	return true


## The agent ids with any XP, sorted.
## @experimental
func agent_ids() -> Array[StringName]:
	var out: Array[StringName] = _xp.keys()
	return _sorted(out)


## Drops everything [param id] knows (for an agent that leaves the society).
## @experimental
func forget(id: StringName) -> void:
	_xp.erase(id)


## Every agent's XP per skill, as plain data: [code]{"xp": {agent: {skill: xp}}}[/code].
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in agent_ids():
		var row := {}
		var skills: Dictionary = _xp[id]
		var names: Array[StringName] = []
		names.assign(skills.keys())
		for skill: StringName in _sorted(names):
			row[String(skill)] = skills[skill]
		out[String(id)] = row
	return {"xp": out}


## Restores [method export_state], replacing what's kept now. False (and nothing changes) when the
## data is malformed, names a skill with no def, or holds XP that is negative, not finite or past
## the skill's top level.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("xp") is Dictionary:
		return false
	var restored: Dictionary[StringName, Dictionary] = {}
	var rows: Dictionary = saved["xp"]
	for id: Variant in rows:
		if not id is String or String(id).is_empty() or not rows[id] is Dictionary:
			return false
		var row := {}
		for skill: Variant in rows[id]:
			var value: Variant = rows[id][skill]
			if not skill is String or not _defs.has(StringName(skill)):
				return false
			if not (value is float or value is int):
				return false
			var xp := float(value)
			if not is_finite(xp) or xp < 0.0 or xp > _defs[StringName(skill)].max_xp():
				return false
			if xp > 0.0:
				row[StringName(skill)] = xp
		if not row.is_empty():
			restored[StringName(id)] = row
	_xp = restored
	return true


func _set_xp(id: StringName, skill: StringName, xp: float) -> void:
	if xp <= 0.0:
		if _xp.has(id):
			_xp[id].erase(skill)
			if _xp[id].is_empty():
				_xp.erase(id)
		return
	if not _xp.has(id):
		_xp[id] = {}
	_xp[id][skill] = xp


static func _sorted(ids: Array[StringName]) -> Array[StringName]:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids
