# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScheduleDef
extends Resource

## A routine, as data: a default day, with whole-day overrides by weekday (a rest day, a market
## day) and by season. A weekday override wins over a season override, which wins over the
## default. The weekday of a game day is [code](day + week_offset) mod week_length[/code], counting
## days from minute 0.
## @experimental

## Its id.
@export var id: StringName = &""
## The usual day.
@export var day: BustleScheduleDay
## Weekday (0 to week_length − 1) → that weekday's day instead.
@export var weekdays: Dictionary[int, BustleScheduleDay] = {}
## Season (the clock port's [method BustleClockPort.season]) → that season's day instead.
@export var seasons: Dictionary[StringName, BustleScheduleDay] = {}
## Days in a week.
@export var week_length: int = 7
## Which weekday game day 0 is.
@export var week_offset: int = 0
## How late an agent may arrive and still be on time, in minutes, for blocks that don't say.
@export var late_minutes: int = 15


## The weekday of game day [param day_index].
## @experimental
func weekday(day_index: int) -> int:
	var length := maxi(week_length, 1)
	return posmod(day_index + week_offset, length)


## The plan for game day [param day_index] in [param season]: the weekday override, else the
## season override, else the usual day. Null when there is none.
## @experimental
func plan_for(day_index: int, season: StringName = &"") -> BustleScheduleDay:
	var key := weekday(day_index)
	if weekdays.has(key) and weekdays[key] != null:
		return weekdays[key]
	if season != &"" and seasons.has(season) and seasons[season] != null:
		return seasons[season]
	return day
