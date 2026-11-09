# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCombatPort
extends RefCounted

## Fighting, handed to the host. A host extends this to drive its own combat, and reports progress
## through [method status] and the result through [method outcome]. The standalone default
## resolves at once and harmlessly: engaging leaves the fighter RESOLVED, with no damage, no winner
## and nobody killed.
## [br][br]
## Every fight has an intent: [code]subdue[/code] (the default) or [code]kill[/code]. A host's
## combat should pass a subdue fight's immediate damage through
## [method BustleConflict.filter_damage]. A target may still die, then or later of its wounds; the
## host's health system decides, and reports it in [method outcome].
## @experimental

## Where a fight stands for one agent.
enum Status { NONE, ENGAGED, RESOLVED }

var _status: Dictionary[StringName, int] = {}
var _outcomes: Dictionary[StringName, Dictionary] = {}


## [param id] engages [param target] with [param intent] ([code]subdue[/code] or
## [code]kill[/code]). Engaging again changes the intent. Ignored when either id is empty or they
## are the same.
## @experimental
func engage(id: StringName, target: StringName, intent: StringName = &"subdue") -> void:
	if id == &"" or target == &"" or id == target:
		return
	_status[id] = Status.RESOLVED
	_outcomes[id] = {"target": target, "intent": intent, "killed": false, "downed": false}


## [param id] stops fighting.
## @experimental
func disengage(id: StringName) -> void:
	_status.erase(id)
	_outcomes.erase(id)


## How [param id]'s fight ended, once RESOLVED: [code]{target, intent, killed, downed}[/code],
## where [code]killed[/code] says whether the target died and [code]downed[/code] whether it was
## beaten without dying. Empty before then.
## @experimental
func outcome(id: StringName) -> Dictionary:
	return _outcomes.get(id, {}).duplicate() if status(id) == Status.RESOLVED else {}


## Where [param id]'s fight stands. NONE for an agent not fighting.
## @experimental
func status(id: StringName) -> Status:
	return _status.get(id, Status.NONE) as Status
