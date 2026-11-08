# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScoringConfig
extends Resource

## The scorer's curves and settings. Anything left unset is neutral (a factor of 1.0, or the
## identity curve for a need), so nothing here is tuning until a project sets it.
## @experimental

## Need name → its response curve over pressure (0 to 1). A need with no curve uses its pressure,
## clamped to 0..1.
@export var need_curves: Dictionary[StringName, Curve] = {}
## The distance falloff, a curve over metres. Null is no falloff (1.0).
@export var distance_curve: Curve
## Tag → a curve over the [code]mood[/code] input, multiplied in for options with that tag. Tags
## with no curve, or no mood input, give 1.0.
@export var mood_curves: Dictionary[StringName, Curve] = {}
## How close to the best score a candidate must be to be picked: within this part of it.
@export var pick_window: float = 0.10
## An optional preview of how an option would make the agent feel:
## [code]func(ad: BustleAdvertisement, context: BustleScoreContext) -> float[/code]. Unset is 1.0.
var expected_thought_gain: Callable = Callable()
