# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDirectorRules
extends Resource

## How [BustleDirector] reads tension and paces the story. Tension (0 to 1) is the host's world
## state, weighted by [member tension_inputs], plus each recently fired event's
## [member BustleEventDef.tension], fading in a straight line over [member memory_minutes]. Above
## [member high], the story needs relief; below [member low], it needs a raise. Experimental
## defaults.
## @experimental

## Input key → how much tension each unit of it adds (negative relieves).
@export var tension_inputs: Dictionary[StringName, float] = {}
## Game minutes a fired event's tension lasts, fading to nothing. Above 0.
@export var memory_minutes: int = 4320
## At or above this, the story needs relief.
@export var high: float = 0.7
## At or below this, the story needs a raise.
@export var low: float = 0.3
## Game minutes after any event fires before the next may. 0: none. It only delays: an event still
## eligible when the gap ends fires then.
@export var beat_gap_minutes: int = 0


## Why these rules can't be used, or empty: a positive memory, 0 <= low < high <= 1, a gap from 0
## to the memory, and finite, non-empty tension inputs.
## @experimental
func validate() -> String:
	if memory_minutes <= 0:
		return "memory_minutes must be above 0"
	if not (is_finite(low) and is_finite(high) and low >= 0.0 and low < high and high <= 1.0):
		return "low and high must satisfy 0 <= low < high <= 1"
	if beat_gap_minutes < 0 or beat_gap_minutes > memory_minutes:
		return "beat_gap_minutes must be between 0 and memory_minutes"
	for key: StringName in tension_inputs:
		if key == &"" or not is_finite(tension_inputs[key]):
			return "a tension input is empty or not finite"
	return ""
