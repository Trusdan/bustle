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
## [br][br]
## A passion ([BustlePassionDef]) multiplies the XP practice gives. An agent's passions are the
## ones the host assigned, or, when it has none, the ones derived from its personality sliders (see
## [method derived_passions]). [method apply] writes the skill in use onto the agent's
## [BustleModifierSet] as [code]work.speed[/code] and [code]work.quality[/code], and holds a
## passion's thought in its mood while it does that work.
## @experimental

## The modifier source [method apply] writes under.
const SOURCE := &"skills"

## The lowest score ([method BustlePassionDef.score]) at which a passion is derived. 0.2 is one
## slider at 70 with weight 1. An experimental default.
var passion_min_score: float = 0.2
## The most passions derived for one agent. An experimental default.
var max_derived_passions: int = 1

var _defs: Dictionary[StringName, BustleSkillDef] = {}
var _passion_defs: Dictionary[StringName, BustlePassionDef] = {}
## Agent id → skill id → XP.
var _xp: Dictionary[StringName, Dictionary] = {}
## Agent id → the skill ids of its assigned passions, sorted.
var _passions: Dictionary[StringName, Array] = {}


## Starts with [param defs] and then [param passions]; invalid or repeated ones are skipped with a
## warning.
func _init(defs: Array[BustleSkillDef] = [], passions: Array[BustlePassionDef] = []) -> void:
	for def: BustleSkillDef in defs:
		if not add_def(def):
			push_warning("BustleSkills: skipped skill def %s" % (def.id if def != null else &"<null>"))
	for passion: BustlePassionDef in passions:
		if not add_passion_def(passion):
			push_warning("BustleSkills: skipped passion def %s" % (passion.skill if passion != null else &"<null>"))


## Adds [param def]. False (and no change) when it's null, invalid or its id is taken.
## @experimental
func add_def(def: BustleSkillDef) -> bool:
	if def == null or not def.is_valid() or _defs.has(def.id):
		return false
	_defs[def.id] = def
	return true


## Adds [param def], the passion for its skill. False (and no change) when it's null or invalid,
## its skill has no def, or that skill already has a passion def.
## @experimental
func add_passion_def(def: BustlePassionDef) -> bool:
	if def == null or not def.is_valid() or not _defs.has(def.skill) or _passion_defs.has(def.skill):
		return false
	_passion_defs[def.skill] = def
	return true


## The passion def for [param skill], or null.
## @experimental
func passion_def_of(skill: StringName) -> BustlePassionDef:
	return _passion_defs.get(skill)


## The def for [param skill], or null.
## @experimental
func def_of(skill: StringName) -> BustleSkillDef:
	return _defs.get(skill)


## The skill ids, sorted.
## @experimental
func skill_ids() -> Array[StringName]:
	return _sorted_keys(_defs)


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
## When the skill is one of [param id]'s passions ([method passion_of], with [param personality]
## for derived ones), the amount is multiplied by the passion's
## [member BustlePassionDef.learn_mult] first. False (and no change) for an unknown skill, an empty
## id, or an amount that is negative or not finite.
## @experimental
func add_xp(id: StringName, skill: StringName, amount: float, personality: BustlePersonality = null) -> bool:
	var def: BustleSkillDef = _defs.get(skill)
	if def == null or id == &"" or not is_finite(amount) or amount < 0.0:
		return false
	var passion := passion_of(id, skill, personality)
	if passion != null:
		amount *= passion.learn_mult
	_set_xp(id, skill, minf(xp_of(id, skill) + amount, def.max_xp()))
	return true


## Gives [param id] a passion for [param skill]. Once an agent has any assigned passion, none are
## derived for it. False (and no change) for an empty id or a skill with no passion def.
## @experimental
func assign_passion(id: StringName, skill: StringName) -> bool:
	if id == &"" or not _passion_defs.has(skill):
		return false
	var row: Array[StringName] = assigned_passions(id)
	if not row.has(skill):
		row.append(skill)
		_passions[id] = _sorted(row)
	return true


## Takes [param skill] from [param id]'s assigned passions. With none left, its passions are
## derived again.
## @experimental
func remove_passion(id: StringName, skill: StringName) -> void:
	if not _passions.has(id):
		return
	_passions[id].erase(skill)
	if _passions[id].is_empty():
		_passions.erase(id)


## [param id]'s assigned passions, sorted. Empty when it has none.
## @experimental
func assigned_passions(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_passions.get(id, []))
	return out


## The passions derived from [param personality], best first: every passion def whose
## [method BustlePassionDef.score] is at least [member passion_min_score], by score and then by
## skill id, at most [member max_derived_passions] of them. Empty for no personality. No rolls: the
## same sliders always give the same passions.
## @experimental
func derived_passions(personality: BustlePersonality) -> Array[StringName]:
	var out: Array[StringName] = []
	if personality == null:
		return out
	var scores: Dictionary[StringName, float] = {}
	for skill: StringName in _passion_defs:
		var def: BustlePassionDef = _passion_defs[skill]
		if def.sliders.is_empty():
			continue
		var value := def.score(personality)
		if value >= passion_min_score:
			scores[skill] = value
			out.append(skill)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return scores[a] > scores[b] or (scores[a] == scores[b] and String(a) < String(b)))
	return out.slice(0, maxi(max_derived_passions, 0))


