# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMemoryConfig
extends Resource

## How a [BustleMemory] holds and forgets, as data. Each kind of memory fades on its own half-life
## in game hours; each source starts at its own strength. An entry is forgotten once its strength
## falls below [member forget_below]. These are starting numbers, not tuning: a host sets its own.
## @experimental

## The most entries one agent keeps; past it, the weakest goes.
@export var capacity: int = 32
## Kind → half-life in game hours. Kinds not listed use [member default_half_life_hours].
@export var half_life_hours: Dictionary[StringName, float] = {&"person": 6.0, &"item": 72.0, &"place": 720.0}
## Half-life for kinds not in [member half_life_hours].
@export var default_half_life_hours: float = 24.0
## Source → starting strength (0 to 1).
@export var source_strength: Dictionary[StringName, float] = {&"saw": 1.0, &"told": 0.8, &"heard": 0.6, &"routine": 0.4}
## Below this strength an entry is forgotten.
@export var forget_below: float = 0.1


## [param kind]'s half-life in game minutes (at least 1).
## @experimental
func half_life_minutes(kind: StringName) -> float:
	var hours: float = half_life_hours.get(kind, default_half_life_hours)
	return maxf(hours * 60.0, 1.0) if is_finite(hours) else 1.0


## [param source]'s starting strength, from 0 to 1 (0 for an unknown source).
## @experimental
func strength_of(source: StringName) -> float:
	var value: float = source_strength.get(source, 0.0)
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
