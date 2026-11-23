# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAspirationConfig
extends Resource

## The want and fear library and its numbers, for [BustleAspirations]. Bustle ships no wants or
## fears: the host supplies both.

## The wants.
@export var wants: Array[BustleWantDef] = []
## The fears.
@export var fears: Array[BustleFearDef] = []
## How many wants an agent takes automatically at a time.
@export var auto_wants: int = 1
## The most wants an agent holds at a time, automatic and posted together.
@export var want_cap: int = 3
## The most a want boosts a goal, whatever its table says: smaller than an ambition's boosts, so a
## want never drowns an ambition.
@export var max_want_boost: float = 1.25
## Goals a want never boosts, whatever its table says (as for ambitions).
@export var never_boost: Array[StringName] = [&"steal", &"insult", &"quarrel", &"fight", &"attack"]
## The most aspiration points an agent can earn up to ([method BustleAspirations.add_points]
## adds no more than reaches it), or a negative number for no cap (the default, -1). The cap only
## limits earning: points already above it (from a save, or a cap lowered later) are kept, and the
## agent earns none until spending takes it below. What points buy stays the host's call.
## @experimental: Added after 1.0; it may be frozen in a later minor release.
@export var max_points: int = -1


## The want [param id], or null.
func find_want(id: StringName) -> BustleWantDef:
	for def: BustleWantDef in wants:
		if def != null and def.id == id:
			return def
	return null


## The fear [param id], or null.
func find_fear(id: StringName) -> BustleFearDef:
	for def: BustleFearDef in fears:
		if def != null and def.id == id:
			return def
	return null


## Why the numbers are out of order, or empty: [member auto_wants] above [member want_cap].
## Aspirations warn once about it and use the values as they are.
func validate() -> String:
	if auto_wants > want_cap:
		return "auto_wants is above want_cap"
	return ""
