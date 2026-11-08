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


func _init(p_id: StringName = &"", p_sequence: BustleActionSequence = null, p_option_id: StringName = &"",
		p_forced: bool = false) -> void:
	id = p_id
	sequence = p_sequence
	option_id = p_option_id
	forced = p_forced
