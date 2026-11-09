# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFightAction
extends BustleActionHandler

## [code]fight[/code]: engages the agent's threat through the combat port with its intent, and
## names it as the output's [code]attack_target[/code]. Every tick it works the intent out again
## ([method BustleConflict.update_intent]) and engages again when it changed, so a fight can
## escalate. Done when the port reports the fight RESOLVED (then [method BustleConflict.finish]
## reports it) or the conflict was cleared. Fails with [code]no_threat[/code] when the agent has
## none.
## @experimental

## The conflicts it serves.
var conflict: BustleConflict


func _init(p_conflict: BustleConflict = null) -> void:
	conflict = p_conflict


func start(context: BustleActionContext) -> void:
	var threat := conflict.threat_of(context.agent_id) if conflict != null else &""
	if threat == &"":
		context.data["failure"] = "no_threat"
		return
	var intent := conflict.update_intent(context.agent_id)
	context.data["threat"] = String(threat)
	context.data["intent"] = String(intent)
	conflict.combat.engage(context.agent_id, threat, intent)


func tick(context: BustleActionContext, _delta: float) -> Status:
	if context.data.has("failure"):
		context.failure = StringName(context.data["failure"])
		return Status.FAILED
	if conflict.threat_of(context.agent_id) != StringName(context.data["threat"]):
		conflict.combat.disengage(context.agent_id)
		return Status.DONE
	var threat := StringName(context.data["threat"])
	context.output["attack_target"] = threat
	var intent := conflict.update_intent(context.agent_id)
	if intent != StringName(context.data["intent"]):
		context.data["intent"] = String(intent)
		conflict.combat.engage(context.agent_id, threat, intent)
	if conflict.combat.status(context.agent_id) != BustleCombatPort.Status.RESOLVED:
		return Status.RUNNING
	conflict.finish(context.agent_id, context.now_minutes)
	return Status.DONE


func cancel(context: BustleActionContext) -> void:
	if conflict != null:
		conflict.combat.disengage(context.agent_id)
