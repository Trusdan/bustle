# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthThought
extends Resource

## A thought held while the host reports a health state: either pain of at least
## [member pain_at_least], or a visible tag such as [code]sick[/code] ([member tag]). Set exactly
## one of the two.
## @experimental

## Held while pain is at least this (above 0). NAN: not a pain thought.
@export var pain_at_least: float = NAN
## Held while [method BustleHealthPort.visible_tags] has this tag. Empty: not a tag thought.
@export var tag: StringName = &""
## The thought: held (duration 0), with reason kind [code]health[/code].
@export var thought: BustleThoughtDef


## True when exactly one of pain or tag is set, the pain line is in 0..1 and above 0, and the
## thought is a valid held health thought.
## @experimental
func is_valid() -> bool:
	var by_pain := not is_nan(pain_at_least)
	if by_pain == (tag != &""):
		return false
	if by_pain and (pain_at_least <= 0.0 or pain_at_least > 1.0):
		return false
	return thought != null and thought.is_valid() and thought.duration_hours == 0.0 and thought.reason_kind == &"health"
