# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleJobSeeker
extends RefCounted

## One agent looking at the job board: its id and what the board's scores and gates read about it.
## The host fills it when the agent looks for work. Roles and skill levels come from the ports, not
## from here.
## @experimental

## The agent's id.
var id: StringName = &""
## Its personality, for [member BustleWorkType.priority_weights]. Null: every slider is 50.
var personality: BustlePersonality = null
## Its circumstances, for [member BustleWorkType.need_weights] (for example money need, 0 to 1).
var inputs: Dictionary[StringName, float] = {}
## Its tags, for [member BustleWorkType.required_tags].
var tags: Array[StringName] = []


func _init(p_id: StringName = &"", p_personality: BustlePersonality = null, p_inputs: Dictionary[StringName, float] = {}, p_tags: Array[StringName] = []) -> void:
	id = p_id
	personality = p_personality
	inputs = p_inputs
	tags = p_tags
