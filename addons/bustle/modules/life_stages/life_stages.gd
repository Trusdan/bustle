# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStages
extends BustleLifeStagePort

## The life-stages module: each agent's age in game days, the stage that age falls in, and the
## gates that stage puts on its goals and options. Opt-in: a host makes one with
## [BustleLifeStageRules] and gives it to each brain as [member BustleBrain.life_stages]. Nothing is
## random; a stage comes from the age alone, and nobody is born or dies unless the host says so.
## [br][br]
## The host sets ages with [method set_age] or adds a newborn (or any new agent) with
## [method birth]. [method advance_to] moves every living age on with the clock, closed-form, so
## one long catch-up step gives exactly the state of many short ones. [method note_death] records a
## death: the agent stops aging, every goal and option is closed to it, and what it held (career,
## job claim, roles) is released. An agent with no age set has no stage and no gates. With rules
## that aren't valid ([method error] says why), the module stays ageless: no ages, no stages, no
## gates.
## @experimental

## The saved-state layout version. Version 1 saves (ages and stages only) still load.
const STATE_VERSION := 2

## [param id]'s stage changed from [param old_stage] to [param new_stage] (either may be empty: no
## stage). Fires once per real change, never when an age stays in the same stage. A step that
## crosses several stages fires once per stage crossed, in order.
signal stage_changed(id: StringName, old_stage: StringName, new_stage: StringName)
## [method birth] added [param id] at [param age_days].
signal born(id: StringName, age_days: float)
## [method note_death] recorded [param id]'s death, with the host's [param cause].
signal died(id: StringName, cause: String)
## A death released something [param id] held: [param kind] is [code]career[/code],
## [code]job[/code] or [code]role[/code], and [param what] the career, posting or role. Refilling it
## is the host's call.
signal vacated(id: StringName, kind: StringName, what: StringName)

## The stages and calendar. After changing them in place, call [method revalidate].
var rules: BustleLifeStageRules:
	set(value):
		rules = value
		_error = ""
		_checked = false
## The roles to vacate on a death, or null (for example [member BustlePorts.roles]).
var roles: BustleRolesPort = null
## The job board whose claims to release on a death, or null.
var jobs: BustleJobBoard = null
## The careers to end on a death, or null.
var careers: BustleCareers = null

# Each agent's age is anchor days at an anchor minute, plus the minutes since in days.
var _ages: Dictionary[StringName, float] = {}
var _anchors: Dictionary[StringName, int] = {}
var _stages: Dictionary[StringName, StringName] = {}
# id → {cause, at}
var _dead: Dictionary[StringName, Dictionary] = {}
var _now: int = 0
var _error: String = ""
var _checked: bool = false


func _init(p_rules: BustleLifeStageRules = null) -> void:
	rules = p_rules


## Why [member rules] can't be used, or empty when they can. Checked once and kept; see
## [method revalidate].
## @experimental
func error() -> String:
	if not _checked:
		_error = "no rules" if rules == null else rules.validate()
		_checked = true
	return _error


## Checks [member rules] again, after they were changed in place. Returns [method error].
## @experimental
func revalidate() -> String:
	_checked = false
	return error()


## The game minute the ages were last moved on to ([method advance_to]).
## @experimental
func now() -> int:
	return _now


## Sets [param id]'s age to [param days] game days, as of [method now], and moves it to the stage
## that age falls in, emitting [signal stage_changed] when that is a different stage. False,
## changing nothing, for an empty id, an age that is negative or not finite, a dead agent, or rules
## that aren't valid.
## @experimental
func set_age(id: StringName, days: float) -> bool:
	if id == &"" or not is_finite(days) or days < 0.0 or _dead.has(id) or error() != "":
		return false
	_ages[id] = days
	_anchors[id] = _now
	var def := rules.stage_for(days)
	_move(id, def.id if def != null else &"")
	return true


## Adds [param id] at [param days] (0: a newborn), as of [method now], emitting [signal born] and
## then [signal stage_changed] into its first stage. Returns why it was refused, or empty: an empty
## id, an agent that already has an age or has died, a bad age, an age below the first stage, or
## rules that aren't valid.
## @experimental
func birth(id: StringName, days: float = 0.0) -> String:
	if error() != "":
		return error()
	if id == &"":
		return "an agent needs an id"
	if _ages.has(id) or _dead.has(id):
		return "'%s' is already known" % id
	if not is_finite(days) or days < 0.0:
		return "'%s': age must be finite and not negative" % id
	if rules.stage_for(days) == null:
		return "'%s': age %s days is below the first stage ('%s')" % [id, days, rules.stages[0].id]
	born.emit(id, days)
	set_age(id, days)
	return ""


