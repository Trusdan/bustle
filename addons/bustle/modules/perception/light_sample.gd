# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLightSample
extends RefCounted

## How much light reaches one point, from a [BustleLightProbe].
## @experimental

## The light level, 0 (dark) to 1 (fully lit).
var level: float = 0.0
## The ids of the sources that added light, for debugging.
var sources: Array[StringName] = []


func _init(p_level: float = 0.0) -> void:
	level = clampf(p_level, 0.0, 1.0)
