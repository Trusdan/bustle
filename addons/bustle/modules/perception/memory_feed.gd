# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMemoryFeed
extends RefCounted

## Writes what agents perceive into their memories, driven by events: each time a perceiver
## becomes alert to a target ([signal BustlePerceptionWorld.perception_changed]), the perceiver's
## [BustleMemory] notes where the target is ([constant BustleMemory.SAW]), and when it loses track
## (back to unaware) it notes where the target was last known. Nothing polls.
## @experimental

## (id) → that agent's [BustleMemory], or null for agents without one.
var memory_of: Callable = Callable()
## () → the current game minute.
var clock: Callable = Callable()
## (id) → the area an actor is in. Empty: every actor is in one unnamed area.
var area_of: Callable = Callable()

var _world: BustlePerceptionWorld


func _init(world: BustlePerceptionWorld, p_memory_of: Callable = Callable(), p_clock: Callable = Callable()) -> void:
	_world = world
	memory_of = p_memory_of
	clock = p_clock
	_world.perception_changed.connect(_on_perception_changed)


## Stops listening.
## @experimental
func disconnect_world() -> void:
	if _world.perception_changed.is_connected(_on_perception_changed):
		_world.perception_changed.disconnect(_on_perception_changed)


func _on_perception_changed(perceiver_id: StringName, target_id: StringName, _old: BustleDetectionMeter.State, new: BustleDetectionMeter.State) -> void:
	if not memory_of.is_valid():
		return
	var memory := memory_of.call(perceiver_id) as BustleMemory
	if memory == null:
		return
	var now := int(clock.call()) if clock.is_valid() else 0
	var area := StringName(area_of.call(target_id)) if area_of.is_valid() else &""
	if new == BustleDetectionMeter.State.ALERT:
		var target := _world.actor(target_id)
		memory.note(BustleMemory.PERSON, target_id, area, target.position if target != null else null, BustleMemory.SAW, now)
	elif new == BustleDetectionMeter.State.UNAWARE:
		var last: Variant = _world.last_known(perceiver_id, target_id)
		if last is Vector3:
			memory.note(BustleMemory.PERSON, target_id, area, last, BustleMemory.SAW, now)
