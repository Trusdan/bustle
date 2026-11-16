# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends BustleClockPort

## The village's clock, as a host adapter (docs/ports.md, "BustleClockPort"). The game owns the time
## and moves [member minutes] on; Bustle only reads it. A real game would read its own day-night
## node here instead.

## Whole game minutes since the start.
var minutes: int = 0


## The current game minute. Bustle reads this; it never moves the clock.
func now_minutes() -> int:
	return minutes


## A key for today, [code]day_<n>[/code], with 1440-minute days like the default.
func day_key() -> StringName:
	return StringName("day_%d" % floori(float(minutes) / MINUTES_PER_DAY))
