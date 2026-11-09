# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFetchHelpAction
extends BustleActionHandler

## [code]fetch_help[/code]: goes to the ally [method BustleConflict.notice] picked
## ([code]move_to[/code] and [code]talk_to[/code] in the output) and, once within
## [constant REACH] metres (or at once without positions), hands the threat to it with
## [method BustleConflict.call_help]. When there's no ally or the ally can't come (it has a
## conflict of its own), it switches to fleeing ([method BustleConflict.switch_to_flee]) and the
## [code]flee[/code] goal takes over. Done either way.
## @experimental

## How close, in metres, the agent must get to its ally.
const REACH := 2.0

## The conflicts it serves.
var conflict: BustleConflict


func _init(p_conflict: BustleConflict = null) -> void:
	conflict = p_conflict


func tick(context: BustleActionContext, _delta: float) -> Status:
	var agent := context.agent_id
	if conflict == null or conflict.threat_of(agent) == &"":
		return Status.DONE
	var helper := conflict.helper_of(agent)
	if helper == &"" or conflict.threat_of(helper) != &"":
		conflict.switch_to_flee(agent)
		return Status.DONE
	var here: Variant = conflict.where(agent)
	var there: Variant = conflict.where(helper)
	if helper != &"" and here != null and there != null and (here as Vector3).distance_to(there) > REACH:
		context.output["move_to"] = there
		context.output["talk_to"] = helper
		return Status.RUNNING
	if not conflict.call_help(helper, agent, context.now_minutes):
		conflict.switch_to_flee(agent)
	return Status.DONE
