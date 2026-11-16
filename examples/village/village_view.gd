# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends Node2D

## Draws the village from [code]village.gd[/code] in real time: places as boxes, villagers as dots
## coloured by mood, each with what it is doing. The simulation is headless; this is only a view.

const Village := preload("res://village.gd")

## Game minutes that pass each real second.
@export var minutes_per_second: float = 40.0

## The simulation.
var village: RefCounted
var _carry: float = 0.0
var _labels: Dictionary[StringName, Label] = {}
var _clock: Label


func _ready() -> void:
	village = Village.new()
	_clock = Label.new()
	_clock.position = Vector2(16, 12)
	add_child(_clock)
	for id: StringName in village.get(&"society").agent_ids():
		var label := Label.new()
		label.add_theme_font_size_override(&"font_size", 13)
		add_child(label)
		_labels[id] = label
	_refresh()


func _process(delta: float) -> void:
	_carry += delta * minutes_per_second
	while _carry >= Village.STEP:
		_carry -= Village.STEP
		village.call(&"step")
	_refresh()


func _refresh() -> void:
	var now: int = village.call(&"now")
	_clock.text = "Day %d, %02d:%02d   (each dot is a villager; green is a good mood)" % [now / 1440 + 1, now % 1440 / 60, now % 60]
	var society: BustleSociety = village.get(&"society")
	var needs: Dictionary = village.get(&"needs")
	var moods: Dictionary = village.get(&"moods")
	var doing: Dictionary = village.get(&"doing")
	for id: StringName in _labels:
		var at := _flat(society.get_agent(id).position)
		var set: BustleNeedSet = needs[id]
		_labels[id].position = at + Vector2(12, -8)
		_labels[id].text = "%s: %s\nmood %d  food %.2f  rest %.2f  skill %.1f" % [id, doing[id],
				roundi((moods[id] as BustleMood).mood), set.pressure(&"food"), set.pressure(&"rest"),
				float(village.call(&"skill_level", id))]
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for place: StringName in Village.PLACES:
		var at := _flat(Village.PLACES[place])
		var rect := Rect2(at - Vector2(55, 35), Vector2(110, 70))
		draw_rect(rect, Color(0.25, 0.3, 0.35) if Village.ROOMS.has(place) else Color(0.3, 0.35, 0.25))
		draw_string(font, rect.position + Vector2(6, 16), String(place), HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var society: BustleSociety = village.get(&"society")
	var moods: Dictionary = village.get(&"moods")
	for id: StringName in _labels:
		var mood: float = (moods[id] as BustleMood).mood
		draw_circle(_flat(society.get_agent(id).position), 8.0, Color.RED.lerp(Color.GREEN, clampf(mood / 100.0, 0.0, 1.0)))


static func _flat(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)
