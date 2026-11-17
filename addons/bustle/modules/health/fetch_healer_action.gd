# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFetchHealerAction
extends BustleActionHandler

## [code]fetch_healer[/code]: goes on with the agent's errand ([method BustleFetchHealer.errand_of]).
## It moves and arrives by the fetch-help rule ([method BustleFetchHelpAction.approach]): while more
## than [constant BustleFetchHelpAction.REACH] metres from the healer it asks the host to move the
## agent there ([code]move_to[/code] and [code]talk_to[/code] in the output); once there, or at once
## without positions, it tells the healer ([method BustleFetchHealer.arrive]). The patient is named
## in the output ([code]fetch_healer[/code]). Done once it arrived, or when the errand ended.
## @experimental: Added after 1.0 for the health module.

## The errands it runs.
var fetch: BustleFetchHealer


func _init(p_fetch: BustleFetchHealer = null) -> void:
	fetch = p_fetch


func tick(context: BustleActionContext, _delta: float) -> Status:
	var agent := context.agent_id
	var errand := fetch.errand_of(agent) if fetch != null else {}
	if errand.is_empty():
		return Status.DONE
	var healer := StringName(errand["healer"])
	context.output["fetch_healer"] = StringName(errand["patient"])
	if BustleFetchHelpAction.approach(context, fetch.position_of(agent), fetch.position_of(healer), healer):
		return Status.RUNNING
	fetch.arrive(agent, context.now_minutes)
	return Status.DONE
