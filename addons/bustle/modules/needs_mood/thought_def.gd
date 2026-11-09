# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleThoughtDef
extends Resource

## One kind of thought, as data: what it does to mood, for how long, how repeats stack, the
## emotion it carries and the kind of reason behind it. A thought with a [member duration_hours]
## of 0 lasts while its condition holds (see [method BustleMood.set_held]); a need thought
## ([member need] set) holds while that need's pressure is at least [member need_at_least].
## @experimental

## Its id.
@export var id: StringName = &""
## Mood points it adds to the target (negative lowers it).
@export var value: float = 0.0
## Game hours it lasts. 0: while its condition holds.
@export var duration_hours: float = 0.0
## How many of it can be active at once. A new one past the limit replaces the oldest.
@export var stack_limit: int = 1
## Each repeat counts this much of the one before: the n-th counts [code]stack_mult^(n-1)[/code].
@export var stack_mult: float = 0.5
## The emotion it carries (for example content, lonely, tense).
@export var emotion: StringName = &""
## Its tags; the modifier [code]thought.tag.<tag>[/code] (base 1) multiplies its value.
@export var tags: Array[StringName] = []
## What kind of reason it has: need, event, environment, trait or deed.
@export var reason_kind: StringName = &"event"
## For a need thought: the need it watches. Empty otherwise.
@export var need: StringName = &""
## For a need thought: the pressure at or above which it holds.
@export_range(0.0, 1.0) var need_at_least: float = 1.0


## The reason kinds a thought can have.
const REASON_KINDS: Array[StringName] = [&"need", &"event", &"environment", &"trait", &"deed"]
## The longest duration: about 1,900 game years, well inside whole minutes.
const MAX_DURATION_HOURS := 1.0e7


## True when it can be used: an id; a finite value; a duration from 0 to
## [constant MAX_DURATION_HOURS]; a stack limit of at least 1; a [member stack_mult] from 0 to 1
## (repeats never count more); a [member need_at_least] from 0 to 1; and a known reason kind.
## @experimental
func is_valid() -> bool:
	return id != &"" and is_finite(value) and is_finite(duration_hours) and duration_hours >= 0.0 \
			and duration_hours <= MAX_DURATION_HOURS and stack_limit >= 1 and is_finite(stack_mult) \
			and stack_mult >= 0.0 and stack_mult <= 1.0 and is_finite(need_at_least) \
			and need_at_least >= 0.0 and need_at_least <= 1.0 and REASON_KINDS.has(reason_kind)


## A timed thought's length in whole game minutes: the duration rounded to the nearest minute, and
## at least 1. 0 for a held thought.
## @experimental
func duration_minutes() -> int:
	if duration_hours <= 0.0:
		return 0
	return maxi(roundi(duration_hours * 60.0), 1)
