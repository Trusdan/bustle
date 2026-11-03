# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleNoiseModel
extends RefCounted

## How far a target's noise carries, in metres: the project's movement radius × a surface factor ×
## a gear factor, times the stealth-skill multiplier. It keeps no state; the numbers come from
## [BustleStealthRules].
## @experimental

## The numbers.
var rules: BustleStealthRules


func _init(p_rules: BustleStealthRules = null) -> void:
	rules = p_rules if p_rules != null else BustleStealthRules.new()


## The noise radius. [param base_radius] comes from how the target moves (for example 1 m still,
## 7 m walking); [param surface_factor] from what it walks on (1.0 is neutral);
## [param gear_factor] from what it wears (1.0 is neutral); [param skill] is its stealth skill.
func compute(base_radius: float, surface_factor: float = 1.0, gear_factor: float = 1.0, skill: float = 0.0) -> float:
	var radius := maxf(base_radius, 0.0) * maxf(surface_factor, 0.0) * maxf(gear_factor, 0.0)
	return radius * rules.skill_noise_multiplier(skill)


## A one-off sound of [param radius] metres at [param position]. Stealth skill does not change it.
static func event_noise(radius: float, position: Vector3 = Vector3.ZERO, source_id: StringName = &"") -> BustleNoiseEvent:
	return BustleNoiseEvent.new(position, radius, source_id)
