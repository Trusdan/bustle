# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleOrder
extends RefCounted

## A task given to an agent from outside (a player or a quest): a sequence to run, optionally on a
## target. Ordinary orders sit in [constant BustleBands.ORDERED], below urgent self-care; a
## [member forced] one sits above everything, danger included.
## @experimental

## The order's id, unique in its agent's queue.
var id: StringName = &""
## What to do.
var sequence: BustleActionSequence
## Its target (an object, a place, a person), or empty.
var option_id: StringName = &""
## True to run even through danger.
var forced: bool = false


## A held order (a lock's): while it's at the front only CRITICAL, or URGENT that keeps to
## [member place], interrupts it (see [BustleBrain]).
var held: bool = false
## A held order's area, or empty.
var place: StringName = &""
## Where [member place] is (a [Vector3], set as [code]move_to[/code] when a step doesn't name one),
## or null.
var position: Variant = null
## How far (metres) an advertised option may be and still count as at [member place].
var reach: float = 5.0


func _init(p_id: StringName = &"", p_sequence: BustleActionSequence = null, p_option_id: StringName = &"",
		p_forced: bool = false) -> void:
	id = p_id
	sequence = p_sequence
	option_id = p_option_id
	forced = p_forced
