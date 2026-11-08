# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleClockPort
extends RefCounted

## The game clock, in whole game minutes. A host extends this and overrides [method now_minutes]
## and [method day_key] to read its own clock. The standalone default keeps its own minute count,
## starting at 0 and moved on with [method advance]; a day is [constant MINUTES_PER_DAY] minutes,
## so minute 1439 is in day 0 and minute 1440 starts day 1.
## @experimental

## Minutes in a day, for the default.
const MINUTES_PER_DAY := 1440

var _minutes: int = 0


## The current game minute.
## @experimental
func now_minutes() -> int:
	return _minutes


## A key for the current day: [code]day_<n>[/code], counting from 0.
## @experimental
func day_key() -> StringName:
	return StringName("day_%d" % floori(float(now_minutes()) / MINUTES_PER_DAY))


## Moves the default clock on by [param minutes]. False (and no change) when negative.
## @experimental
func advance(minutes: int) -> bool:
	if minutes < 0:
		return false
	_minutes += minutes
	return true
