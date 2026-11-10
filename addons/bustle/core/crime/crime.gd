# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCrime
extends RefCounted

## Desperate theft, in the [constant BustleBands.GUARDED] band. Nothing here is left to chance: an
## agent steals when its circumstances and its personality add up, every time they do, and never
## otherwise. There is no limit on how much crime a place sees; how often it happens follows from
## who lives there and how hard pressed they are.
## [br][br]
## [method consider] runs the guards, in order. Each must pass:
## [br]1. crime is allowed: the developer setting [constant BustleCrimeConfig.SETTING] and
## [member enabled] (neither is a game option);
## [br]2. the agent is a known agent, not in [member exempt] and not held by [member is_locked];
## [br]3. need: one of [member BustleCrimeConfig.needs] presses at least
## [member BustleCrimeConfig.min_need];
## [br]4. personality: that pressure plus [code]Σ weight × (slider − 50) / 100[/code] over
## [member BustleCrimeConfig.slider_weights] reaches [member BustleCrimeConfig.threshold] (honesty
## holds an agent back; greed and boldness push it on);
## [br]5. opportunity: an item in the agent's area, owned by someone else, not protected, that
## eases the need, where nobody else would see ([member is_observed]).
## [br]When they all pass, the agent's [code]fact.steal[/code] input is 1 ([method fill_inputs]),
## so the [code]steal[/code] goal from [method goal_defs] can run its [code]steal[/code] action,
## which moves the item through the property port and emits [signal theft]. A theft only moves an
## existing item, and never makes anyone mean to kill: what follows is for the host.
## @experimental

## [param thief] took [param item] from [param owner_id]. [param circumstances]:
## [code]{place, need, pressure, score, at}[/code]: what drove it.
signal theft(thief: StringName, owner_id: StringName, item: StringName, circumstances: Dictionary)

## The input the [code]steal[/code] goal reads.
const INPUT := &"fact.steal"

## The agents, their areas and the property port.
var society: BustleSociety
## The numbers.
var config: BustleCrimeConfig
## The host's own switch, under the developer setting.
var enabled: bool = true
## Agents that never steal (for example the player's own character, if it is an agent).
var exempt: Array[StringName] = []
## (id) → that agent's [BustlePersonality], or null (neutral sliders).
var personality_of: Callable = Callable()
## (id) → that agent's [BustleNeedSet], or null (no needs, so no theft).
var needs_of: Callable = Callable()
## (thief, place) → true when someone would see a theft there. Empty: someone would whenever
## another agent of the society is in that area.
var is_observed: Callable = Callable()
## (id) → true while the host holds that agent to a story or task. Empty: never.
var is_locked: Callable = Callable()

var _targets: Dictionary[StringName, Dictionary] = {}


func _init(p_society: BustleSociety = null, p_config: BustleCrimeConfig = null) -> void:
	society = p_society if p_society != null else BustleSociety.new()
	config = p_config if p_config != null else BustleCrimeConfig.new()


## Runs the guards for [param agent] at minute [param now] (see the class description). Returns
## what it would steal, [code]{item, owner_id, place, need, pressure, score}[/code], and remembers
## it as the agent's target; empty (and no target) when any guard fails.
## @experimental
func consider(agent: StringName, now: int) -> Dictionary:
	_targets.erase(agent)
	if not BustleCrimeConfig.crime_allowed() or not enabled or exempt.has(agent):
		return {}
	var state := society.get_agent(agent)
	if state == null or (is_locked.is_valid() and bool(is_locked.call(agent))):
		return {}
	var pressing := _pressing_need(agent)
	if pressing.is_empty():
		return {}
	var score: float = pressing["pressure"] + _temperament(agent)
	if score < config.threshold:
		return {}
	var choice := _best_item(agent, state.area, StringName(pressing["need"]))
	if choice.is_empty():
		return {}
	var target := {"item": choice["id"], "owner_id": choice["owner_id"], "place": choice["place"],
		"need": String(pressing["need"]), "pressure": pressing["pressure"], "score": score, "considered_at": now}
	_targets[agent] = target
	return target.duplicate()


