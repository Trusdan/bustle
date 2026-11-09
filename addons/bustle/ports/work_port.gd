# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWorkPort
extends RefCounted

## Jobs. A host extends this to give agents its jobs. The standalone default has none, unless it
## is given a [BustleScheduleRoster]: then an agent's job is its role that comes with a routine.
## @experimental

## Jobs as roles, or null for none.
var roster: BustleScheduleRoster


func _init(p_roster: BustleScheduleRoster = null) -> void:
	roster = p_roster


## The job [param id] has, or empty.
## @experimental
func job_of(id: StringName) -> StringName:
	return roster.job_of(id) if roster != null else &""
