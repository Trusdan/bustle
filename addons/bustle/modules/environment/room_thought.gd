# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRoomThought
extends Resource

## One environment thought rule, as data: while an agent is in a room whose [member score] is at
## least [member at_least] (a high rule) or at most [member at_most] (a low rule), it holds
## [member thought]. [BustleRoomThoughts] reads it. Bustle ships none; the thresholds are the host's.
## @experimental

## The room score it reads, one of [constant BustleEnvironmentPort.SCORES].
@export var score: StringName = &""
## Held while the score is at least this. NAN: not a high rule.
@export var at_least: float = NAN
## Held while the score is at most this. NAN: not a low rule.
@export var at_most: float = NAN
## The thought held: a [code]BustleThoughtDef[/code] from the needs_mood module, with a duration of
## 0 (held) and reason kind [code]environment[/code].
@export var thought: Resource = null


## True when it can be used: a known score; exactly one of [member at_least] and [member at_most],
## from 0 to 1; and a held thought (a duration of 0) with an id and reason kind
## [code]environment[/code].
## @experimental
func is_valid() -> bool:
	if not BustleEnvironmentPort.SCORES.has(score) or thought == null or thought.get(&"id") == &"":
		return false
	var duration: Variant = thought.get(&"duration_hours")
	if not (duration is float or duration is int) or float(duration) != 0.0 \
			or thought.get(&"reason_kind") != &"environment":
		return false
	if is_nan(at_least) == is_nan(at_most):
		return false
	var line := at_most if is_nan(at_least) else at_least
	return is_finite(line) and line >= 0.0 and line <= 1.0


## True for a high rule ([member at_least] set).
## @experimental
func is_high() -> bool:
	return not is_nan(at_least)


## True when [param value] meets it. An unset score (NAN) never does.
## @experimental
func matches(value: float) -> bool:
	if is_nan(value):
		return false
	return value >= at_least if is_high() else value <= at_most
