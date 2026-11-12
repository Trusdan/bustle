# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends BustleActionHandler

## The demo host's [code]use[/code] action: hold an object, use it for its time, then finish the use
## ([method BustleAffordance.use]), which lowers the needs it meets. The object is the step's
## option, or [code]params.object[/code]. Fails with the affordance's refusal when it can't be held
## or used, and with [code]no_object[/code] for an unknown object. It names the object in its
## output as [code]use_affordance[/code].

## The objects.
var affordances: BustleAffordanceSet
## (agent) → its [BustleNeedSet].
var needs_of: Callable = Callable()
## (object id) → how many game minutes one use takes.
var minutes_of: Callable = Callable()
## (agent, object id, minute) → called when a use completes.
var on_used: Callable = Callable()


func start(context: BustleActionContext) -> void:
	var object := _object(context)
	var found := affordances.get_affordance(object) if affordances != null else null
	if found == null:
		context.data["fail"] = "no_object"
		return
	var held := found.reserve(context.agent_id, context.now_minutes)
	if held != BustleAffordance.OK:
		context.data["fail"] = String(held)
		return
	context.data["object"] = String(object)
	context.data["until"] = context.now_minutes + int(minutes_of.call(object))


func tick(context: BustleActionContext, _delta: float) -> Status:
	if context.data.has("fail"):
		context.failure = StringName(context.data["fail"])
		return Status.FAILED
	var object := StringName(context.data["object"])
	context.output["use_affordance"] = object
	if context.now_minutes < int(context.data["until"]):
		return Status.RUNNING
	var used := affordances.get_affordance(object).use(context.agent_id, context.now_minutes, needs_of.call(context.agent_id))
	if used != BustleAffordance.OK:
		context.failure = used
		return Status.FAILED
	if on_used.is_valid():
		on_used.call(context.agent_id, object, context.now_minutes)
	return Status.DONE


func cancel(context: BustleActionContext) -> void:
	var found := affordances.get_affordance(_object(context)) if affordances != null else null
	if found != null:
		found.release(context.agent_id)


func _object(context: BustleActionContext) -> StringName:
	return context.option_id if context.option_id != &"" else StringName(context.params.get("object", ""))