## Moves every living age on to game minute [param minute], in whole minutes of
## [member BustleLifeStageRules.minutes_per_day] a day. Every stage crossed fires
## [signal stage_changed] once, all agents' crossings in the order they happened (ties in id
## order). Ages come from the minute alone, so one call gives the same state and signals as many
## shorter ones. False, changing nothing, for a minute before [method now] or rules that aren't
## valid.
## @experimental
func advance_to(minute: int) -> bool:
	if minute < _now or error() != "":
		return false
	var crossings: Array[Array] = []
	for id: StringName in _sorted(_ages.keys()):
		if _dead.has(id):
			continue
		var from := _age_at(id, _now)
		var to := _age_at(id, minute)
		for stage: BustleLifeStageDef in rules.stages:
			if stage.min_days > from and stage.min_days <= to:
				crossings.append([_anchors[id] + (stage.min_days - _ages[id]) * rules.minutes_per_day, String(id), stage.id])
	crossings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	_now = minute
	for crossing: Array in crossings:
		_move(StringName(crossing[1]), crossing[2])
	for id: StringName in _sorted(_ages.keys()):
		if not _dead.has(id):
			var def := rules.stage_for(_age_at(id, minute))
			_move(id, def.id if def != null else &"")
	return true


## Records [param id]'s death from [param cause] (a host string Bustle doesn't read), at
## [method now]. Emits [signal died], then releases what it held, emitting [signal vacated] for
## each: its career ([member careers]), its job claim ([member jobs]) and its roles ([member roles],
## in name order). From then on it doesn't age, [method set_age] refuses it and every goal and
## option is closed to it. Returns why it was refused, or empty: an unknown or already dead agent,
## or an empty cause.
## @experimental
func note_death(id: StringName, cause: String) -> String:
	if not _ages.has(id):
		return "'%s' has no age" % id
	if _dead.has(id):
		return "'%s' has already died" % id
	if cause == "":
		return "'%s': a death needs a cause" % id
	_ages[id] = age_days(id)
	_anchors[id] = _now
	_dead[id] = {"cause": cause, "at": _now}
	died.emit(id, cause)
	if careers != null:
		var career := careers.career_of(id)
		if career != &"" and careers.end(id):
			vacated.emit(id, &"career", career)
	if jobs != null:
		var job := jobs.claimed_of(id)
		if job != &"" and jobs.release(job):
			vacated.emit(id, &"job", job)
	if roles != null:
		for role: String in roles.roles_of(id):
			roles.set_holder(StringName(role), &"")
			vacated.emit(id, &"role", StringName(role))
	return ""


## True when [param id]'s death has been recorded.
## @experimental
func is_dead(id: StringName) -> bool:
	return _dead.has(id)


## The cause given for [param id]'s death, or empty.
## @experimental
func cause_of(id: StringName) -> String:
	return _dead.get(id, {}).get("cause", "")


## The agents with an age who haven't died, in id order: the ones still to schedule.
## @experimental
func living_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _sorted(_ages.keys()):
		if not _dead.has(id):
			out.append(id)
	return out


## True when [param id] has an age.
## @experimental
func has_age(id: StringName) -> bool:
	return _ages.has(id)


## [param id]'s age in game days at [method now] (0 with none). A dead agent's age stays at its
## death.
## @experimental
func age_days(id: StringName) -> float:
	return _age_at(id, _now) if _ages.has(id) else 0.0


## [param id]'s age in years of [member BustleLifeStageRules.days_per_year] (0 with none or with
## rules that aren't valid).
## @experimental
func age_years(id: StringName) -> float:
	return rules.years_of(age_days(id)) if error() == "" else 0.0


## [param id]'s stage, or empty. A dead agent keeps its last stage.
## @experimental
func stage_of(id: StringName) -> StringName:
	return _stages.get(id, &"")


## False when [param id] has died or its stage blocks any of [param tags] (a goal's id and tags).
## @experimental
func allows_goal(id: StringName, tags: Array[StringName]) -> bool:
	if _dead.has(id):
		return false
	var def := _def(id)
	return def == null or not tags.any(func(tag: StringName) -> bool: return def.blocked_goal_tags.has(tag))


