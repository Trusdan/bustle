# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceptionProfile
extends Resource

## How one kind of observer notices a target: what it senses, how fast its [BustleDetectionMeter] fills
## and empties, and when it changes state. A project supplies one [code].tres[/code] per kind of
## observer; the defaults here are PROPOSED tuning, not final values.
## @experimental

## What light sight needs.
enum SightLight {
	## Sight works by the target's visibility from ambient and placed light.
	AMBIENT,
	## Sight works only on targets that carry a lit light of their own
	## ([member BustleSenseTarget.carries_light]). Hearing is unaffected.
	CARRIED_LIGHT_ONLY,
}

## Notices the target by sight.
@export var sees := true
## Notices the target by its noise.
@export var hears := true
## How far it sees, in metres.
@export var sight_range: float = 15.0
## The full width of the inner view cone, in degrees. Sight fills at the full rate inside it.
@export var sight_angle_deg: float = 90.0
## The full width of the outer (peripheral) cone, in degrees. Between the inner cone and this one
## sight fills at half the rate. At or below [member sight_angle_deg] there is no peripheral band.
@export var peripheral_angle_deg: float = 150.0
## What light its sight needs.
@export var sight_light: SightLight = SightLight.AMBIENT
## Multiplies the target's noise radius before the distance check.
@export var hearing_scale: float = 1.0
## Fill per second from sight, at visibility 1.0 and point-blank range.
@export var fill_rate_sight: float = 1.0
## Fill per second from hearing, at point-blank range.
@export var fill_rate_hearing: float = 0.8
## Loss per second while it neither sees nor hears the target.
@export var decay_rate: float = 0.15
## The meter level (0..1) at which it becomes suspicious.
@export var suspicious_at: float = 0.3
## The meter level (0..1) at which it becomes alert.
@export var alert_at: float = 0.9
## How long it searches with nothing new before it is unaware again, in seconds.
@export var search_time: float = 8.0
## How long an alert observer can neither see nor hear the target before it starts searching,
## in seconds.
@export var lose_track_time: float = 4.0
## How many times per second a perceiver with this profile senses (throttling; 0 or less: every
## frame).
@export var perception_hz: float = 10.0
