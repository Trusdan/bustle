# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleVisibilityModel
extends RefCounted

## How visible a target is: the light curve × posture × movement × a clothing factor, times the
## stealth-skill multiplier, clamped to [code]min_visibility..max_visibility[/code]. 1.0 is a
## standing, walking target in full light with neutral clothing and no skill. It keeps no state;
## the numbers come from [BustleStealthRules].
## @experimental

## The numbers.
var rules: BustleStealthRules


func _init(p_rules: BustleStealthRules = null) -> void:
	rules = p_rules if p_rules != null else BustleStealthRules.new()


## The target's visibility. [param light_level] is 0..1 (from a [BustleLightProbe]);
## [param wear_factor] is the project's clothing value (1.0 is neutral); [param skill] is the
## target's stealth skill.
func compute(light_level: float, posture: BustleStealthRules.Posture, movement: BustleStealthRules.Movement, wear_factor: float = 1.0, skill: float = 0.0) -> float:
	var value := rules.light_factor(light_level) * rules.posture_factor(posture) \
		* rules.movement_factor(movement) * maxf(wear_factor, 0.0)
	value *= rules.skill_visibility_multiplier(skill)
	return clampf(value, rules.min_visibility, rules.max_visibility)
