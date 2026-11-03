# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDispositionPort
extends RefCounted

## How one actor regards another: hostile, neutral or friendly. A host plugs in its own source
## (factions, reputation) by extending this class and overriding [method disposition]. The
## standalone default reads a [BustleDispositionTable] if one is given, and is neutral otherwise.
## @experimental

## How one actor regards another.
enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }

## The table the default reads, or null for neutral everywhere.
var table: BustleDispositionTable


func _init(p_table: BustleDispositionTable = null) -> void:
	table = p_table


## How actor [param a_id] (in group [param a_group]) regards actor [param b_id] (in group
## [param b_group]).
## @experimental
func disposition(a_id: StringName, a_group: StringName, b_id: StringName, b_group: StringName) -> Disposition:
	if table == null:
		return Disposition.NEUTRAL
	return table.lookup(a_id, a_group, b_id, b_group)
