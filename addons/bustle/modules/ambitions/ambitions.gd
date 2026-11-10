# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAmbitions
extends RefCounted

## One agent's ambition: a long-term aim, one at a time, from [member BustleAmbitionConfig.templates].
## Everything follows from the agent's personality and circumstances; nothing here is a chance or
## a limit shared between agents, and an ambition is never given up.
## [br][br]
## [b]Assigning.[/b] An agent with no ambition is given one at the next [method update] (so at
## spawn, and again after one ends): [member pin] when the host set one and it's eligible;
## otherwise the eligible template with the highest score ([code]Σ weight × (slider − 50) / 100[/code]),
## ties going to the lower id. Eligible means enabled, every [member BustleAmbitionDef.requires]
## true, every minimum slider met, not already done, and not completed within
## [member BustleAmbitionConfig.cooldown_days]. A disabled template is never assigned.
## [br][b]Completing.[/b] Once the template's progress line or done fact holds
## ([method BustleAmbitionDef.is_done]), it's completed: [signal ambition_completed], the
## [code]achieved_ambition[/code] deed (with a [member social] port), and its cooldown starts. Its
## [member BustleAmbitionDef.next] is taken when eligible; otherwise the library is scored again.
## [br][b]Moot.[/b] Once a [member BustleAmbitionDef.moot_facts] fact holds, the ambition can no
## longer happen: [signal ended_moot], with no cooldown, and the library is scored again at once.
## [br]There is no other ending: an ambition stays until it's achieved or moot, however long that takes.
## [br][br]
## [b]Bias.[/b] An ambition never acts on its own: [method boost] multiplies the scores of the goals
## its template names (for [member BustleBrain.score_boost]). Boosts never change a band, so
## nothing here outranks danger, self-care, crime or mental states, orders or duty. They're off while
## the agent is locked ([code]locked[/code] in the inputs: an order or quest is followed), while
## the template is disabled (even when it was assigned earlier), and for
## [member BustleAmbitionConfig.never_boost] goals; the ambition stays assigned all the while.
## @experimental

## [param agent] took on ambition [param id]. [param info]: see [method active].
signal ambition_started(agent: StringName, id: StringName, info: Dictionary)
## [param agent] achieved ambition [param id].
signal ambition_completed(agent: StringName, id: StringName, info: Dictionary)
## [param agent]'s ambition [param id] can no longer happen; [param fact] is what made it so.
signal ended_moot(agent: StringName, id: StringName, fact: StringName)

## The deed recorded when an ambition is achieved (the template id is the deed's target).
const DEED := &"achieved_ambition"

## The agent this is.
var agent_id: StringName
## The library and numbers.
var config: BustleAmbitionConfig
## A template the host pins on this agent's profile: taken over any score whenever it's eligible.
var pin: StringName = &""
## False: nothing is assigned and the current ambition is left as it is (the host's own switch).
var enabled: bool = true
## Optional: (id) → true while the agent is locked, checked by [method boost] at once (without it,
## only [code]locked[/code] in the last [method update]'s inputs counts, so call [method update]
## whenever a lock starts or ends).
var is_locked: Callable = Callable()
## Optional: where the achieved deed is recorded.
var social: BustleSocialPort

var _active: Dictionary = {}
var _completed: Dictionary[StringName, int] = {}
var _locked: bool = false


func _init(p_agent: StringName = &"", p_config: BustleAmbitionConfig = null) -> void:
	agent_id = p_agent
	config = p_config if p_config != null else BustleAmbitionConfig.new()


## The current ambition as [code]{id, since, progress, target, last_target}[/code] (a copy), or
## empty. [code]progress[/code] is the last value of its progress input seen; [code]target[/code] is
## who it's about right now, for a template with a [member BustleAmbitionDef.target_input] (empty
## while nobody qualifies), and [code]last_target[/code] the last one it had.
## @experimental
func active() -> Dictionary:
	return _active.duplicate()


## Updates the ambition at minute [param now] from [param personality] (or null: every slider 50)
## and [param inputs]: the circumstances, progress inputs and facts the templates name, by name,
## and [code]locked[/code].
## Completes or ends the current ambition when it's done or moot, then assigns one if there's
## none. Returns the active ambition.
## @experimental
func update(now: int, personality: BustlePersonality = null, inputs: Dictionary = {}) -> Dictionary:
	_locked = bool(inputs.get("locked", false))
	if not enabled or not BustleAmbitionConfig.allowed():
		return active()
	var after := &""
	if not _active.is_empty():
		var def := config.find(StringName(_active["id"]))
		if def == null:
			var gone := StringName(_active["id"])
			_active = {}
			ended_moot.emit(agent_id, gone, &"unknown_template")
		elif def.is_done(inputs):
			_complete(def, now)
			after = def.next
		else:
			for fact: StringName in def.moot_facts:
				if bool(inputs.get(fact, false)):
					_active = {}
					ended_moot.emit(agent_id, def.id, fact)
					break
			if not _active.is_empty():
				if def.progress_input != &"":
					_active["progress"] = float(inputs.get(def.progress_input, 0.0))
				_set_target(_target(def, inputs))
				return active()
	var chosen: BustleAmbitionDef = null
	for preferred: StringName in [after, pin]:
		var def := config.find(preferred) if preferred != &"" else null
		if def != null and is_eligible(def, now, personality, inputs):
			chosen = def
			break
	if chosen == null:
		chosen = choose(now, personality, inputs)
	if chosen != null:
		_active = {"id": String(chosen.id), "since": now,
			"progress": float(inputs.get(chosen.progress_input, 0.0)) if chosen.progress_input != &"" else 0.0,
			"target": "", "last_target": ""}
		_set_target(_target(chosen, inputs))
		ambition_started.emit(agent_id, chosen.id, active())
	return active()


