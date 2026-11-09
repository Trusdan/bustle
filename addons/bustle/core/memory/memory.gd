# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMemory
extends RefCounted

## One agent's memory of where people, places and items are. Each entry is one subject of one
## kind ([constant PERSON], [constant PLACE], [constant ITEM]) with an area, maybe a position, its
## source ([constant SAW], [constant HEARD], [constant TOLD], [constant ROUTINE]) and a strength
## that halves every half-life of its kind ([BustleMemoryConfig]). An entry is forgotten when its
## strength falls below the config's threshold, and past capacity the weakest entry goes.
## [br][br]
## A new note about a subject replaces the old one when it is at least as strong as what is left
## of the old one, so a fresh sighting beats an old rumour but a rumour doesn't overwrite a fresh
## sighting. Time is whole game minutes.
## @experimental

## A person's whereabouts.
const PERSON := &"person"
## A place.
const PLACE := &"place"
## An item's whereabouts.
const ITEM := &"item"
## Seen first-hand.
const SAW := &"saw"
## Overheard.
const HEARD := &"heard"
## Told directly by someone.
const TOLD := &"told"
## Guessed from someone's routine.
const ROUTINE := &"routine"

## How it holds and forgets.
var config: BustleMemoryConfig

# "kind:subject" → {kind, subject, area, position (Vector3 or null), source, strength, at}.
var _entries: Dictionary[String, Dictionary] = {}


func _init(p_config: BustleMemoryConfig = null) -> void:
	config = p_config if p_config != null else BustleMemoryConfig.new()


## Notes where [param subject] (of [param kind]) is, at minute [param now]: [param area] and
## [param position] (null when unknown), from [param source]. Returns true when it was kept (see
## the class description); false for an empty subject, an unknown source or a weaker note.
## @experimental
func note(kind: StringName, subject: StringName, area: StringName, position: Variant, source: StringName, now: int) -> bool:
	var strength := config.strength_of(source)
	if subject == &"" or kind == &"" or strength <= 0.0 or not (position == null or position is Vector3):
		return false
	var key := _key(kind, subject)
	if _entries.has(key) and strength < _strength(_entries[key], now):
		return false
	_entries[key] = {"kind": kind, "subject": subject, "area": area, "position": position,
		"source": source, "strength": strength, "at": now}
	forget(now)
	while _entries.size() > maxi(config.capacity, 1):
		_entries.erase(_weakest(now))
	return true


## What is remembered about [param subject] at minute [param now], with its current strength:
## [code]{kind, subject, area, position, source, strength, at}[/code]; empty when nothing is (or it
## has faded below the threshold, in which case it is forgotten).
## @experimental
func recall(kind: StringName, subject: StringName, now: int) -> Dictionary:
	var key := _key(kind, subject)
	if not _entries.has(key):
		return {}
	var strength := _strength(_entries[key], now)
	if strength < config.forget_below:
		_entries.erase(key)
		return {}
	var out := _entries[key].duplicate()
	out["strength"] = strength
	return out


## How sure the agent is of [param subject]'s whereabouts at minute [param now], from 0 to 1.
## @experimental
func confidence(kind: StringName, subject: StringName, now: int) -> float:
	return float(recall(kind, subject, now).get("strength", 0.0))


## Drops every entry that has faded below the threshold by minute [param now].
## @experimental
func forget(now: int) -> void:
	for key: String in _entries.keys():
		if _strength(_entries[key], now) < config.forget_below:
			_entries.erase(key)


## The number of entries held (some may have faded since; see [method forget]).
## @experimental
func size() -> int:
	return _entries.size()


## The entries as plain data, sorted by key.
## @experimental
func export_state() -> Dictionary:
	var keys: Array[String] = _entries.keys()
	keys.sort()
	var out: Array = []
	for key: String in keys:
		var entry := _entries[key]
		var position: Variant = entry["position"]
		out.append({"kind": String(entry["kind"]), "subject": String(entry["subject"]), "area": String(entry["area"]),
			"position": [position.x, position.y, position.z] if position is Vector3 else null,
			"source": String(entry["source"]), "strength": entry["strength"], "at": entry["at"]})
	return {"entries": out}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("entries") is Array:
		return false
	var staged: Dictionary[String, Dictionary] = {}
	for item: Variant in saved["entries"]:
		if not item is Dictionary:
			return false
		var data: Dictionary = item
		for field: String in ["kind", "subject", "area", "source"]:
			if not data.get(field) is String:
				return false
		var at: Variant = data.get("at")
		if at is float and is_finite(at) and at == floorf(at):
			at = int(at)
		var strength: Variant = data.get("strength")
		if not at is int or not (strength is float or strength is int) or not is_finite(float(strength)):
			return false
		var position: Variant = data.get("position")
		if position is Array and (position as Array).size() == 3:
			for part: Variant in position:
				if not (part is float or part is int) or not is_finite(float(part)):
					return false
			position = Vector3(float(position[0]), float(position[1]), float(position[2]))
		elif position != null:
			return false
		var kind := StringName(data["kind"])
		var subject := StringName(data["subject"])
		staged[_key(kind, subject)] = {"kind": kind, "subject": subject, "area": StringName(data["area"]),
			"position": position, "source": StringName(data["source"]), "strength": clampf(float(strength), 0.0, 1.0), "at": at}
	if staged.size() > maxi(config.capacity, 1):
		return false
	_entries = staged
	return true


func _strength(entry: Dictionary, now: int) -> float:
	var age := maxf(float(now - int(entry["at"])), 0.0)
	return float(entry["strength"]) * pow(0.5, age / config.half_life_minutes(entry["kind"]))


func _weakest(now: int) -> String:
	var keys: Array[String] = _entries.keys()
	keys.sort()
	var weakest := keys[0]
	for key: String in keys:
		var a := _strength(_entries[key], now)
		var b := _strength(_entries[weakest], now)
		if a < b or (a == b and int(_entries[key]["at"]) < int(_entries[weakest]["at"])):
			weakest = key
	return weakest


static func _key(kind: StringName, subject: StringName) -> String:
	return "%s:%s" % [kind, subject]
