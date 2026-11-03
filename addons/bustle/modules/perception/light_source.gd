# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLightSource
extends RefCounted

## One point light, as [BustlePointLightProbe] sees it. Plain data; the project keeps it in step with
## whatever torch, candle or window it stands for.
## @experimental

## A free id, reported in [member BustleLightSample.sources].
var id: StringName = &""
## Where the light is.
var position := Vector3.ZERO
## How far it reaches, in metres. At or beyond this distance it adds nothing.
var range: float = 5.0
## The light it adds at its own position (0..1 is typical).
var energy: float = 1.0
## False: it adds nothing.
var enabled := true


func _init(p_id: StringName = &"", p_position: Vector3 = Vector3.ZERO, p_range: float = 5.0, p_energy: float = 1.0) -> void:
	id = p_id
	position = p_position
	range = p_range
	energy = p_energy


## The light it adds at [param point], ignoring anything in between.
func contribution(point: Vector3) -> float:
	if not enabled or range <= 0.0:
		return 0.0
	var distance := position.distance_to(point)
	if distance >= range:
		return 0.0
	var falloff := 1.0 - distance / range
	return energy * falloff * falloff
