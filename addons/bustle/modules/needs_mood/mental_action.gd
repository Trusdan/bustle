# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMentalAction
extends BustleActionHandler

## [code]mental[/code]: acts out the agent's mental state through [BustleMentalBehaviour]. It names
## where to go ([code]move_to[/code]) and the host moves the body:
## [br]- withdraw: home, and stays there ([code]withdrawn[/code] in the output: a host's own visits
## should be turned away while it's set; see [method BustleMentalBehaviour.accepts]);
## [br]- wander: walks from place to place;
## [br]- binge: uses its indulgence ([code]use_affordance[/code]);
## [br]- lash out: goes to its target ([code]talk_to[/code]) and, once there, insults it
## ([code]insulted[/code]), then is done.
## [br]It runs while the state lasts; the goal stops being eligible when the state ends.
## @experimental

## The behaviour it acts out.
var behaviour: BustleMentalBehaviour


func _init(p_behaviour: BustleMentalBehaviour = null) -> void:
	behaviour = p_behaviour


func tick(context: BustleActionContext, _delta: float) -> Status:
	if behaviour == null:
		return Status.DONE
	var agent := context.agent_id
	var id := StringName(behaviour.state_of(agent).active().get("id", ""))
	var there: Variant = behaviour.destination(agent, context.now_minutes)
	if there is Vector3:
		context.output["move_to"] = there
	match id:
		&"withdraw":
			context.output["withdrawn"] = true
		&"binge":
			context.output["use_affordance"] = behaviour.indulgence(agent)
		&"lash_out":
			var target := behaviour.lash_target(agent)
			if target == &"":
				return Status.DONE
			context.output["talk_to"] = target
			var here: Variant = behaviour.position(agent)
			if not (here is Vector3 and there is Vector3) or (here as Vector3).distance_to(there) <= behaviour.config.lash_reach:
				context.output["insulted"] = target
				behaviour.insult(agent, target, context.now_minutes)
				return Status.DONE
		&"wander":
			pass
		_:
			return Status.DONE
	return Status.RUNNING
