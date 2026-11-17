# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFetchHelpAction
extends BustleActionHandler

## [code]fetch_help[/code]: goes to the ally [method BustleConflict.notice] picked
## ([code]move_to[/code] and [code]talk_to[/code] in the output) and, once within
## [constant REACH] metres (or at once without positions), hands the threat to it with
## [method BustleConflict.call_help]. When there's no ally or the ally can't come (it has a
## conflict of its own), it switches to fleeing ([method BustleConflict.switch_to_flee]) and the
## [code]flee[/code] goal takes over. Done either way.

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
	if approach(context, conflict.where(agent), conflict.where(helper), helper):
		return Status.RUNNING
	if not conflict.call_help(helper, agent, context.now_minutes):
		conflict.switch_to_flee(agent)
	return Status.DONE


## The fetch-help movement and arrival rule, shared by every errand that goes to fetch someone:
## while the agent at [param here] is more than [constant REACH] metres from [param helper] at
## [param there], it asks the host to move it there ([code]move_to[/code] and [code]talk_to[/code]
## in [param context]'s output) and returns true. Once within reach, or at once when either
## position is unknown (not a [Vector3]), it returns false: the agent has arrived.
## @experimental: Added after 1.0, when fetching a healer started to reuse this rule.
static func approach(context: BustleActionContext, here: Variant, there: Variant, helper: StringName) -> bool:
	if helper != &"" and here is Vector3 and there is Vector3 and (here as Vector3).distance_to(there) > REACH:
		context.output["move_to"] = there
		context.output["talk_to"] = helper
		return true
	return false
