# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScheduleBlock
extends Resource

## One block of a day's schedule: an activity from one minute of the day to another, at a place.
## An end at or before the start runs past midnight; the block belongs to the day it starts.
## @experimental

## What the agent should be doing: the scorer sees it as the input
## [code]schedule.<activity>[/code] (lower-case letters, digits and underscores).
@export var activity: StringName = &""
## The minute of the day it starts, 0 to 1439.
@export_range(0, 1439) var start_minute: int = 0
## The minute of the day it ends, 0 to 1440. At or before the start: the next day.
@export_range(0, 1440) var end_minute: int = 0
## Where (the host's place id), or empty.
@export var place: StringName = &""
## How late the agent may arrive and still be on time, in minutes. -1: the schedule's own.
@export var late_minutes: int = -1
## What attending it earns, paid at its end through the trade port. 0: unpaid.
@export var wage: int = 0
## Who pays the wage. Empty: the employer of the agent's job (see [BustleRoleSchedules]).
@export var payer: StringName = &""


## Its length in minutes (1 to 1440).
## @experimental
func length() -> int:
	var out := end_minute - start_minute
	return out if out > 0 else out + 1440


## True when it can be used: an activity name that is a valid input name (and not
## [code]free_time[/code], which means no block), minutes in range, a lateness of -1 or more and a
## wage of at least 0.
## @experimental
func is_valid() -> bool:
	return BustleInputs.is_valid_input(StringName("schedule.%s" % activity)) and activity != &"" \
			and activity != &"free_time" and wage >= 0 \
			and start_minute >= 0 and start_minute < 1440 and end_minute >= 0 and end_minute <= 1440 \
			and late_minutes >= -1
