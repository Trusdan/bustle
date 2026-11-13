# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleEnvironmentPort
extends RefCounted

## Rooms and surroundings. The host computes its rooms and their scores; Bustle never detects rooms
## or looks at what is in them. A host either extends this (overriding [method room_of] and
## [method scores]) or fills the built-in store with [method set_room] and [method set_scores].
## The standalone default has no rooms and no scores.
## @experimental

## The room scores, each from 0 to 1. A score a room doesn't have is unset, not 0.
const SCORES: Array[StringName] = [&"beauty", &"comfort", &"cleanliness", &"impressiveness"]

## Agent id → room.
var _rooms: Dictionary[StringName, StringName] = {}
## Room → score → value.
var _scores: Dictionary[StringName, Dictionary] = {}


## The room [param id] is in, or empty.
## @experimental
func room_of(id: StringName) -> StringName:
	return _rooms.get(id, &"")


## [param room]'s scores (a subset of [constant SCORES], each from 0 to 1). Empty for no room or an
## unscored one.
## @experimental
func scores(room: StringName) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	out.assign(_scores.get(room, {}))
	return out


## Puts [param id] in [param room] (empty: in no room). False for an empty id.
## @experimental
func set_room(id: StringName, room: StringName) -> bool:
	if id == &"":
		return false
	if room == &"":
		_rooms.erase(id)
	else:
		_rooms[id] = room
	return true


## Replaces [param room]'s scores with [param values] (score → value; empty clears them). False (and
## no change) for an empty room, a score not in [constant SCORES] or a value outside 0 to 1.
## @experimental
func set_scores(room: StringName, values: Dictionary) -> bool:
	if room == &"":
		return false
	var clean: Dictionary[StringName, float] = {}
	for key: Variant in values:
		var value: Variant = values[key]
		if not (key is String or key is StringName) or not SCORES.has(StringName(key)) \
				or not (value is float or value is int) or not is_finite(float(value)) \
				or float(value) < 0.0 or float(value) > 1.0:
			return false
		clean[StringName(key)] = float(value)
	if clean.is_empty():
		_scores.erase(room)
	else:
		_scores[room] = clean
	return true


## The built-in store as plain data: [code]{"rooms": {agent: room}, "scores": {room: {score:
## value}}}[/code], sorted. A host that overrides the lookups saves its own rooms.
## @experimental
func export_state() -> Dictionary:
	var rooms := {}
	for id: StringName in _sorted(_rooms.keys()):
		rooms[String(id)] = String(_rooms[id])
	var scored := {}
	for room: StringName in _sorted(_scores.keys()):
		var row := {}
		for key: StringName in _sorted(_scores[room].keys()):
			row[String(key)] = _scores[room][key]
		scored[String(room)] = row
	return {"rooms": rooms, "scores": scored}


## Restores [method export_state], replacing the store. False (and nothing changes) for malformed
## data, an unknown score or a value outside 0 to 1.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("rooms") is Dictionary or not saved.get("scores") is Dictionary:
		return false
	var probe := BustleEnvironmentPort.new()
	for id: Variant in saved["rooms"]:
		var room: Variant = saved["rooms"][id]
		if not id is String or not room is String or String(id).is_empty() or String(room).is_empty():
			return false
		probe.set_room(StringName(id), StringName(room))
	for room: Variant in saved["scores"]:
		var values: Variant = saved["scores"][room]
		if not room is String or not values is Dictionary or (values as Dictionary).is_empty() \
				or not probe.set_scores(StringName(room), values):
			return false
	_rooms = probe._rooms
	_scores = probe._scores
	return true


static func _sorted(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ids)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
