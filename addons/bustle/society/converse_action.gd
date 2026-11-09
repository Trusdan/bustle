# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConverseAction
extends BustleActionHandler

## [code]converse[/code]: a [BustleConversation] one turn per tick, for agents in view. The partner
## is [code]params.with[/code], or the step's option id when that's empty (as when a goal picks
## someone to talk to from advertisements, like the comfort hook's). [code]params.opener[/code]
## names the first turn's interaction. A turn happens on the first tick at or after its minute, so
## the results match [method BustleConversation.run] for the same start.
## [br][br]
## It fails with [code]no_partner[/code], [code]declined[/code] (the roll to start failed) or
## [code]nothing_to_say[/code]. While it runs, the output names the partner as
## [code]talk_to[/code], and each turn's result is in it as [code]turn[/code]. The
## conversation's state is plain data in the step's data, so it saves with the runner.
## @experimental

## The conversation it runs.
var conversation: BustleConversation


func _init(p_conversation: BustleConversation = null) -> void:
	conversation = p_conversation


func start(context: BustleActionContext) -> void:
	var partner := StringName(str(context.params.get("with", "")))
	if partner == &"":
		partner = context.option_id
	var opener := StringName(str(context.params.get("opener", "")))
	var state := conversation.begin(context.agent_id, partner, context.now_minutes, opener) if conversation != null else {}
	if state.is_empty():
		context.data["failure"] = "no_partner"
	elif not conversation.wants_to_start(context.agent_id, partner, context.now_minutes):
		context.data["failure"] = "declined"
	else:
		context.data["conversation"] = state


func tick(context: BustleActionContext, _delta: float) -> Status:
	if context.data.has("failure"):
		context.failure = StringName(context.data["failure"])
		return Status.FAILED
	var state: Dictionary = context.data.get("conversation", {})
	if conversation.is_finished(state):
		return Status.DONE
	context.output["talk_to"] = StringName(state["b"])
	if context.now_minutes < conversation.next_minute(state):
		return Status.RUNNING
	var result := conversation.step(state)
	if not result.get("ok", false):
		context.failure = result.get("reason", &"nothing_to_say")
		return Status.FAILED
	context.output["turn"] = result
	return Status.DONE if conversation.is_finished(state) else Status.RUNNING
