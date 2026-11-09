# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleInteractionDef
extends Resource

## One kind of interaction between two agents, as data (a greeting, a chat, kind words, a slight,
## an insult): how much it moves each side's opinion of the other, for how long, how much the pair's
## compatibility and each side's mood bend that, and the thoughts it leaves. See
## [method BustleSocialInteractions.outcome].
## @experimental

## Its id; also the verb of the deed it records.
@export var id: StringName = &""
## How much the recipient's opinion of the initiator moves.
@export var recipient_value: float = 0.0
## How much the initiator's opinion of the recipient moves.
@export var initiator_value: float = 0.0
## Up to this much is added or taken away at random (seeded per pair, minute and interaction).
@export var spread: float = 0.0
## How much compatibility bends the values, like mood: a compatible pair gains more and loses less,
## an incompatible pair the reverse. A gain is multiplied by
## [code]1 + compatibility × compatibility_scale[/code], a loss by
## [code]1 − compatibility × compatibility_scale[/code] (never below 0).
@export var compatibility_scale: float = 0.5
## How much each side's mood bends its own value: a good mood (above 50) makes gains larger and
## losses smaller, a low mood the reverse, by up to this share at the ends of the scale.
@export var mood_scale: float = 0.3
## Game days the opinion entries last.
@export var days: float = 3.0
## A thought for the recipient (a mood module thought definition), or null.
@export var recipient_thought: Resource
## A thought for the initiator, or null.
@export var initiator_thought: Resource
## Its tags (for later choice by weight and mood).
@export var tags: Array[StringName] = []


## True when it can be used: an id, finite numbers, a non-negative spread and scales, and a
## duration above 0 and at most the store's limit of a million days.
## @experimental
func is_valid() -> bool:
	for value: float in [recipient_value, initiator_value, spread, compatibility_scale, mood_scale, days]:
		if not is_finite(value):
			return false
	return id != &"" and spread >= 0.0 and compatibility_scale >= 0.0 and mood_scale >= 0.0 and days > 0.0 \
			and days <= 1.0e6