## [param agent]'s current target (a copy), or empty.
## @experimental
func target_of(agent: StringName) -> Dictionary:
	return _targets[agent].duplicate() if _targets.has(agent) else {}


## Writes [constant INPUT] into [param inputs]: 1 while [param agent] has a target, else erased.
## @experimental
func fill_inputs(agent: StringName, inputs: Dictionary[StringName, float]) -> void:
	if _targets.has(agent):
		inputs[INPUT] = 1.0
	else:
		inputs.erase(INPUT)


## [param agent] takes its target at minute [param now], if every guard still passes for that same
## item: the property port moves it to the agent and [signal theft] is emitted. The target is
## cleared either way. Returns [code]{ok: true, item}[/code] or [code]{ok: false, reason}[/code].
## @experimental
func steal(agent: StringName, now: int) -> Dictionary:
	var wanted := target_of(agent)
	_targets.erase(agent)
	if wanted.is_empty():
		return {"ok": false, "reason": &"no_target"}
	var again := consider(agent, now)
	_targets.erase(agent)
	if again.is_empty() or again["item"] != wanted["item"]:
		return {"ok": false, "reason": &"guards_failed"}
	var item := StringName(again["item"])
	var owner_id := StringName(again["owner_id"])
	if not society.ports.property.transfer(item, owner_id, agent):
		return {"ok": false, "reason": &"not_moved"}
	theft.emit(agent, owner_id, item, {"place": again["place"], "need": again["need"],
		"pressure": again["pressure"], "score": again["score"], "at": now})
	return {"ok": true, "item": item}


## Forgets [param agent]'s target.
## @experimental
func clear(agent: StringName) -> void:
	_targets.erase(agent)


## The one GUARDED goal: [code]steal[/code], eligible only while [constant INPUT] is 1, running the
## [code]steal[/code] action.
## @experimental
static func goal_defs() -> Array[BustleGoalDef]:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = INPUT
	consideration.curve = curve
	var step := BustleActionStep.new()
	step.action = &"steal"
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	var goal := BustleGoalDef.new()
	goal.id = &"steal"
	goal.band = BustleBands.GUARDED
	goal.min_score = 0.5
	goal.considerations.append(consideration)
	goal.sequence = sequence
	return [goal]


# The most pressing driving need at or over the minimum: {need, pressure}, or empty.
func _pressing_need(agent: StringName) -> Dictionary:
	var found: Variant = needs_of.call(agent) if needs_of.is_valid() else null
	if not found is BustleNeedSet:
		return {}
	var needs := found as BustleNeedSet
	var best := {}
	for need: StringName in config.needs:
		if not needs.has_need(need):
			continue
		var pressure := needs.pressure(need)
		if pressure >= config.min_need and (best.is_empty() or pressure > float(best["pressure"])):
			best = {"need": need, "pressure": pressure}
	return best


func _temperament(agent: StringName) -> float:
	var found: Variant = personality_of.call(agent) if personality_of.is_valid() else null
	var total := 0.0
	for slider: StringName in config.slider_weights:
		var level := (found as BustlePersonality).slider(slider) if found is BustlePersonality else 50.0
		total += config.slider_weights[slider] * (level - 50.0) / 100.0
	return total


# The unseen, unprotected item of someone else's in [param area] that eases [param need] most
# (ties by id), or empty.
func _best_item(agent: StringName, area: StringName, need: StringName) -> Dictionary:
	if _observed(agent, area):
		return {}
	var best := {}
	for row: Dictionary in society.ports.property.items_at(area):
		var relief := float((row["relieves"] as Dictionary).get(String(need), 0.0))
		if relief <= 0.0 or bool(row["protected"]) or StringName(row["owner_id"]) == agent:
			continue
		if best.is_empty() or relief > float((best["relieves"] as Dictionary).get(String(need), 0.0)):
			best = row
	return best


func _observed(agent: StringName, area: StringName) -> bool:
	if is_observed.is_valid():
		return bool(is_observed.call(agent, area))
	for other: StringName in society.agent_ids():
		if other != agent and society.get_agent(other).area == area:
			return true
	return false
