# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAdvertisement
extends RefCounted

## What one option (an object, a place, someone to talk to) offers an agent: how much it relieves
## each need, what it adds to each need as a side effect, its tags and how far away it is.
## @experimental

## The option's id, unique among one agent's options.
var option_id: StringName = &""
## Need name → relief (how much using it lowers that need).
var relief: Dictionary[StringName, float] = {}
## Need name → side effect (how much using it raises that need).
var adds: Dictionary[StringName, float] = {}
## Its tags (for example social, solitary, quiet).
var tags: Array[StringName] = []
## How far it is from the agent, in metres.
var distance: float = 0.0
## Where the option is (a [Vector3]), or null. When known, a held order measures its reach from its
## place to here rather than using [member distance].
var position: Variant = null


func _init(p_option_id: StringName = &"", p_relief: Dictionary[StringName, float] = {},
		p_adds: Dictionary[StringName, float] = {}, p_tags: Array[StringName] = [], p_distance: float = 0.0) -> void:
	option_id = p_option_id
	relief = p_relief
	adds = p_adds
	tags = p_tags
	distance = p_distance
