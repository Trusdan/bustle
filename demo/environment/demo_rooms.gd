# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## EXPERIMENTAL DEMO DATA, NOT CANON. Three example rooms and their scores, for trying the
## environment port, room thoughts and the indoors and outdoors needs in the demos and tests. They
## are not part of the addon: nothing in [code]addons/bustle/[/code] loads them, the demos don't
## install them unless asked, and a host replaces them with its own rooms and scores. The names
## and numbers may change in any release.
## [br][br]
## [method install] gives a port the scores; it puts nobody in a room. Placing agents is the host's
## call ([method BustleEnvironmentPort.set_room]), and an agent in one of these rooms is indoors.
## Preload this script; it has no class name, so it adds nothing to the global class list.

## A plain room of a house: fairly pleasant, comfortable and clean.
const HOUSE_ROOM := &"house_room"
## A working room: plain, a little cramped and dusty, somewhat impressive for its tools.
const WORKSHOP := &"workshop"
## A cellar: bare, cramped and dirty. Impressiveness is left unset, to show that an unset score
## isn't 0.
const CELLAR := &"cellar"

## Room → score → value, each from 0 to 1 (see [constant BustleEnvironmentPort.SCORES]).
const ROOMS: Dictionary = {
	HOUSE_ROOM: {&"beauty": 0.6, &"comfort": 0.7, &"cleanliness": 0.7, &"impressiveness": 0.3},
	WORKSHOP: {&"beauty": 0.3, &"comfort": 0.4, &"cleanliness": 0.35, &"impressiveness": 0.5},
	CELLAR: {&"beauty": 0.1, &"comfort": 0.2, &"cleanliness": 0.2},
}


## The demo room ids, sorted.
static func rooms() -> Array[StringName]:
	var out: Array[StringName] = []
	for room: Variant in ROOMS:
		out.append(StringName(room))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## [param room]'s demo scores (a copy), or empty for a room that isn't one of these.
static func scores_of(room: StringName) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	out.assign(ROOMS.get(room, {}))
	return out


## Sets every demo room's scores on [param port], replacing any scores those rooms had. Other rooms
## and every agent's room are left as they were. False, changing nothing, when [param port] is null.
static func install(port: BustleEnvironmentPort) -> bool:
	if port == null:
		return false
	for room: StringName in rooms():
		port.set_scores(room, ROOMS[room])
	return true
