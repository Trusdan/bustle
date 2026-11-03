# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleNoiseEvent
extends RefCounted

## A one-off sound (a thrown object landing, a lock breaking) that the project broadcasts to
## observers. Anyone within [member radius] of [member position] can hear it.
## @experimental

## Where the sound happened.
var position := Vector3.ZERO
## How far it carries, in metres.
var radius: float = 0.0
## A free id for what made it.
var source_id: StringName = &""


func _init(p_position: Vector3 = Vector3.ZERO, p_radius: float = 0.0, p_source_id: StringName = &"") -> void:
	position = p_position
	radius = maxf(p_radius, 0.0)
	source_id = p_source_id


## True when a listener at [param listener] is within the radius, scaled by
## [param hearing_scale].
func reaches(listener: Vector3, hearing_scale: float = 1.0) -> bool:
	return position.distance_to(listener) <= radius * hearing_scale
