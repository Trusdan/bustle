# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCareers
extends RefCounted

## The careers module: ranks on standing jobs. A career is not a second job: it is the agent's
## standing job (a role with a routine, see [BustleScheduleRoster]) held at a rank of a
## [BustleCareerDef]. The rank sets what the track's career block pays, through the agent's
## schedule ([member BustleSchedule.wages]), so it is paid at the block's end like any shift and
## only if attended. While an agent attends an off-site career block it is away ([method is_away]),
## and the host takes it out of the world until the block ends.
## [br][br]
## Agents with no career keep their job, routine and wages exactly as before. An agent that loses
## the track's role leaves the track. Nothing is random.
## @experimental

## [param id]'s career changed: [param career] at [param old_rank] became [param new_rank]. An
## empty [param old_rank] is a start; an empty [param new_rank] is the end of the career.
signal career_changed(id: StringName, career: StringName, old_rank: StringName, new_rank: StringName)

## The jobs and routines careers rank. Required.
var roster: BustleScheduleRoster
## The ports it reads: [code]skills[/code] for rank skill minimums. Null (or a null port): every
## skill is 0.
var ports: BustlePorts

var _defs: Dictionary[StringName, BustleCareerDef] = {}
## Agent id → {career, rank, since}.
var _careers: Dictionary[StringName, Dictionary] = {}


## Starts with [param defs] (invalid or repeated ones are skipped with a warning) on
## [param p_roster], reading skills from [param p_ports].
func _init(defs: Array[BustleCareerDef] = [], p_roster: BustleScheduleRoster = null, p_ports: BustlePorts = null) -> void:
	roster = p_roster if p_roster != null else BustleScheduleRoster.new()
	ports = p_ports
	for def: BustleCareerDef in defs:
		if not add_def(def):
			push_warning("BustleCareers: skipped career def %s" % (def.id if def != null else &"<null>"))
	roster.roles.holder_changed.connect(_on_holder_changed)
	roster.schedule_changed.connect(_on_schedule_changed)


## Adds [param def]. False (and no change) when it's null, invalid or its id is taken.
## @experimental
func add_def(def: BustleCareerDef) -> bool:
	if def == null or not def.is_valid() or _defs.has(def.id):
		return false
	_defs[def.id] = def
	return true


## The track [param career], or null.
## @experimental
func def_of(career: StringName) -> BustleCareerDef:
	return _defs.get(career)


## True when [param id] could hold [param rank] of [param career]: the track's role is its job and
## it has the rank's skill minimum.
## @experimental
func can_hold(id: StringName, career: StringName, rank: StringName) -> bool:
	var def: BustleCareerDef = _defs.get(career)
	if def == null or id == &"" or roster.job_of(id) != def.role:
		return false
	var index := def.rank_index(rank)
	if index < 0:
		return false
	var minimum := def.ranks[index].min_skill
	var skills: BustleSkillSet = ports.skills if ports != null else null
	return minimum <= 0.0 or (skills != null and skills.level(id, def.skill) >= minimum)


## Puts [param id] on [param career] at [param rank] from game minute [param now] (a start, or a
## move to another rank of its track). False (and no change) unless it [method can_hold] the rank.
## @experimental
func assign(id: StringName, career: StringName, rank: StringName, now: int) -> bool:
	if not can_hold(id, career, rank):
		return false
	var old: Dictionary = _careers.get(id, {})
	if not old.is_empty() and old["career"] != career:
		end(id)
		old = {}
	var old_rank: StringName = old.get("rank", &"")
	if old_rank == rank:
		return true
	_careers[id] = {"career": career, "rank": rank, "since": now}
	_apply(id)
	career_changed.emit(id, career, old_rank, rank)
	return true


## Takes [param id] off its career. Its job stays; its career block pays the block's own wage again.
## False when it has none.
## @experimental
func end(id: StringName) -> bool:
	var info: Dictionary = _careers.get(id, {})
	if info.is_empty():
		return false
	_careers.erase(id)
	var schedule := roster.schedule_of(id)
	if schedule != null:
		schedule.wages.erase(_defs[info["career"]].activity)
	career_changed.emit(id, info["career"], info["rank"], &"")
	return true


## [param id]'s career, or empty.
## @experimental
func career_of(id: StringName) -> StringName:
	return _careers.get(id, {}).get("career", &"")


## [param id]'s rank, or empty.
## @experimental
func rank_of(id: StringName) -> StringName:
	return _careers.get(id, {}).get("rank", &"")


## The game minute [param id] took its rank, or -1.
## @experimental
func since_of(id: StringName) -> int:
	return _careers.get(id, {}).get("since", -1)


## The agents with a career, sorted.
## @experimental
func agent_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_careers.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## True while [param id] is off site at minute [param now]: it has a career whose track is off
## site, its current block is the career block, and it has attended it. It is back when the block
## ends.
## @experimental
func is_away(id: StringName, now: int, season: StringName = &"") -> bool:
	var career := career_of(id)
	var schedule := roster.schedule_of(id)
	if career == &"" or schedule == null or not _defs[career].off_site:
		return false
	var current := schedule.block_at(now, season)
	return not current.is_empty() and (current["block"] as BustleScheduleBlock).activity == _defs[career].activity \
			and schedule.attended_now(now, season)


## Every career as plain data: [code]{agent: {career, rank, since}}[/code].
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in agent_ids():
		var info: Dictionary = _careers[id]
		out[String(id)] = {"career": String(info["career"]), "rank": String(info["rank"]), "since": info["since"]}
	return out


## Restores [method export_state], replacing every career. False (and nothing changes) when the data
## is malformed or names a track or rank there's no def for. It doesn't check who holds which role:
## restore the roles first.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var restored: Dictionary[StringName, Dictionary] = {}
	for id: Variant in saved:
		var row: Variant = saved[id]
		if not id is String or String(id).is_empty() or not row is Dictionary:
			return false
		var def: BustleCareerDef = _defs.get(StringName(row.get("career", "")))
		var since: Variant = row.get("since")
		if def == null or not row.get("rank") is String or def.rank_index(StringName(row["rank"])) < 0 \
				or not (since is int or (since is float and is_finite(since) and since == floorf(since))):
			return false
		restored[StringName(id)] = {"career": def.id, "rank": StringName(row["rank"]), "since": int(since)}
	for id: StringName in _careers:
		var schedule := roster.schedule_of(id)
		if schedule != null:
			schedule.wages.erase(_defs[_careers[id]["career"]].activity)
	_careers = restored
	for id: StringName in _careers:
		_apply(id)
	return true


# Puts the rank's wage on the agent's career block.
func _apply(id: StringName) -> void:
	var info: Dictionary = _careers.get(id, {})
	var schedule := roster.schedule_of(id)
	if info.is_empty() or schedule == null:
		return
	var def: BustleCareerDef = _defs[info["career"]]
	schedule.wages[def.activity] = def.ranks[def.rank_index(info["rank"])].wage


func _on_holder_changed(role: StringName, old: StringName, _new: StringName) -> void:
	var career := career_of(old)
	if career != &"" and _defs[career].role == role:
		end(old)


func _on_schedule_changed(id: StringName, _old: BustleScheduleDef, _new: BustleScheduleDef) -> void:
	_apply(id)
