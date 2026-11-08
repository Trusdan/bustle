# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWaitAction
extends BustleActionHandler

## [code]wait[/code]: does nothing until [code]params.minutes[/code] game minutes have passed.
## A missing, negative or non-finite number of minutes fails the step ([code]bad_params[/code]).
## @experimental


func start(context: BustleActionContext) -> void:
	var minutes: Variant = context.params.get("minutes", null)
	if typeof(minutes) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(minutes)) or float(minutes) < 0.0:
		context.data["bad"] = true
		return
	context.data["until"] = context.now_minutes + ceili(float(minutes))


func tick(context: BustleActionContext, _delta: float) -> Status:
	if context.data.get("bad", false):
		context.failure = &"bad_params"
		return Status.FAILED
	return Status.DONE if context.now_minutes >= int(context.data["until"]) else Status.RUNNING
