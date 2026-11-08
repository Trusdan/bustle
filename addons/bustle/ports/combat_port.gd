# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCombatPort
extends RefCounted

## Fighting, handed to the host. A host extends this to drive its own combat, and reports progress
## through [method status]. The standalone default resolves at once and harmlessly: engaging
## leaves the fighter RESOLVED, with no damage and no winner.
## @experimental

## Where a fight stands for one agent.
enum Status { NONE, ENGAGED, RESOLVED }

var _status: Dictionary[StringName, int] = {}


## [param id] engages [param target]. Ignored when either is empty or they are the same.
## @experimental
func engage(id: StringName, target: StringName) -> void:
	if id == &"" or target == &"" or id == target:
		return
	_status[id] = Status.RESOLVED


## [param id] stops fighting.
## @experimental
func disengage(id: StringName) -> void:
	_status.erase(id)


## Where [param id]'s fight stands. NONE for an agent not fighting.
## @experimental
func status(id: StringName) -> Status:
	return _status.get(id, Status.NONE) as Status
