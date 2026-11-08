# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleNeedDef
extends Resource

## One need, as data: how fast its pressure rises (0 = fine, 1 = urgent), under which conditions,
## how it changes while other conditions hold, and its response curve. Bustle ships no needs of its
## own; a host defines them. Every rate defaults to 0.
## [br][br]
## Each game hour the pressure changes by [member rate_per_hour] × the agent's
## [code]need.<id>.rate[/code] modifier (only while one of [member rises_when] holds, or always when
## that is empty), plus [member condition_rates] for every condition that holds. The rate modifier
## scales the rise only, never a fall.
## @experimental

## Its id: the scorer reads its pressure as the input [code]need.<id>[/code].
@export var id: StringName = &""
## Rise in pressure per game hour.
@export var rate_per_hour: float = 0.0
## The base rate applies only while one of these conditions holds. Empty: always.
@export var rises_when: Array[StringName] = []
## Condition → change in pressure per game hour while it holds (negative falls, for example while
## asleep).
@export var condition_rates: Dictionary[StringName, float] = {}
## Its response curve over pressure, for the scorer (see [method BustleNeedSet.apply_curves]).
## Null: the pressure itself.
@export var curve: Curve
## Its pressure when an agent gets it.
@export_range(0.0, 1.0) var start: float = 0.0


## The change in pressure per game hour under [param conditions], with the rise scaled by
## [param rate_mult]. Non-finite numbers count as 0.
## @experimental
func rate_under(conditions: Array[StringName], rate_mult: float = 1.0) -> float:
	var rate := 0.0
	var rising := rises_when.is_empty()
	for condition: StringName in rises_when:
		if conditions.has(condition):
			rising = true
			break
	if rising:
		rate += _finite(rate_per_hour) * maxf(_finite(rate_mult), 0.0)
	var held: Array[StringName] = []
	for condition: StringName in conditions:
		if condition_rates.has(condition) and not held.has(condition):
			held.append(condition)
			var extra := _finite(condition_rates[condition])
			rate += extra * maxf(_finite(rate_mult), 0.0) if extra > 0.0 else extra
	return rate


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
