# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSeekCareAction
extends BustleActionHandler

## [code]seek_care[/code]: takes the agent to where it can get care
## ([method BustleSeekCare.destination_for]). While it still has to get there, it asks the host to
## move it ([code]move_to[/code] when a position is known, [code]talk_to[/code] for a person, and
## [code]seek_care[/code], the target, in the output); Bustle names where, the host moves the body.
## Done once there, or when the agent no longer needs to seek care (it recovered, or is downed).
## Failed with [code]no_care[/code] when there is nowhere to go.
## @experimental: Added after 1.0 for the health module.

## The seek-care rules it works for.
var seek: BustleSeekCare


func _init(p_seek: BustleSeekCare = null) -> void:
	seek = p_seek


func tick(context: BustleActionContext, _delta: float) -> Status:
	var agent := context.agent_id
	if seek == null:
		context.failure = &"no_care"
		return Status.FAILED
	var destination := seek.destination_for(agent)
	if destination.is_empty():
		context.failure = &"no_care"
		return Status.FAILED
	context.output["seek_care"] = destination["target"]
	if seek.need(agent) <= 0.0 or seek.has_reached(agent, destination):
		return Status.DONE
	var there: Variant = seek.position_for(destination)
	if there is Vector3:
		context.output["move_to"] = there
	if destination["kind"] == &"agent":
		context.output["talk_to"] = destination["target"]
	return Status.RUNNING
