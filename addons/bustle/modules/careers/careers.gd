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
## [method update] closes whole days into a performance score ([method day_performance]: mood,
## skill and attendance) and reviews the agent after each window of
## [member BustleCareerRank.review_days] days. A window at or above the rank's
## [member BustleCareerRank.promote_if] makes a promotion due; at or below
## [member BustleCareerRank.demote_if], a demotion. [member review_hook] grants or refuses it; with
## none, it is granted. Reviews can leave the agent a thought, when it has a mood.
## [br][br]
## Agents with no career keep their job, routine and wages exactly as before. An agent whose job is
## no longer the track's role leaves the track. Nothing is random: the same mood, skill and
## attendance give the same reviews.
## @experimental

## [param id]'s career changed: [param career] at [param old_rank] became [param new_rank]. An
## empty [param old_rank] is a start; an empty [param new_rank] is the end of the career.
signal career_changed(id: StringName, career: StringName, old_rank: StringName, new_rank: StringName)
## A review found [param id] due a promotion from [param from_rank] to [param to_rank]. The hook
## decides next.
signal promotion_due(id: StringName, career: StringName, from_rank: StringName, to_rank: StringName)
## A review found [param id] due a demotion from [param from_rank] to [param to_rank].
signal demotion_due(id: StringName, career: StringName, from_rank: StringName, to_rank: StringName)
## [param id] was reviewed at game minute [param at] with [param performance]; [param outcome] is
## one of [constant PROMOTED], [constant DEMOTED], [constant GOOD_REVIEW], [constant POOR_REVIEW]
## or [constant STEADY].
signal reviewed(id: StringName, career: StringName, performance: float, outcome: StringName, at: int)

## Review outcomes, which are also the keys of [member thoughts].
const PROMOTED := &"promoted"
const DEMOTED := &"demoted"
## At or above the promotion line, but no promotion (top rank, the next rank's skill minimum, or
## the hook refused).
const GOOD_REVIEW := &"good_review"
## At or below the demotion line, but no demotion (bottom rank, or the hook refused).
const POOR_REVIEW := &"poor_review"
const STEADY := &"steady"
## The fact [method fill_inputs] sets after a granted promotion.
const PROMOTION_GRANTED := &"promotion_granted"

## The jobs and routines careers rank. Required.
var roster: BustleScheduleRoster
## The ports it reads: [code]skills[/code] for rank skill minimums and performance. Null (or a null
## port): every skill is 0.
var ports: BustlePorts
## [code]func(id, career, from_rank, to_rank, kind) -> bool[/code], where kind is
## [constant PROMOTED] or [constant DEMOTED]: true grants the change. Unset: every change is
## granted. The host's employer policy goes here.
var review_hook: Callable = Callable()
## Outcome → a timed thought (a [code]BustleThoughtDef[/code]) added to the agent's mood after a
## review with that outcome. Leave empty without the needs_mood module.
var thoughts: Dictionary[StringName, Resource] = {}
## The weights of the performance terms (see [method day_performance]). Experimental defaults.
var mood_weight: float = 0.4
var skill_weight: float = 0.3
var attendance_weight: float = 0.3
## The skill level that counts as full marks.
var skill_full: float = 10.0
## How much a late arrival counts, against 1 for on time and 0 for missed.
var late_credit: float = 0.5
## The mood term with no mood given.
var neutral_mood: float = 0.5

var _defs: Dictionary[StringName, BustleCareerDef] = {}
## Agent id → {career, rank, since, closed (last day closed), window (performances), promoted}.
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
	return minimum <= 0.0 or _skill(id, def) >= minimum


## Puts [param id] on [param career] at [param rank] from game minute [param now] (a start, or a
## move to another rank of its track). Its review window starts at the first whole day from
## [param now]. False (and no change) unless it [method can_hold] the rank.
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
	_careers[id] = {"career": career, "rank": rank, "since": now, "closed": ceili(now / 1440.0) - 1,
		"window": [] as Array[float], "promoted": false}
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


