# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMentalState
extends RefCounted

## One agent's mental state: which of [member BustleMentalConfig.states] it's in, if any, and
## when that starts and ends. Everything follows from its mood, personality and circumstances;
## nothing here is a chance, a timer between episodes or a limit shared between agents.
## [br][br]
## [b]Starting.[/b] Each [method update], an agent in no state may start one:
## [br]- a low state when mood is below its break threshold
## ([member BustleMentalConfig.break_threshold] plus the [code]mental.break_threshold[/code]
## modifier). The highest score wins, ties going to the earlier state (quieter first). A state
## that needs an indulgence or a target is skipped without one. A disliked target pushes lashing
## out further.
## [br]- inspiration when mood is above [member BustleMentalConfig.inspired_above] and diligence or
## curiosity is above [member BustleMentalConfig.inspired_slider] (or a trait opts in through the
## [code]mental.inspired[/code] modifier); else high spirits when mood is above
## [member BustleMentalConfig.high_spirits_above]. Inspiration beats high spirits: an agent in
## high spirits whose mood rises far enough becomes inspired.
## [br]Nothing starts while the circumstances say the agent is locked, or while mental states are
## off ([member enabled], [method BustleMentalConfig.allowed]).
## [br][br]
## [b]Ending.[/b] A state ends when its duration is up, or sooner when mood recovers (a low state
## once mood rises to the threshold plus [member BustleMentalConfig.recover_margin]; a high one
## once mood drops below its exit line). When a low state ends, the agent gets the catharsis
## thought, an aftermath only: it can start another state as soon as its mood is below the line
## again. This part only decides and records states; what an agent does in one comes later.
## @experimental

## [param agent] entered state [param id]. [param info]: see [method active].
signal state_entered(agent: StringName, id: StringName, info: Dictionary)
## [param agent] left state [param id]: [param reason] is ended, recovered, replaced (high spirits
## giving way to inspiration) or disabled.
signal state_exited(agent: StringName, id: StringName, reason: StringName)

## The agent this is.
var agent_id: StringName
## The states and numbers.
var config: BustleMentalConfig
## False: no state starts, and an active one ends (the host's own switch).
var enabled: bool = true

var _active: Dictionary = {}


func _init(p_agent: StringName = &"", p_config: BustleMentalConfig = null) -> void:
	agent_id = p_agent
	config = p_config if p_config != null else BustleMentalConfig.new()


## The active state as [code]{id, kind, tier, since, until}[/code] (a copy), or empty.
## [code]tier[/code] is minor, major or extreme for a low state, and empty for a high one.
## @experimental
func active() -> Dictionary:
	return _active.duplicate()


## True while in a state.
## @experimental
func is_active() -> bool:
	return not _active.is_empty()


## Updates the state at minute [param now] from [param mood] (its value, modifiers and thoughts),
## [param personality] (or null: every slider 50) and [param circumstances]:
## [code]{locked, indulgence, target, target_opinion}[/code] (whether the agent is locked to a
## task, knows an indulgence, who it dislikes nearby, and its opinion of them, 0 to 100). Ends a
## state that's over (adding catharsis to [param mood] after a low one); otherwise starts one if
## it can. A state that ended this update doesn't start another until the next. Returns the
## active state.
## @experimental
func update(now: int, mood: BustleMood, personality: BustlePersonality = null, circumstances: Dictionary = {}) -> Dictionary:
	var on := enabled and BustleMentalConfig.allowed()
	var locked := bool(circumstances.get("locked", false))
	var def: BustleMentalStateDef = null
	if not _active.is_empty():
		var reason := &"disabled" if not on else _exit_reason(now, mood)
		var current := _find(StringName(_active["id"]))
		if reason == &"" and not locked and current != null and current.behaviour == BustleMentalStateDef.Behaviour.HIGH_SPIRITS:
			def = choose(mood, personality, circumstances)
			reason = &"replaced" if def != null and def.behaviour == BustleMentalStateDef.Behaviour.INSPIRED else &""
		if reason != &"":
			_end(reason, mood)
		if reason != &"replaced":
			return active()
	elif on and not locked:
		def = choose(mood, personality, circumstances)
	if def != null:
		_active = {"id": String(def.id), "kind": String(def.kind), "tier": _tier(def, mood), "since": now,
			"until": now + def.duration_minutes()}
		state_entered.emit(agent_id, def.id, active())
	return active()


