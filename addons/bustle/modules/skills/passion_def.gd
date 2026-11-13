# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePassionDef
extends Resource

## A passion for one skill, as data: how much faster an agent with it learns, which personality
## sliders make an agent take it up when it has no passion assigned, and an optional thought held
## while it does that skill's work. [BustleSkills] reads it. The numbers are experimental defaults.
## @experimental

## The skill it is a passion for; a [BustleSkillDef] with this id must be installed first.
@export var skill: StringName = &""
## Practice XP is multiplied by this while the agent has the passion.
@export var learn_mult: float = 1.5
## Slider → weight, for deriving the passion from personality. Its score is
## [code]Σ weight × (slider − 50) / 100[/code]; see [method BustleSkills.derived_passions]. Empty:
## never derived, only assigned.
@export var sliders: Dictionary[StringName, float] = {}
## A thought (a [code]BustleThoughtDef[/code] from the needs_mood module, with a duration of 0) held
## while the agent does this skill's work. Null: none. Without the needs_mood module, leave it null.
@export var thought: Resource = null


## True when it can be used: a skill id, a positive finite multiplier, and known sliders with finite
## weights.
## @experimental
func is_valid() -> bool:
	if skill == &"" or not is_finite(learn_mult) or learn_mult <= 0.0:
		return false
	for slider: StringName in sliders:
		if not BustlePersonality.SLIDERS.has(slider) or not is_finite(sliders[slider]):
			return false
	return true


## How strongly [param personality] matches it: [code]Σ weight × (slider − 50) / 100[/code]. 0 with
## no sliders or no personality.
## @experimental
func score(personality: BustlePersonality) -> float:
	if personality == null:
		return 0.0
	var total := 0.0
	for slider: StringName in sliders:
		total += sliders[slider] * (personality.slider(slider) - 50.0) / 100.0
	return total
