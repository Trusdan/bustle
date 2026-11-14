# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleEventDef
extends Resource

## One story event, as host data: when it may fire, how it moves tension, how often, and whether
## a quest lock holds it back. The host decides what the event does when [BustleDirector] fires it.
## @experimental

## Its id, unique among a director's events.
@export var id: StringName = &""
## The kind [method BustleDirectorPort.allows] is asked about. Empty: the id.
@export var kind: StringName = &""
## Preconditions on the host's inputs, all of which must hold. Each is
## [code]{"input": key}[/code] with an optional [code]"at_least"[/code] and/or
## [code]"at_most"[/code]. With neither, the input must be above 0. A missing input fails.
@export var requires: Array[Dictionary] = []
## How it moves tension when fired: above 0 raises it, below 0 relieves it, 0 leaves it.
@export var tension: float = 0.0
## Game minutes after it fires before it may fire again. 0: no wait.
@export var cooldown_minutes: int = 0
## True: it never fires while a quest lock is held.
@export var lock_sensitive: bool = false
## Its base score.
@export var weight: float = 1.0
## Extra score from the host's inputs: input key → points per unit of that input (missing: 0).
@export var score_inputs: Dictionary[StringName, float] = {}


## The kind to ask the port about.
## @experimental
func event_kind() -> StringName:
	return kind if kind != &"" else id


## Why it can't be used, or empty: an id, finite numbers, a cooldown not below 0, and well-formed
## preconditions (each an input key with finite bounds, and no other keys).
## @experimental
func validate() -> String:
	if id == &"":
		return "an event needs an id"
	if not is_finite(tension) or not is_finite(weight) or cooldown_minutes < 0:
		return "event '%s': tension and weight must be finite and the cooldown not negative" % id
	for i: int in requires.size():
		var rule: Dictionary = requires[i]
		if str(rule.get("input", "")) == "":
			return "event '%s': precondition %d has no input" % [id, i]
		for key: Variant in rule:
			if not key in ["input", "at_least", "at_most"]:
				return "event '%s': precondition %d has an unknown key '%s'" % [id, i, key]
		for bound: String in ["at_least", "at_most"]:
			if rule.has(bound) and (not (rule[bound] is float or rule[bound] is int) or not is_finite(float(rule[bound]))):
				return "event '%s': precondition %d has a bad %s" % [id, i, bound]
	for key: StringName in score_inputs:
		if key == &"" or not is_finite(score_inputs[key]):
			return "event '%s': a score input is empty or not finite" % id
	return ""


## True when every precondition holds on [param inputs].
## @experimental
func preconditions_hold(inputs: Dictionary) -> bool:
	for rule: Dictionary in requires:
		var key := StringName(str(rule["input"]))
		if not inputs.has(key):
			return false
		var value := float(inputs[key])
		if not is_finite(value):
			return false
		if not rule.has("at_least") and not rule.has("at_most") and value <= 0.0:
			return false
		if rule.has("at_least") and value < float(rule["at_least"]):
			return false
		if rule.has("at_most") and value > float(rule["at_most"]):
			return false
	return true


## Its score on [param inputs]: [member weight] plus each score input's points.
## @experimental
func score(inputs: Dictionary) -> float:
	var out := weight
	for key: StringName in score_inputs:
		var value := float(inputs.get(key, 0.0))
		if is_finite(value):
			out += score_inputs[key] * value
	return out
