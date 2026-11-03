# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceptionActor
extends RefCounted

## One actor in a [BustlePerceptionWorld]: what others can sense of it and, if it has a
## [member profile], how it senses them. The host (or a perception component) keeps the fields
## up to date; the world reads them when it ticks. Any actor can perceive any actor.
## @experimental

## A stable, host-supplied id (opaque to Bustle).
var id: StringName = &""
## Where its senses are (its eyes and ears) and where others sense it.
var position := Vector3.ZERO
## The way it faces (any length).
var forward := Vector3.FORWARD
## How it senses others. Null: it perceives nothing (it can still be perceived).
var profile: BustlePerceptionProfile
## False: others can't sense it.
var perceivable := true
## How visible it is to others (from [BustleVisibilityModel]).
var visibility: float = 1.0
## How far its noise carries, in metres (from [BustleNoiseModel]).
var noise_radius: float = 0.0
## True while it carries a lit light of its own.
var carries_light := false
## Its group, for dispositions ([BustleDispositionPort]).
var group: StringName = &""
## What it knows about the others. Only perceivers have entries.
var awareness := BustleAwareness.new()

var _due: float = 0.0


func _init(p_id: StringName = &"", p_profile: BustlePerceptionProfile = null) -> void:
	id = p_id
	profile = p_profile


## True when it has a profile and so senses others.
## @experimental
func perceives() -> bool:
	return profile != null


## Seconds between its senses ([member BustlePerceptionProfile.perception_hz]); 0: every tick.
## @experimental
func period() -> float:
	if profile == null or profile.perception_hz <= 0.0:
		return 0.0
	return 1.0 / profile.perception_hz


## The target others sense: its position, visibility, noise and carried light, with a clear line
## of sight until the world casts its ray.
## @experimental
func as_target() -> BustleSenseTarget:
	return BustleSenseTarget.new(position, visibility, noise_radius, true, carries_light)
