# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCombatPort
extends RefCounted

## Fighting, handed to the host. A host extends this to drive its own combat, and reports progress
## through [method status] and the result through [method outcome]. The standalone default
## resolves at once and harmlessly: engaging leaves the fighter RESOLVED, with no damage, no winner
## and nobody killed.
## [br][br]
## A fight is a scuffle unless it is engaged as lethal. A host's combat should pass a scuffle's
## damage through [method BustleConflict.filter_damage], so a scuffle never kills.
## @experimental

## Where a fight stands for one agent.
enum Status { NONE, ENGAGED, RESOLVED }

var _status: Dictionary[StringName, int] = {}
var _outcomes: Dictionary[StringName, Dictionary] = {}


## [param id] engages [param target], as a scuffle or, with [param lethal], to kill. Ignored when
## either is empty or they are the same.
## @experimental
func engage(id: StringName, target: StringName, lethal: bool = false) -> void:
	if id == &"" or target == &"" or id == target:
		return
	_status[id] = Status.RESOLVED
	_outcomes[id] = {"target": target, "lethal": lethal, "killed": false}


## [param id] stops fighting.
## @experimental
func disengage(id: StringName) -> void:
	_status.erase(id)
	_outcomes.erase(id)


## How [param id]'s fight ended, once RESOLVED: [code]{target, lethal, killed}[/code], where
## [code]killed[/code] says whether the target died. Empty before then.
## @experimental
func outcome(id: StringName) -> Dictionary:
	return _outcomes.get(id, {}).duplicate() if status(id) == Status.RESOLVED else {}


## Where [param id]'s fight stands. NONE for an agent not fighting.
## @experimental
func status(id: StringName) -> Status:
	return _status.get(id, Status.NONE) as Status