## The eligible template with the highest score (ties to the lower id), or null. Ignores
## [member pin]. Changes nothing.
## @experimental
func choose(now: int, personality: BustlePersonality = null, inputs: Dictionary = {}) -> BustleAmbitionDef:
	var best: BustleAmbitionDef = null
	var best_score := 0.0
	for def: BustleAmbitionDef in config.templates:
		if not is_eligible(def, now, personality, inputs):
			continue
		var score := score_of(def, personality)
		if best == null or score > best_score or (score == best_score and String(def.id) < String(best.id)):
			best = def
			best_score = score
	return best


## True when [param def] could be assigned now: valid and enabled, every requirement true, every
## minimum slider met, not already done or moot, and not completed within the cooldown.
## @experimental
func is_eligible(def: BustleAmbitionDef, now: int, personality: BustlePersonality = null, inputs: Dictionary = {}) -> bool:
	if def == null or not def.enabled or not def.is_valid() or def.is_done(inputs) or def.is_moot(inputs):
		return false
	if _completed.has(def.id) and now < _completed[def.id] + roundi(config.cooldown_days * 1440.0):
		return false
	for need: StringName in def.requires:
		if not bool(inputs.get(need, false)):
			return false
	for slider: StringName in def.min_sliders:
		if _slider(personality, slider) < def.min_sliders[slider]:
			return false
	return true


## How much the active ambition multiplies goal [param goal_id]'s score for option
## [param option_id] (for [member BustleBrain.score_boost]): its template's boost for that goal, or 1.
## Always 1 with no ambition, while locked ([code]locked[/code] at the last update, or
## [member is_locked] now) or turned off, when the template is disabled, for a
## [member BustleAmbitionConfig.never_boost] goal, or, for a template with a target, when it has no
## target right now or the option isn't that target.
## @experimental
func boost(goal_id: StringName, option_id: StringName = &"") -> float:
	if _active.is_empty() or _locked or (is_locked.is_valid() and bool(is_locked.call(agent_id))) or not enabled or not BustleAmbitionConfig.allowed() or config.never_boost.has(goal_id):
		return 1.0
	var def := config.find(StringName(_active["id"]))
	if def == null or not def.enabled or not def.boosts.has(goal_id):
		return 1.0
	var target := str(_active.get("target", ""))
	if def.target_input != &"" and (target == "" or String(option_id) != target):
		return 1.0
	var mult := def.boosts[goal_id]
	return mult if is_finite(mult) and mult >= 0.0 else 1.0


## [param def]'s score for [param personality]: [code]Σ weight × (slider − 50) / 100[/code].
## @experimental
func score_of(def: BustleAmbitionDef, personality: BustlePersonality = null) -> float:
	var score := 0.0
	for slider: StringName in def.weights:
		score += def.weights[slider] * (_slider(personality, slider) - 50.0) / 100.0
	return score


## The ambition and when each template was last completed, as plain data.
## @experimental
func export_state() -> Dictionary:
	var completed := {}
	for id: StringName in _completed:
		completed[String(id)] = _completed[id]
	return {"active": active(), "completed": completed}


## Restores [method export_state]. False (and nothing changes) when malformed or naming a template
## the config doesn't have.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("active") is Dictionary or not saved.get("completed") is Dictionary:
		return false
	var row: Dictionary = saved["active"]
	if not row.is_empty() and (not row.get("id") is String or config.find(StringName(row["id"])) == null
			or not row.get("since") is int or not (row.get("progress") is float or row.get("progress") is int)
			or not row.get("target", "") is String or not row.get("last_target", "") is String):
		return false
	var completed: Dictionary[StringName, int] = {}
	for id: Variant in saved["completed"]:
		if not id is String or config.find(StringName(id)) == null or not saved["completed"][id] is int:
			return false
		completed[StringName(id)] = int(saved["completed"][id])
	_active = row.duplicate()
	if not _active.is_empty():
		_active["progress"] = float(_active["progress"])
		_active["target"] = str(_active.get("target", ""))
		_active["last_target"] = str(_active.get("last_target", _active["target"]))
	_completed = completed
	return true


func _complete(def: BustleAmbitionDef, now: int) -> void:
	var info := active()
	info["completed_at"] = now
	_active = {}
	_completed[def.id] = now
	if social != null:
		social.record_deed(agent_id, DEED, def.id, &"", [] as Array[Dictionary])
	ambition_completed.emit(agent_id, def.id, info)


func _set_target(target: String) -> void:
	_active["target"] = target
	if target != "":
		_active["last_target"] = target


static func _target(def: BustleAmbitionDef, inputs: Dictionary) -> String:
	return str(inputs.get(def.target_input, "")) if def.target_input != &"" else ""


static func _slider(personality: BustlePersonality, slider: StringName) -> float:
	return personality.slider(slider) if personality != null else 50.0