## [param id]'s passions: its assigned ones, or, when it has none, the ones derived from
## [param personality].
## @experimental
func passions_of(id: StringName, personality: BustlePersonality = null) -> Array[StringName]:
	var out := assigned_passions(id)
	return out if not out.is_empty() else _sorted(derived_passions(personality))


## The passion def when [param skill] is one of [param id]'s passions, or null.
## @experimental
func passion_of(id: StringName, skill: StringName, personality: BustlePersonality = null) -> BustlePassionDef:
	return _passion_defs.get(skill) if passions_of(id, personality).has(skill) else null


## Puts [param id]'s work at [param using_skill] into effect. On [param modifiers], under source
## [constant SOURCE], it replaces anything written before with the skill's share of
## [member BustleSkillDef.speed_add] on [code]work.speed[/code] and of
## [member BustleSkillDef.quality_add] on [code]work.quality[/code] (level ÷ top level of each), and
## the same on [code]work.speed.<skill>[/code] and [code]work.quality.<skill>[/code] when the skill
## id is a valid key part. They combine with other sources (a mental state) through the modifier
## set. On [param mood] (anything with [code]set_held(def, held, details)[/code], such as a
## [code]BustleMood[/code]), it holds the thought of the passion for [param using_skill] and drops
## every other passion thought. An empty or unknown [param using_skill] clears both: the agent
## isn't working at a skill.
## @experimental
func apply(id: StringName, modifiers: BustleModifierSet, using_skill: StringName = &"", personality: BustlePersonality = null, mood: Object = null) -> void:
	var def: BustleSkillDef = _defs.get(using_skill)
	if modifiers != null:
		modifiers.remove_source(SOURCE)
		var share := level(id, using_skill) / def.max_level if def != null else 0.0
		if share > 0.0:
			_write(modifiers, &"work.speed", using_skill, def.speed_add * share)
			_write(modifiers, &"work.quality", using_skill, def.quality_add * share)
	if mood == null or not mood.has_method(&"set_held"):
		return
	var held: Resource = null
	if def != null and passion_of(id, using_skill, personality) != null:
		held = _passion_defs[using_skill].thought
	for skill: StringName in _sorted_keys(_passion_defs):
		var thought: Resource = _passion_defs[skill].thought
		if thought != null and thought != held:
			mood.call(&"set_held", thought, false, {})
	if held != null:
		mood.call(&"set_held", held, true, {"skill": String(using_skill)})


## Moves [param id]'s skills on by [param minutes] of game time: each skill above its decay floor
## loses [member BustleSkillDef.decay_per_day] levels a day, never going below the floor. Call it
## for all the time that passes, practice included; practice adds its XP on top through
## [method add_xp]. Skills at or below the floor don't change. One long call gives the same levels
## as many short ones. False (and no change) when [param minutes] is negative.
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


## The agent ids with any XP or an assigned passion, sorted.
## @experimental
func agent_ids() -> Array[StringName]:
	var out := _sorted_keys(_xp)
	for id: StringName in _passions:
		if not out.has(id):
			out.append(id)
	return _sorted(out)


## Drops everything [param id] knows and its assigned passions (for an agent that leaves the
## society).
## @experimental
func forget(id: StringName) -> void:
	_xp.erase(id)
	_passions.erase(id)


## Every agent's XP per skill and assigned passions, as plain data:
## [code]{"xp": {agent: {skill: xp}}, "passions": {agent: [skill, ...]}}[/code]. Derived passions
## aren't saved; they come from the personality, which the host saves.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in _sorted_keys(_xp):
		var row := {}
		var skills: Dictionary = _xp[id]
		var names: Array[StringName] = []
		names.assign(skills.keys())
		for skill: StringName in _sorted(names):
			row[String(skill)] = skills[skill]
		out[String(id)] = row
	var passions := {}
	for id: StringName in _sorted_keys(_passions):
		var names := PackedStringArray()
		for skill: StringName in _passions[id]:
			names.append(String(skill))
		passions[String(id)] = Array(names)
	return {"xp": out, "passions": passions}


## Restores [method export_state], replacing what's kept now. False (and nothing changes) when the
## data is malformed, names a skill with no def or a passion with no passion def, or holds XP that
## is negative, not finite or past the skill's top level. A save with no [code]passions[/code] has
## no assigned passions.
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
	var passions: Dictionary[StringName, Array] = {}
	var saved_passions: Variant = saved.get("passions", {})
	if not saved_passions is Dictionary:
		return false
	for id: Variant in saved_passions:
		var list: Variant = saved_passions[id]
		if not id is String or String(id).is_empty() or not list is Array:
			return false
		var skills: Array[StringName] = []
		for skill: Variant in list:
			if not skill is String or not _passion_defs.has(StringName(skill)) or skills.has(StringName(skill)):
				return false
			skills.append(StringName(skill))
		if not skills.is_empty():
			passions[StringName(id)] = _sorted(skills)
	_xp = restored
	_passions = passions
	return true


func _write(modifiers: BustleModifierSet, key: StringName, skill: StringName, add: float) -> void:
	modifiers.set_source(SOURCE, key, add)
	var own := StringName("%s.%s" % [key, skill])
	if BustleModifierSet.is_valid_key(own):
		modifiers.set_source(SOURCE, own, add)


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


static func _sorted_keys(map: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(map.keys())
	return _sorted(out)
