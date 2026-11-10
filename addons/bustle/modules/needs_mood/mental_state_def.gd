# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMentalStateDef
extends Resource

## One mental state, as data: what it does ([member behaviour]), whether it's a low or a high
## state, how personality weighs it, what circumstance it needs and how long it lasts. What a
## state can do is fixed by [enum Behaviour]; there is no field for harming anyone, the agent
## included, or for any intent.
## @experimental

## Everything a mental state can be. Nothing else can be expressed.
enum Behaviour {
	WITHDRAW, ## Keeps to itself.
	SULK, ## Curt and slow.
	WANDER, ## Walks about aimlessly.
	BINGE, ## Indulges in something it knows of.
	LASH_OUT, ## Insults or quarrels with someone it dislikes, nearby. Words only.
	HIGH_SPIRITS, ## Sociable and generous.
	INSPIRED, ## Works faster or better.
}

## A state for low mood.
const LOW := &"low"
## A state for high mood.
const HIGH := &"high"
## No circumstance needed.
const NONE := &""
## Needs an indulgence the agent knows of.
const INDULGENCE := &"indulgence"
## Needs someone it dislikes nearby.
const TARGET := &"target"

## Its id.
@export var id: StringName = &""
## What it does.
@export var behaviour: Behaviour = Behaviour.WITHDRAW
## [constant LOW] or [constant HIGH].
@export var kind: StringName = LOW
## Slider → weight; the score is [code]Σ weight × (slider − 50) / 100[/code].
@export var weights: Dictionary[StringName, float] = {}
## The circumstance it needs: [constant NONE], [constant INDULGENCE] or [constant TARGET].
@export var needs: StringName = NONE
## How long it lasts unless mood ends it sooner, in game hours.
@export var duration_hours: float = 8.0


## True when it can be used: an id, a known kind and circumstance, known sliders with finite
## weights, and a positive finite duration.
## @experimental
func is_valid() -> bool:
	if id == &"" or not kind in [LOW, HIGH] or not needs in [NONE, INDULGENCE, TARGET]:
		return false
	for slider: StringName in weights:
		if not BustlePersonality.SLIDERS.has(slider) or not is_finite(weights[slider]):
			return false
	return is_finite(duration_hours) and duration_hours > 0.0


## [member duration_hours] in whole game minutes, at least 1.
## @experimental
func duration_minutes() -> int:
	return maxi(1, roundi(duration_hours * 60.0))


## A state def with these values.
## @experimental
static func make(p_id: StringName, p_behaviour: Behaviour, p_kind: StringName, p_weights: Dictionary[StringName, float],
		p_hours: float, p_needs: StringName = NONE) -> BustleMentalStateDef:
	var def := BustleMentalStateDef.new()
	def.id = p_id
	def.behaviour = p_behaviour
	def.kind = p_kind
	def.weights = p_weights
	def.duration_hours = p_hours
	def.needs = p_needs
	return def
