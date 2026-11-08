# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleChoiceKeeper
extends RefCounted

## Hysteresis around [BustleUtilityScorer]: it remembers an agent's current choice so the agent
## doesn't flicker between near-equal goals, and keeps failed goals out for a while.
##
## Each [method choose]:
## 1. Candidates whose goal is cooling down after a failure are made ineligible.
## 2. If the current choice is still eligible, its selection score gets [member momentum] (×1.15).
##    Eligibility itself uses the raw score, so momentum can't keep a goal that fell below its
##    minimum.
## 3. A candidate in a strictly higher band than the current choice always wins (it interrupts).
## 4. Otherwise, during the current goal's [member BustleGoalDef.min_commit_minutes] it is kept.
## 5. After that, it is kept while it is inside the pick window (no draw); if it falls out, the
##    scorer picks from the window as usual.
## A current choice that is no longer eligible is dropped at once.
## @experimental

## The bonus the current choice's selection score gets.
var momentum: float = 1.15
## The current goal, or empty.
var goal_id: StringName = &""
## The current option, or empty.
var option_id: StringName = &""
## The current goal's band.
var band: int = BustleBands.IDLE
## The game minute the current choice was made.
var since_minutes: int = 0
## Goal id → the game minute it may be chosen again after failing.
var cooldowns: Dictionary[StringName, int] = {}
## Goal id → the game minute it last failed.
var failed_at: Dictionary[StringName, int] = {}


## Chooses from [param candidates] (from [method BustleUtilityScorer.evaluate]) at
## [param now_minutes], remembers the choice, and returns it.
## @experimental
func choose(candidates: Array[BustleCandidate], library: BustleGoalLibrary, config: BustleScoringConfig,
		rng: RandomNumberGenerator, now_minutes: int) -> BustleCandidate:
	var current: BustleCandidate = null
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and is_cooling_down(candidate.goal_id, now_minutes):
			candidate.eligible = false
			candidate.reasons.append({"kind": &"cooling_down"})
		if candidate.goal_id == goal_id and candidate.option_id == option_id and candidate.eligible and not candidate.fallback:
			current = candidate
	var picked: BustleCandidate
	if current == null:
		picked = _pick(candidates, config, rng)
	else:
		current.selection_score = current.raw_score * momentum
		current.reasons.append({"kind": &"momentum", "value": momentum})
		BustleUtilityScorer.sort(candidates)
		var top := BustleUtilityScorer.top_band(candidates)
		var goal := library.find(goal_id)
		var committed := goal != null and now_minutes - since_minutes < goal.min_commit_minutes
		if top[0].band > current.band:
			picked = _pick(candidates, config, rng)
		elif committed or BustleUtilityScorer.pick_window(top, config.pick_window).has(current):
			picked = current
		else:
			picked = _pick(candidates, config, rng)
	if picked != current:
		goal_id = picked.goal_id
		option_id = picked.option_id
		band = picked.band
		since_minutes = now_minutes
	return picked


## Records that [param id] failed at [param now_minutes], so it cools down for its
## [member BustleGoalDef.fail_cooldown_minutes] (and at least the rest of that minute). Clears the
## current choice if it was that goal.
## @experimental
func mark_failed(id: StringName, library: BustleGoalLibrary, now_minutes: int) -> void:
	var goal := library.find(id)
	cooldowns[id] = now_minutes + maxi(goal.fail_cooldown_minutes if goal != null else 0, 0)
	failed_at[id] = now_minutes
	if goal_id == id:
		clear()


## True while [param id] may not be chosen after a failure.
## @experimental
func is_cooling_down(id: StringName, now_minutes: int) -> bool:
	return (failed_at.has(id) and failed_at[id] == now_minutes) \
			or (cooldowns.has(id) and now_minutes < cooldowns[id])


## Forgets the current choice.
## @experimental
func clear() -> void:
	goal_id = &""
	option_id = &""
	band = BustleBands.IDLE
	since_minutes = 0


## The keeper's state as plain data.
## @experimental
func export_state() -> Dictionary:
	return {
		"goal": String(goal_id), "option": String(option_id), "band": band, "since": since_minutes,
		"cooldowns": _plain(cooldowns), "failed_at": _plain(failed_at),
	}


## Restores [method export_state]'s state. Anything malformed is dropped.
## @experimental
func import_state(saved: Dictionary) -> void:
	goal_id = StringName(str(saved.get("goal", "")))
	option_id = StringName(str(saved.get("option", "")))
	band = int(saved.get("band", BustleBands.IDLE))
	since_minutes = int(saved.get("since", 0))
	cooldowns = _typed(saved.get("cooldowns", {}))
	failed_at = _typed(saved.get("failed_at", {}))


func _pick(candidates: Array[BustleCandidate], config: BustleScoringConfig, rng: RandomNumberGenerator) -> BustleCandidate:
	return BustleUtilityScorer.new().choose(candidates, config, rng)


static func _plain(source: Dictionary[StringName, int]) -> Dictionary:
	var out := {}
	for key: StringName in source:
		out[String(key)] = source[key]
	return out


static func _typed(source: Variant) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if source is Dictionary:
		for key: Variant in source:
			if typeof(source[key]) in [TYPE_INT, TYPE_FLOAT]:
				out[StringName(str(key))] = int(source[key])
	return out
