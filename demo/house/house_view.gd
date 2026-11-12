# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends Control

## Runs the house demo in real time and shows what each resident is doing and how its needs stand.
## The same run as the tests, from [code]demo/house/house.gd[/code].

const House := preload("res://demo/house/house.gd")

## Game minutes that pass each real second.
@export var minutes_per_second: float = 60.0
## The run's world seed.
@export var world_seed: int = 1

## The run.
var house: RefCounted
var _carry: float = 0.0
var _intents: Dictionary = {}


func _ready() -> void:
	house = House.build(world_seed)
	($Back as Button).pressed.connect(func() -> void: get_tree().change_scene_to_file("res://demo/main.tscn"))
	_show()


func _process(delta: float) -> void:
	_carry += delta * minutes_per_second
	while _carry >= house.step_minutes:
		_carry -= house.step_minutes
		_intents = house.step()
	_show()


func _show() -> void:
	var lines := PackedStringArray()
	lines.append("Day %d, %02d:%02d" % [house.now / 1440 + 1, house.now % 1440 / 60, house.now % 60])
	for id: StringName in house.agent_ids():
		var intent: BustleIntent = _intents.get(id)
		var doing := "starting"
		if intent != null:
			doing = "away at work" if house.is_away(id) else "idle" if intent.idle \
				else "%s %s" % [intent.goal_id if intent.order_id == &"" else intent.order_id, intent.option_id]
		var needs: BustleNeedSet = house.needs_of(id)
		var parts := PackedStringArray()
		for need: StringName in needs.ids():
			parts.append("%s %.2f" % [need, needs.pressure(need)])
		lines.append("%s: %s  (%s)" % [id, doing, ", ".join(parts)])
	($Status as Label).text = "\n".join(lines)