## One day's performance, from 0 to 1: the weighted mean of the terms given, each from 0 to 1.
## [param mood] always counts; [param skill] and [param attendance] only when not NAN (a track with
## no skill; a day with no career block).
## [code](mood_weight × mood + skill_weight × skill + attendance_weight × attendance) ÷ (sum of the
## weights used)[/code].
## @experimental
func day_performance(mood: float, skill: float = NAN, attendance: float = NAN) -> float:
	var total := mood_weight * clampf(mood, 0.0, 1.0)
	var weights := mood_weight
	if not is_nan(skill):
		total += skill_weight * clampf(skill, 0.0, 1.0)
		weights += skill_weight
	if not is_nan(attendance):
		total += attendance_weight * clampf(attendance, 0.0, 1.0)
		weights += attendance_weight
	return total / weights if weights > 0.0 else 0.0


## The mean performance of [param id]'s current review window so far, or NAN with no closed day.
## @experimental
func performance(id: StringName) -> float:
	var window: Array = _careers.get(id, {}).get("window", [])
	if window.is_empty():
		return NAN
	var total := 0.0
	for value: float in window:
		total += value
	return total / window.size()


## Brings [param id]'s career up to game minute [param now]. Each whole game day whose career
## blocks have all ended is closed into a [method day_performance] from [param mood] (anything with
## a [code]mood[/code] number, such as a [code]BustleMood[/code]; null: [member neutral_mood]), the
## skill level now and that day's attendance at the career block. Each time a window has
## [member BustleCareerRank.review_days] days, the agent is reviewed at the end of the last day,
## and the next window starts. Call it at least every few game days (the schedule keeps 7 days of
## attendance). Given the same mood, skill and attendance, one long call gives the same reviews as
## many short ones. Returns one [code]{at, performance, outcome, rank}[/code] per review.
## @experimental
func update(id: StringName, now: int, mood: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var schedule := roster.schedule_of(id)
	while _careers.has(id) and schedule != null:
		var info: Dictionary = _careers[id]
		var def: BustleCareerDef = _defs[info["career"]]
		var day: int = int(info["closed"]) + 1
		var closes := (day + 1) * 1440
		var blocks := 0
		for occurrence: Dictionary in schedule.occurrences(day):
			if (occurrence["block"] as BustleScheduleBlock).activity == def.activity:
				closes = maxi(closes, int(occurrence["end"]))
				blocks += 1
		if now < closes:
			break
		var attendance := NAN
		if blocks > 0:
			var seen := schedule.report(day, closes, &"", def.activity)
			attendance = (float(seen["on_time"]) + late_credit * float(seen["late"])) / blocks
		var skill := NAN
		if def.skill != &"":
			skill = _skill(id, def) / skill_full if skill_full > 0.0 else 1.0
		info["closed"] = day
		(info["window"] as Array).append(day_performance(_mood(mood), skill, attendance))
		var rank: BustleCareerRank = def.ranks[def.rank_index(info["rank"])]
		if (info["window"] as Array).size() >= rank.review_days:
			out.append(_review(id, (day + 1) * 1440, mood))
	return out


## Sets [constant PROMOTION_GRANTED] to true in [param inputs] (an ambition's facts) from a granted
## promotion of [param id] until its next review, so an ambition to be promoted completes.
## @experimental
func fill_inputs(id: StringName, inputs: Dictionary) -> void:
	if bool(_careers.get(id, {}).get("promoted", false)):
		inputs[PROMOTION_GRANTED] = true


## Every career as plain data:
## [code]{agent: {career, rank, since, closed, window, promoted}}[/code].
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in agent_ids():
		var info: Dictionary = _careers[id]
		out[String(id)] = {"career": String(info["career"]), "rank": String(info["rank"]), "since": info["since"],
			"closed": info["closed"], "window": (info["window"] as Array).duplicate(), "promoted": info["promoted"]}
	return out


## Restores [method export_state], replacing every career. False (and nothing changes) when the data
## is malformed or names a track or rank there's no def for. A save without the review clock
## ([code]closed[/code], [code]window[/code], [code]promoted[/code]) starts it afresh from
## [code]since[/code]. It doesn't check who holds which role: restore the roles first.
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
		if def == null or not row.get("rank") is String or def.rank_index(StringName(row["rank"])) < 0 or not _is_int(since):
			return false
		var closed: Variant = row.get("closed", ceili(float(since) / 1440.0) - 1)
		var window: Variant = row.get("window", [])
		if not _is_int(closed) or not window is Array or not row.get("promoted", false) is bool:
			return false
		var values: Array[float] = []
		for value: Variant in window:
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
				return false
			values.append(float(value))
		restored[StringName(id)] = {"career": def.id, "rank": StringName(row["rank"]), "since": int(since),
			"closed": int(closed), "window": values, "promoted": row.get("promoted", false)}
	for id: StringName in _careers:
		var schedule := roster.schedule_of(id)
		if schedule != null:
			schedule.wages.erase(_defs[_careers[id]["career"]].activity)
	_careers = restored
	for id: StringName in _careers:
		_apply(id)
	return true


func _review(id: StringName, at: int, mood: Object) -> Dictionary:
	var info: Dictionary = _careers[id]
	var def: BustleCareerDef = _defs[info["career"]]
	var index := def.rank_index(info["rank"])
	var rank: BustleCareerRank = def.ranks[index]
	var value := performance(id)
	info["window"] = [] as Array[float]
	info["promoted"] = false
	var outcome := STEADY
	if value >= rank.promote_if:
		outcome = GOOD_REVIEW
		var next := def.ranks[index + 1].id if index + 1 < def.ranks.size() else &""
		if next != &"" and can_hold(id, def.id, next) and _decide(id, def, rank.id, next, PROMOTED):
			_set_rank(id, def, rank.id, next, at, info["closed"])
			_careers[id]["promoted"] = true
			outcome = PROMOTED
	elif value <= rank.demote_if:
		outcome = POOR_REVIEW
		if index > 0 and _decide(id, def, rank.id, def.ranks[index - 1].id, DEMOTED):
			_set_rank(id, def, rank.id, def.ranks[index - 1].id, at, info["closed"])
			outcome = DEMOTED
	reviewed.emit(id, def.id, value, outcome, at)
	var thought: Resource = thoughts.get(outcome)
	if thought != null and mood != null and mood.has_method(&"add_thought"):
		mood.call(&"add_thought", thought, {"career": String(def.id), "rank": String(rank_of(id))})
	return {"at": at, "performance": value, "outcome": outcome, "rank": rank_of(id)}


# A granted change of rank at minute [param at]: the new window starts the next day.
func _set_rank(id: StringName, def: BustleCareerDef, from_rank: StringName, to_rank: StringName, at: int, closed: int) -> void:
	_careers[id] = {"career": def.id, "rank": to_rank, "since": at, "closed": closed,
		"window": [] as Array[float], "promoted": false}
	_apply(id)
	career_changed.emit(id, def.id, from_rank, to_rank)


# Emits the due signal and asks the hook; with no hook, true.
func _decide(id: StringName, def: BustleCareerDef, from_rank: StringName, to_rank: StringName, kind: StringName) -> bool:
	if kind == PROMOTED:
		promotion_due.emit(id, def.id, from_rank, to_rank)
	else:
		demotion_due.emit(id, def.id, from_rank, to_rank)
	if not review_hook.is_valid():
		return true
	return bool(review_hook.call(id, def.id, from_rank, to_rank, kind))


func _skill(id: StringName, def: BustleCareerDef) -> float:
	var skills: BustleSkillSet = ports.skills if ports != null else null
	return skills.level(id, def.skill) if skills != null and def.skill != &"" else 0.0


func _mood(mood: Object) -> float:
	if mood == null or not (mood.get(&"mood") is float or mood.get(&"mood") is int):
		return neutral_mood
	var bounds := Vector2(0.0, 100.0)
	if mood.has_method(&"mood_range"):
		bounds = mood.call(&"mood_range")
	return (float(mood.get(&"mood")) - bounds.x) / (bounds.y - bounds.x) if bounds.y > bounds.x else neutral_mood


# Puts the rank's wage on the agent's career block.
func _apply(id: StringName) -> void:
	var info: Dictionary = _careers.get(id, {})
	var schedule := roster.schedule_of(id)
	if info.is_empty() or schedule == null:
		return
	var def: BustleCareerDef = _defs[info["career"]]
	schedule.wages[def.activity] = def.ranks[def.rank_index(info["rank"])].wage


# Ends the career of an agent whose job is no longer the track's role.
func _check(id: StringName) -> void:
	var career := career_of(id)
	if career != &"" and roster.job_of(id) != _defs[career].role:
		end(id)


func _on_holder_changed(_role: StringName, old: StringName, new: StringName) -> void:
	for id: StringName in [old, new]:
		_check(id)


func _on_schedule_changed(id: StringName, _old: BustleScheduleDef, _new: BustleScheduleDef) -> void:
	_check(id)
	_apply(id)


static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
