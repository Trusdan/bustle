# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleStealAction
extends BustleActionHandler

## [code]steal[/code]: takes the agent's target through [method BustleCrime.steal] (which checks
## every guard again first). Done when the item moved; fails with the reason otherwise
## ([code]no_target[/code], [code]guards_failed[/code] or [code]not_moved[/code]).
## @experimental

## The crime rules it serves.
var crime: BustleCrime


func _init(p_crime: BustleCrime = null) -> void:
	crime = p_crime


func tick(context: BustleActionContext, _delta: float) -> Status:
	if crime == null:
		context.failure = &"no_target"
		return Status.FAILED
	var result := crime.steal(context.agent_id, context.now_minutes)
	if not result.get("ok", false):
		context.failure = result.get("reason", &"guards_failed")
		return Status.FAILED
	context.output["took"] = result["item"]
	return Status.DONE