## False when [param id] has died or its stage blocks any of [param tags] (an option's
## advertisement tags).
## @experimental
func allows_affordance(id: StringName, tags: Array[StringName]) -> bool:
	if _dead.has(id):
		return false
	var def := _def(id)
	return def == null or not tags.any(func(tag: StringName) -> bool: return def.blocked_affordance_tags.has(tag))


## Every age, stage and death as plain data, in id order: [code]ages[/code] (at [method now]),
## [code]stages[/code], [code]anchors[/code] (each age as [code][days, minute][/code], so aging
## carries on exactly), [code]dead[/code] ([code]{cause, at}[/code]) and [code]now[/code].
## @experimental
func export_state() -> Dictionary:
	var ages := {}
	var anchors := {}
	var stages := {}
	var dead := {}
	for id: StringName in _sorted(_ages.keys()):
		ages[String(id)] = age_days(id)
		anchors[String(id)] = [_ages[id], _anchors[id]]
		if _stages.has(id):
			stages[String(id)] = String(_stages[id])
		if _dead.has(id):
			dead[String(id)] = _dead[id].duplicate()
	return {"version": STATE_VERSION, "now": _now, "ages": ages, "anchors": anchors, "stages": stages, "dead": dead}


## Restores [method export_state]'s state (or a version 1 save, with ages as of minute 0), without
## emitting anything. False, changing nothing, for another version, an age that is negative or not
## finite, a stage or death for an agent with no age, a stage id the rules don't have, a bad death
## record, or rules that aren't valid. A stage is restored as saved, even if the rules have changed
## since and it no longer matches the age; the next [method set_age] or [method advance_to] moves
## it on.
## @experimental
func import_state(saved: Dictionary) -> bool:
	var version := int(saved.get("version", -1))
	if error() != "" or version < 1 or version > STATE_VERSION \
			or not saved.get("ages") is Dictionary or not saved.get("stages") is Dictionary:
		return false
	var now := 0
	var ages: Dictionary[StringName, float] = {}
	var anchors: Dictionary[StringName, int] = {}
	var dead: Dictionary[StringName, Dictionary] = {}
	if version == 1:
		for key: Variant in saved["ages"]:
			if not _age_ok(key, saved["ages"][key]):
				return false
			ages[StringName(str(key))] = float(saved["ages"][key])
			anchors[StringName(str(key))] = 0
	else:
		if not saved.get("now") is int or int(saved["now"]) < 0 or not saved.get("anchors") is Dictionary \
				or not saved.get("dead") is Dictionary or (saved["anchors"] as Dictionary).size() != (saved["ages"] as Dictionary).size():
			return false
		now = saved["now"]
		for key: Variant in saved["ages"]:
			if not _age_ok(key, saved["ages"][key]):
				return false
		for key: Variant in saved["anchors"]:
			var anchor: Variant = saved["anchors"][key]
			if not anchor is Array or anchor.size() != 2 or not _age_ok(key, anchor[0]) or not anchor[1] is int \
					or int(anchor[1]) > now or not (saved["ages"] as Dictionary).has(key):
				return false
			ages[StringName(str(key))] = float(anchor[0])
			anchors[StringName(str(key))] = anchor[1]
		for key: Variant in saved["dead"]:
			var record: Variant = saved["dead"][key]
			if not ages.has(StringName(str(key))) or not record is Dictionary or str(record.get("cause", "")) == "" \
					or not record.get("at") is int:
				return false
			dead[StringName(str(key))] = {"cause": str(record["cause"]), "at": int(record["at"])}
	var stages: Dictionary[StringName, StringName] = {}
	for key: Variant in saved["stages"]:
		var stage := StringName(str(saved["stages"][key]))
		if not ages.has(StringName(str(key))) or rules.find(stage) == null:
			return false
		stages[StringName(str(key))] = stage
	_now = now
	_ages = ages
	_anchors = anchors
	_stages = stages
	_dead = dead
	return true


func _age_at(id: StringName, minute: int) -> float:
	if _dead.has(id):
		return _ages[id]
	return _ages[id] + float(minute - _anchors[id]) / rules.minutes_per_day


func _move(id: StringName, stage: StringName) -> void:
	var old: StringName = _stages.get(id, &"")
	if stage == old:
		return
	if stage == &"":
		_stages.erase(id)
	else:
		_stages[id] = stage
	stage_changed.emit(id, old, stage)


func _def(id: StringName) -> BustleLifeStageDef:
	if not _stages.has(id) or error() != "":
		return null
	return rules.find(_stages[id])


static func _age_ok(key: Variant, value: Variant) -> bool:
	return str(key) != "" and (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0


static func _sorted(keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(keys)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
