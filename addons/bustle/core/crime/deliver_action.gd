# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDeliverAction
extends BustleActionHandler

## [code]deliver[/code]: goes on with the agent's oldest errand through
## [method BustleCrimeWatch.deliver]. While it still has to get there, it asks the host to move
## the agent towards the target ([code]move_to[/code], [code]talk_to[/code] and
## [code]gear[/code] in the output, the gear being [member BustleCrimeWatch.travel_gear]); Bustle
## names where, the host moves the body. Done once the word is delivered, forgotten, or there's
## nobody to reach yet.
## @experimental

## The watch whose errands it runs.
var watch: BustleCrimeWatch


func _init(p_watch: BustleCrimeWatch = null) -> void:
	watch = p_watch


func tick(context: BustleActionContext, _delta: float) -> Status:
	if watch == null:
		return Status.DONE
	var result := watch.deliver(context.agent_id, context.now_minutes)
	context.output["errand"] = result["state"]
	if result["state"] != &"travelling":
		return Status.DONE
	var target: StringName = result["target"]
	var there: Variant = watch.position_of(target)
	if there is Vector3:
		context.output["move_to"] = there
	context.output["talk_to"] = target
	context.output["gear"] = watch.travel_gear
	return Status.RUNNING
