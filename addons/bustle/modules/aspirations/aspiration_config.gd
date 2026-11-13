# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAspirationConfig
extends Resource

## The want and fear library and its numbers, for [BustleAspirations]. Bustle ships no wants or
## fears: the host supplies both. The numbers are experimental defaults.
## @experimental

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


## The want [param id], or null.
## @experimental
func find_want(id: StringName) -> BustleWantDef:
	for def: BustleWantDef in wants:
		if def != null and def.id == id:
			return def
	return null


## The fear [param id], or null.
## @experimental
func find_fear(id: StringName) -> BustleFearDef:
	for def: BustleFearDef in fears:
		if def != null and def.id == id:
			return def
	return null
