# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSenseTarget
extends RefCounted

## What the project reports about one target to one observer each tick. The project casts the
## sight ray and fills in [member line_of_sight]; the core never touches physics.
## @experimental

## Where the target is.
var position := Vector3.ZERO
## How visible it is (from [BustleVisibilityModel]); 1.0 is a standing, walking target in full light.
var visibility: float = 1.0
## How far its noise carries, in metres (from [BustleNoiseModel]).
var noise_radius: float = 0.0
## True when nothing blocks this observer's view of the target.
var line_of_sight := true
## True while the target carries a lit light of its own (a torch, a lantern). Profiles whose
## [member BustlePerceptionProfile.sight_light] is
## [constant BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY] see only such targets.
var carries_light := false


func _init(p_position: Vector3 = Vector3.ZERO, p_visibility: float = 1.0, p_noise_radius: float = 0.0, p_line_of_sight: bool = true, p_carries_light: bool = false) -> void:
	position = p_position
	visibility = p_visibility
	noise_radius = p_noise_radius
	line_of_sight = p_line_of_sight
	carries_light = p_carries_light
