# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleStealthRules
extends Resource

## The numbers behind [BustleVisibilityModel] and [BustleNoiseModel]. A project supplies its own as a
## [code].tres[/code]; the defaults here are PROPOSED tuning, not final values.
## @experimental

## How the target holds itself.
enum Posture { STANDING, CROUCHED }
## How the target moves.
enum Movement { STILL, WALKING, RUNNING }

## Visibility factor while standing.
@export var standing: float = 1.0
## Visibility factor while crouched.
@export var crouched: float = 0.55
## Visibility factor while still.
@export var still: float = 0.6
## Visibility factor while walking.
@export var walking: float = 1.0
## Visibility factor while running.
@export var running: float = 1.4
## Visibility removed per stealth-skill point, as a fraction (0.005 is 0.5% per point).
@export var skill_visibility_reduction_per_point: float = 0.005
## The lowest multiplier stealth skill can bring visibility to.
@export var skill_visibility_floor: float = 0.5
## Noise removed per stealth-skill point, as a fraction.
@export var skill_noise_reduction_per_point: float = 0.006
## The lowest multiplier stealth skill can bring noise to.
@export var skill_noise_floor: float = 0.4
## Maps a light level (0..1) to a visibility factor. Null: the level itself.
@export var light_curve: Curve
## The lowest visibility the model returns.
@export var min_visibility: float = 0.05
## The highest visibility the model returns.
@export var max_visibility: float = 1.5


func _init() -> void:
	light_curve = linear_light_curve(0.1, 1.0)


## A straight-line light curve from [param dark] at level 0 to [param bright] at level 1.
static func linear_light_curve(dark: float, bright: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = minf(0.0, minf(dark, bright))
	curve.max_value = maxf(1.0, maxf(dark, bright))
	curve.add_point(Vector2(0.0, dark), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, bright), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


## The visibility factor for [param posture].
func posture_factor(posture: Posture) -> float:
	return crouched if posture == Posture.CROUCHED else standing


## The visibility factor for [param movement].
func movement_factor(movement: Movement) -> float:
	match movement:
		Movement.STILL:
			return still
		Movement.RUNNING:
			return running
	return walking


## The visibility factor for a light [param level] (clamped to 0..1).
func light_factor(level: float) -> float:
	var clamped := clampf(level, 0.0, 1.0)
	if light_curve == null:
		return clamped
	return light_curve.sample(clamped)


## The multiplier stealth [param skill] leaves on visibility: never below the floor, never above 1.
func skill_visibility_multiplier(skill: float) -> float:
	return clampf(1.0 - maxf(skill, 0.0) * skill_visibility_reduction_per_point, skill_visibility_floor, 1.0)


## The multiplier stealth [param skill] leaves on noise: never below the floor, never above 1.
func skill_noise_multiplier(skill: float) -> float:
	return clampf(1.0 - maxf(skill, 0.0) * skill_noise_reduction_per_point, skill_noise_floor, 1.0)
