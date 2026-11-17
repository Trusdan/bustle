# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRestSickAction
extends BustleActionHandler

## [code]rest_sick[/code]: the agent rests while it is ill ([method BustleRestSick.wants_rest]).
## With a bed ([method BustleRestSick.bed_for]) it first asks the host to move it there
## ([code]move_to[/code] in the output); then, or at once without one, it rests, naming the bed in
## the output ([code]rest_sick[/code]: the bed's item, or empty where it stands). Bustle names
## where; the host moves the body and plays the rest. Done on the first tick it no longer should
## rest: the port cleared the tag or restored the capacity (or it is now downed, locked, or seeking
## care first).
## @experimental: Added after 1.0 for the health module.

## The rest-when-sick rules it works for.
var rest: BustleRestSick


func _init(p_rest: BustleRestSick = null) -> void:
	rest = p_rest


func tick(context: BustleActionContext, _delta: float) -> Status:
	var agent := context.agent_id
	if rest == null or not rest.wants_rest(agent):
		return Status.DONE
	var bed := rest.bed_for(agent)
	context.output["rest_sick"] = bed.get("item", &"")
	if not rest.has_reached(agent, bed):
		context.output["move_to"] = rest.health.ports.world.place_position(StringName(bed["place"]))
	return Status.RUNNING