## Which state [param mood], [param personality] and [param circumstances] would start now (see
## [method update]), or null. Doesn't change anything.
## @experimental
func choose(mood: BustleMood, personality: BustlePersonality = null, circumstances: Dictionary = {}) -> BustleMentalStateDef:
	var value := mood.mood
	if value < break_threshold(mood):
		var best: BustleMentalStateDef = null
		var best_score := 0.0
		for def: BustleMentalStateDef in config.states:
			if def.kind != BustleMentalStateDef.LOW or not _has_circumstance(def, circumstances):
				continue
			var score := score_of(def, personality, circumstances)
			if best == null or score > best_score:
				best = def
				best_score = score
		return best
	var inspired := _of_behaviour(BustleMentalStateDef.Behaviour.INSPIRED)
	if inspired != null and value > config.inspired_above and _opts_in(mood, personality):
		return inspired
	if value > config.high_spirits_above:
		return _of_behaviour(BustleMentalStateDef.Behaviour.HIGH_SPIRITS)
	return null


## [param def]'s score: [code]Σ weight × (slider − 50) / 100[/code], plus, for a state that needs a
## target, [code]dislike_weight × (50 − target_opinion) / 100[/code].
## @experimental
func score_of(def: BustleMentalStateDef, personality: BustlePersonality, circumstances: Dictionary = {}) -> float:
	var score := 0.0
	for slider: StringName in def.weights:
		var value := personality.slider(slider) if personality != null else 50.0
		score += def.weights[slider] * (value - 50.0) / 100.0
	if def.needs == BustleMentalStateDef.TARGET:
		score += config.dislike_weight * (50.0 - float(circumstances.get("target_opinion", 50.0))) / 100.0
	return score


## The agent's break threshold: the config's plus the [code]mental.break_threshold[/code] modifier.
## @experimental
func break_threshold(mood: BustleMood) -> float:
	var base := config.break_threshold
	var out := mood.modifiers.value(&"mental.break_threshold", base) if mood.modifiers != null else base
	return out if is_finite(out) else base


## The state as plain data.
## @experimental
func export_state() -> Dictionary:
	return {"active": active()}


## Restores [method export_state]. False (and nothing changes) when malformed or naming a state
## the config doesn't have.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("active") is Dictionary:
		return false
	var row: Dictionary = saved["active"]
	if row.is_empty():
		_active = {}
		return true
	var def := _find(StringName(str(row.get("id", ""))))
	if def == null or not row.get("id") is String or row.get("kind") != String(def.kind) \
			or not row.get("tier") in (["minor", "major", "extreme"] if def.kind == BustleMentalStateDef.LOW else [""]) \
			or not row.get("since") is int or not row.get("until") is int or int(row["until"]) <= int(row["since"]):
		return false
	_active = row.duplicate()
	return true


func _exit_reason(now: int, mood: BustleMood) -> StringName:
	if now >= int(_active["until"]):
		return &"ended"
	var value := mood.mood
	var def := _find(StringName(_active["id"]))
	match def.behaviour if def != null else -1:
		BustleMentalStateDef.Behaviour.HIGH_SPIRITS:
			return &"recovered" if value < config.high_spirits_exit else &""
		BustleMentalStateDef.Behaviour.INSPIRED:
			return &"recovered" if value < config.inspired_exit else &""
	if _active["kind"] == String(BustleMentalStateDef.LOW) and value >= break_threshold(mood) + config.recover_margin:
		return &"recovered"
	return &""


func _end(reason: StringName, mood: BustleMood) -> void:
	var was := _active
	_active = {}
	if was["kind"] == String(BustleMentalStateDef.LOW) and reason != &"disabled":
		mood.add_thought(config.catharsis_def(), {"state": was["id"]})
	state_exited.emit(agent_id, StringName(was["id"]), reason)


func _tier(def: BustleMentalStateDef, mood: BustleMood) -> String:
	if def.kind != BustleMentalStateDef.LOW:
		return ""
	var line := break_threshold(mood)
	if mood.mood < line * config.extreme_fraction:
		return "extreme"
	return "major" if mood.mood < line * config.major_fraction else "minor"


func _opts_in(mood: BustleMood, personality: BustlePersonality) -> bool:
	if mood.modifiers != null and mood.modifiers.value(&"mental.inspired", 0.0) > 0.0:
		return true
	return personality != null and (personality.slider(&"diligence") > config.inspired_slider
		or personality.slider(&"curiosity") > config.inspired_slider)


static func _has_circumstance(def: BustleMentalStateDef, circumstances: Dictionary) -> bool:
	match def.needs:
		BustleMentalStateDef.INDULGENCE:
			return bool(circumstances.get("indulgence", false))
		BustleMentalStateDef.TARGET:
			return StringName(str(circumstances.get("target", ""))) != &""
	return true


func _of_behaviour(behaviour: BustleMentalStateDef.Behaviour) -> BustleMentalStateDef:
	for def: BustleMentalStateDef in config.states:
		if def.behaviour == behaviour and def.kind == BustleMentalStateDef.HIGH:
			return def
	return null


func _find(id: StringName) -> BustleMentalStateDef:
	for def: BustleMentalStateDef in config.states:
		if def.id == id:
			return def
	return null
