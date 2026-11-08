# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleIdleAction
extends BustleActionHandler

## [code]idle[/code]: idles in [code]params.style[/code] (put in the output as
## [code]animation[/code]) for [code]params.minutes[/code] game minutes, default 0 (one tick).
## A negative or non-finite number of minutes fails the step ([code]bad_params[/code]).
## @experimental


func start(context: BustleActionContext) -> void:
	var minutes: Variant = context.params.get("minutes", 0)
	if typeof(minutes) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(minutes)) or float(minutes) < 0.0:
		context.data["bad"] = true
		return
	context.data["until"] = context.now_minutes + ceili(float(minutes))


func tick(context: BustleActionContext, _delta: float) -> Status:
	if context.data.get("bad", false):
		context.failure = &"bad_params"
		return Status.FAILED
	context.output["animation"] = StringName(str(context.params.get("style", "")))
	return Status.DONE if context.now_minutes >= int(context.data["until"]) else Status.RUNNING
