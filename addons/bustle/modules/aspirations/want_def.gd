# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWantDef
extends Resource

## One short-lived want, as data: who it suits (personality and circumstances), when it's fulfilled,
## how long it lasts and the thought fulfilling it gives. [BustleAspirations] reads it. Every
## circumstance, progress input and fact is a name the host fills each update. Bustle ships none.
## @experimental

## Its id. Ties between equal scores break by id.
@export var id: StringName = &""
## False: never taken automatically (a host may still post it).
@export var auto: bool = true
## Slider → weight; its score for the automatic slot is [code]Σ weight × (slider − 50) / 100[/code].
@export var weights: Dictionary[StringName, float] = {}
## Circumstances that must all be true for it to be taken automatically.
@export var requires: Array[StringName] = []
## A fact that fulfils it. Empty: only the progress line (or the host's
## [method BustleAspirations.fulfill]).
@export var done_fact: StringName = &""
## A number that fulfils it once it reaches [member target]. Empty: no progress line.
@export var progress_input: StringName = &""
## What [member progress_input] must reach.
@export var target: float = 0.0
## Game hours it lasts before it expires unfulfilled.
@export var duration_hours: float = 12.0
## Game hours after it ends (fulfilled or expired) before the same agent takes it again
## automatically.
@export var cooldown_hours: float = 24.0
## Aspiration points the agent earns when it's fulfilled.
@export var points: int = 0
## Goal → multiplier while it's active (see [method BustleAspirations.boost]). Each is at least 1,
## and is capped by [member BustleAspirationConfig.max_want_boost].
@export var boosts: Dictionary[StringName, float] = {}
## With one, only candidates whose option is this are boosted. Empty: any option.
@export var boost_option: StringName = &""
## The satisfaction thought added when it's fulfilled (a timed [code]BustleThoughtDef[/code] from
## the needs_mood module), or null.
@export var thought: Resource = null


## True when it can be used: an id, known sliders with finite weights, a finite target, a positive
## finite duration, a non-negative finite cooldown, points of at least 0, and boosts that are finite
## and at least 1.
## @experimental
func is_valid() -> bool:
	if id == &"" or not is_finite(target) or not is_finite(duration_hours) or duration_hours <= 0.0:
		return false
	if not is_finite(cooldown_hours) or cooldown_hours < 0.0 or points < 0:
		return false
	for goal: StringName in boosts:
		if not is_finite(boosts[goal]) or boosts[goal] < 1.0:
			return false
	for slider: StringName in weights:
		if not BustlePersonality.SLIDERS.has(slider) or not is_finite(weights[slider]):
			return false
	return true


## True when [param inputs] say it's fulfilled: [member done_fact] is true, or
## [member progress_input] has reached [member target].
## @experimental
func is_done(inputs: Dictionary) -> bool:
	if done_fact != &"" and bool(inputs.get(done_fact, false)):
		return true
	return progress_input != &"" and float(inputs.get(progress_input, -INF)) >= target
