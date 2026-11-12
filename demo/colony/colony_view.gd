# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends Control

## Runs the colony demo in real time and shows what each settler is doing, its needs, its mood and
## any mental state. The same run as the tests, from [code]demo/colony/colony.gd[/code].

const Colony := preload("res://demo/colony/colony.gd")

## Game minutes that pass each real second.
@export var minutes_per_second: float = 60.0
## The run's world seed.
@export var world_seed: int = 1

## The run.
var colony: RefCounted
var _carry: float = 0.0
var _intents: Dictionary = {}


func _ready() -> void:
	colony = Colony.build(world_seed)
	($Back as Button).pressed.connect(func() -> void: get_tree().change_scene_to_file("res://demo/main.tscn"))
	_show()


func _process(delta: float) -> void:
	_carry += delta * minutes_per_second
	while _carry >= colony.step_minutes:
		_carry -= colony.step_minutes
		_intents = colony.step()
	_show()


func _show() -> void:
	var lines := PackedStringArray()
	var now: int = colony.now
	var weather := "  (cold snap)" if now >= Colony.COLD_START and now < Colony.COLD_START + Colony.COLD_MINUTES else ""
	lines.append("Day %d, %02d:%02d%s" % [now / 1440 + 1, now % 1440 / 60, now % 60, weather])
	for id: StringName in colony.agent_ids():
		var intent: BustleIntent = _intents.get(id)
		var doing := "starting"
		if intent != null:
			doing = "idle" if intent.idle else "%s %s" % [intent.goal_id, intent.option_id]
		var needs: BustleNeedSet = colony.needs_of(id)
		var parts := PackedStringArray()
		for need: StringName in needs.ids():
			parts.append("%s %.2f" % [need, needs.pressure(need)])
		var mood: BustleMood = colony.mood_of(id)
		var state: BustleMentalState = colony.mental_of(id)
		var feeling := "mood %.0f" % mood.mood if mood != null else ""
		if state != null and state.is_active():
			feeling += ", %s" % state.active()["id"]
		lines.append("%s: %s  (%s)  %s" % [id, doing, ", ".join(parts), feeling])
	($Status as Label).text = "\n".join(lines)
