# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFearDef
extends Resource

## One fear, as data: the event that forms it, what it makes the agent avoid and for how long.
## [BustleAspirations] reads it. Bustle ships none; events, goals and inputs are the host's names.
## @experimental

## Its id.
@export var id: StringName = &""
## The event that forms it (an event name the host passes to [method BustleAspirations.update]).
@export var trigger: StringName = &""
## Goals it makes the agent avoid, whatever the option.
@export var avoid_goals: Array[StringName] = []
## Options (objects, places, people) it makes the agent avoid, whatever the goal.
@export var avoid_options: Array[StringName] = []
## An input naming one more option to avoid, read when the fear forms (for example who caused the
## event). Empty: none.
@export var avoid_input: StringName = &""
## How much an avoided candidate's score is multiplied by, from 0 to 1. 0: it can't be chosen.
@export var avoid_mult: float = 0.25
## Game hours it lasts after it forms. 0: until [member cleared_fact].
@export var duration_hours: float = 72.0
## A fact that ends it early (a counter-event the host reports). Empty: none.
@export var cleared_fact: StringName = &""
## A thought added when it forms (a timed [code]BustleThoughtDef[/code]), or null.
@export var thought: Resource = null


## True when it can be used: an id, a trigger, something to avoid, a multiplier from 0 to 1, a
## finite non-negative duration, and a way to end (a duration or a clearing fact).
## @experimental
func is_valid() -> bool:
	if id == &"" or trigger == &"" or (avoid_goals.is_empty() and avoid_options.is_empty() and avoid_input == &""):
		return false
	if not is_finite(avoid_mult) or avoid_mult < 0.0 or avoid_mult > 1.0:
		return false
	return is_finite(duration_hours) and duration_hours >= 0.0 and (duration_hours > 0.0 or cleared_fact != &"")
