# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFleeAction
extends BustleActionHandler

## [code]flee[/code]: runs straight away from the agent's threat ([code]move_to[/code] in the
## output, aimed [member BustleConflictConfig.flee_margin] past the safe distance so a body that
## stops a little short still gets there) until it is
## [member BustleConflictConfig.flee_distance] away, then clears the conflict.
## Without positions it gets away at once. Done when the conflict is over.
## @experimental

## The conflicts it serves.
var conflict: BustleConflict


func _init(p_conflict: BustleConflict = null) -> void:
	conflict = p_conflict


func tick(context: BustleActionContext, _delta: float) -> Status:
	var threat := conflict.threat_of(context.agent_id) if conflict != null else &""
	if threat == &"":
		return Status.DONE
	var here: Variant = conflict.where(context.agent_id)
	var there: Variant = conflict.where(threat)
	if here == null or there == null or (here as Vector3).distance_to(there) >= conflict.config.flee_distance:
		conflict.clear(context.agent_id)
		return Status.DONE
	var away := (here as Vector3) - (there as Vector3)
	if away.is_zero_approx():
		away = Vector3.FORWARD
	context.output["move_to"] = (there as Vector3) + away.normalized() * (conflict.config.flee_distance + maxf(conflict.config.flee_margin, 0.0))
	return Status.RUNNING
