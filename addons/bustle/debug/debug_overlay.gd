# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDebugOverlay
extends Node3D

## A world overlay for developing: a label above each agent's attached body with its ring, band,
## goal, step, top 3 scores and need inputs (from [BustleInspector]). Toggle [member enabled] at
## runtime. Off, it stops processing and frees its labels, so it costs nothing. It can't be enabled
## in a release build (see [BustleDebug]).
## @experimental

## How high above a body its label floats, in metres.
@export var label_height: float = 2.2

## The society it shows. Set before enabling.
var society: BustleSociety
## True while it shows labels. Setting it on in a release build leaves it off.
var enabled: bool = false:
	set(value):
		enabled = value and BustleDebug.is_available()
		set_process(enabled)
		if not enabled:
			_clear()

## Its inspector (exposed so tests can count snapshots).
var inspector := BustleInspector.new()

var _labels: Dictionary[StringName, Label3D] = {}


func _ready() -> void:
	set_process(enabled)


func _process(_delta: float) -> void:
	refresh()


## Updates every label now (what each frame does while enabled). Does nothing when disabled.
## @experimental
func refresh() -> void:
	if not enabled or society == null:
		return
	var seen := {}
	for id: StringName in society.agent_ids():
		var body := society.get_agent(id).body()
		if body == null or not body.is_inside_tree():
			continue
		seen[id] = true
		var label: Label3D = _labels.get(id, null)
		if label == null:
			label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			add_child(label)
			_labels[id] = label
		label.global_position = body.global_position + Vector3.UP * label_height
		label.text = text_for(inspector.snapshot(society, id))
	for id: StringName in _labels.keys():
		if not seen.has(id):
			_labels[id].queue_free()
			_labels.erase(id)


## The number of labels shown.
## @experimental
func label_count() -> int:
	return _labels.size()


## The label text for a [method BustleInspector.snapshot].
## @experimental
static func text_for(snap: Dictionary) -> String:
	if snap.get("missing", true):
		return "%s: missing" % snap.get("agent", "")
	var lines := PackedStringArray()
	lines.append("%s  ring: n/a" % snap["agent"])
	var doing: String = ("order " + String(snap["order"])) if snap["order"] != &"" else String(snap["goal"])
	lines.append("%s %s" % [snap["band"], doing])
	var step: Variant = snap["step"]
	if step != null:
		lines.append("step %d %s (%s)" % [step["index"], step["action"], step["state"]])
	for row: Dictionary in snap["top"]:
		lines.append("  %s %.3f%s" % [row["goal"], row["raw"], "" if row["eligible"] else " x"])
	var inputs: Dictionary = snap["needs"]["inputs"]
	if not inputs.is_empty():
		lines.append("needs (inputs): " + ", ".join(inputs.keys().map(func(k: StringName) -> String:
			return "%s %.2f" % [String(k).trim_prefix("need."), inputs[k]])))
	return "\n".join(lines)


func _clear() -> void:
	for label: Label3D in _labels.values():
		label.queue_free()
	_labels.clear()
