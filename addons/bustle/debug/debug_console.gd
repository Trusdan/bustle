# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDebugConsole
extends RefCounted

## Text commands for inspecting and steering a [BustleSociety] while developing. [method run] takes
## one line and returns the answer as text. It does nothing in release builds (see [BustleDebug]).
##
## - [code]help[/code], [code]agents[/code]
## - [code]why <agent> [goal] [option][/code]: the last tick's top candidates, or one candidate's
##   score breakdown, straight from the scorer.
## - [code]need <agent>[/code]: the need inputs the agent was last given. There is no needs module
##   yet, so needs can't be set here.
## - [code]order <agent>[/code] lists the queue; [code]order <agent> <sequence> [forced][/code]
##   queues one of [member sequences]; [code]order <agent> cancel <order_id>[/code] cancels one.
## @experimental

## The answer in a release build.
const NOT_AVAILABLE := "debug tools are not available in this build"
## The answer to malformed input.
const USAGE := "usage: help | agents | why <agent> [goal] [option] | need <agent> | order <agent> [<sequence> [forced] | cancel <order>]"

## The society it works on.
var society: BustleSociety
## Sequence name → sequence, for the [code]order[/code] command. Supplied by the host.
var sequences: Dictionary[StringName, BustleActionSequence] = {}

var _inspector := BustleInspector.new()
var _next_order: int = 1


func _init(p_society: BustleSociety = null) -> void:
	society = p_society


## Runs one command line and returns its answer.
## @experimental
func run(line: String) -> String:
	if not BustleDebug.is_available():
		return NOT_AVAILABLE
	if society == null:
		return "no society"
	var words := Array(line.strip_edges().split(" ", false))
	if words.is_empty():
		return USAGE
	var command: String = words.pop_front()
	match command:
		"help":
			return USAGE
		"agents":
			return ", ".join(society.agent_ids().map(func(id: StringName) -> String: return String(id)))
		"why":
			return _why(words)
		"need":
			return _need(words)
		"order":
			return _order(words)
	return "unknown command: %s\n%s" % [command, USAGE]


func _agent(words: Array) -> BustleNpcState:
	return society.get_agent(StringName(words[0])) if not words.is_empty() else null


func _why(words: Array) -> String:
	if words.is_empty() or words.size() > 3:
		return USAGE
	var state := _agent(words)
	if state == null:
		return "no agent %s" % words[0]
	if state.brain.last_intent == null:
		return "%s hasn't thought yet" % words[0]
	if words.size() >= 2:
		var detail := BustleInspector.breakdown(state.brain, StringName(words[1]), StringName(words[2]) if words.size() == 3 else &"")
		if not detail["found"]:
			return "no candidate %s on the last tick" % " ".join(words.slice(1))
		var lines := PackedStringArray(["%s %s: raw %.4f, selection %.4f, %s" % [detail["goal"], detail["band"],
			detail["raw"], detail["selection"], "eligible" if detail["eligible"] else "not eligible"]])
		for reason: Dictionary in detail["reasons"]:
			lines.append("  %s" % reason)
		return "\n".join(lines)
	var lines := PackedStringArray()
	for row: Dictionary in BustleInspector.top(state.brain, 3):
		lines.append("%s%s %s raw %.4f selection %.4f%s" % [row["goal"], "/" + String(row["option"]) if row["option"] != &"" else "",
			row["band"], row["raw"], row["selection"], "" if row["eligible"] else " (not eligible)"])
	return "\n".join(lines) if not lines.is_empty() else "no candidates on the last tick"


func _need(words: Array) -> String:
	if words.is_empty():
		return USAGE
	var state := _agent(words)
	if state == null:
		return "no agent %s" % words[0]
	if words.size() > 1:
		return "needs can't be set: the needs module isn't installed"
	var needs := BustleInspector.needs(state.brain)
	var inputs: Dictionary = needs["inputs"]
	var parts := PackedStringArray()
	for key: StringName in inputs:
		parts.append("%s %.2f" % [key, inputs[key]])
	return "needs module not installed; last need inputs: %s" % (", ".join(parts) if not parts.is_empty() else "none")


func _order(words: Array) -> String:
	if words.is_empty():
		return USAGE
	var state := _agent(words)
	if state == null:
		return "no agent %s" % words[0]
	if words.size() == 1:
		var rows := BustleInspector.orders(state.brain)
		return "no orders" if rows.is_empty() else ", ".join(rows.map(func(r: Dictionary) -> String:
			return "%s%s%s" % [r["id"], " forced" if r["forced"] else "", " (active)" if r["active"] else ""]))
	if words[1] == "cancel":
		if words.size() != 3:
			return USAGE
		return "cancelled %s" % words[2] if state.brain.orders.cancel(StringName(words[2])) else "no order %s" % words[2]
	if words.size() > 3 or (words.size() == 3 and words[2] != "forced"):
		return USAGE
	if sequences.is_empty():
		return "no sequences registered"
	var sequence: BustleActionSequence = sequences.get(StringName(words[1]), null)
	if sequence == null:
		return "no sequence %s" % words[1]
	var id := StringName("console_%d" % _next_order)
	_next_order += 1
	var reason := state.brain.order(BustleOrder.new(id, sequence, &"", words.size() == 3))
	return "queued %s" % id if reason == &"" else "refused: %s" % reason
