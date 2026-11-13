# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWorkPort
extends RefCounted

## Jobs. A host extends this to give agents its jobs. The standalone default has none, unless it
## is given a [BustleScheduleRoster]: then an agent's job is its role that comes with a routine.
## Posted, one-off work is on an optional [BustleJobBoard]; standing jobs stay roles.
## @experimental

## Jobs as roles, or null for none.
var roster: BustleScheduleRoster
## Posted, one-off work, or null for none.
var board: BustleJobBoard


func _init(p_roster: BustleScheduleRoster = null, p_board: BustleJobBoard = null) -> void:
	roster = p_roster
	board = p_board


## The job [param id] has, or empty.
## @experimental
func job_of(id: StringName) -> StringName:
	return roster.job_of(id) if roster != null else &""


## True when [param id] (with [param tags]) passes the gates of posting [param job] on the board.
## False with no board.
## @experimental
func can_do(id: StringName, job: StringName, tags: Array[StringName] = []) -> bool:
	return board != null and board.can_do(BustleJobSeeker.new(id, null, {}, tags), job)


## The board posting [param id] has claimed, or empty (always empty with no board).
## @experimental
func claimed_of(id: StringName) -> StringName:
	return board.claimed_of(id) if board != null else &""
