# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMemoryFeed
extends RefCounted

## Writes what agents perceive into their memories, driven by events: each time a perceiver
## becomes alert to a target ([signal BustlePerceptionWorld.perception_changed]), the perceiver's
## [BustleMemory] notes where the target is ([constant BustleMemory.SAW]), and when it loses track
## (back to unaware) it notes where the target was last known. Nothing polls.
## [br][br]
## Both halves of a loss-of-track note come from what the perceiver actually observed: the
## position is the world's last-known one, and the area is the one the target was in when this
## perceiver last became alert to it, never where the target is now. With no such observation, or
## no last-known position, nothing is written. The note is stamped with the minute track was lost.
## Suspicion alone writes nothing.
## @experimental

## (id) → that agent's [BustleMemory], or null for agents without one.
var memory_of: Callable = Callable()
## () → the current game minute.
var clock: Callable = Callable()
## (id) → the area an actor is in. Empty: every actor is in one unnamed area.
var area_of: Callable = Callable()

var _world: BustlePerceptionWorld
# "perceiver>target" → the target's area when that perceiver last became alert to it.
var _seen_area: Dictionary[String, StringName] = {}


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
	var key := "%s>%s" % [perceiver_id, target_id]
	if new == BustleDetectionMeter.State.ALERT:
		var area := StringName(area_of.call(target_id)) if area_of.is_valid() else &""
		_seen_area[key] = area
		var target := _world.actor(target_id)
		memory.note(BustleMemory.PERSON, target_id, area, target.position if target != null else null, BustleMemory.SAW, now)
	elif new == BustleDetectionMeter.State.UNAWARE:
		var last: Variant = _world.last_known(perceiver_id, target_id)
		if last is Vector3 and _seen_area.has(key):
			memory.note(BustleMemory.PERSON, target_id, _seen_area[key], last, BustleMemory.SAW, now)
		_seen_area.erase(key)
