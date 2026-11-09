# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMoodConfig
extends Resource

## How mood moves, as data. Mood runs from [member min_mood] to [member max_mood]; it heads for its
## target (the baseline plus every active thought) at [member rise_per_hour] when below it and
## [member fall_per_hour] when above, both times [member volatility]. These are starting numbers,
## not tuning: a host sets its own. Per agent, the modifiers [code]mood.baseline[/code],
## [code]mood.volatility[/code], [code]mood.rise.mult[/code] and [code]mood.fall.mult[/code] adjust them.
## @experimental

## Resting mood.
@export var baseline: float = 50.0
## Mood points gained per game hour while below the target.
@export var rise_per_hour: float = 12.0
## Mood points lost per game hour while above the target.
@export var fall_per_hour: float = 8.0
## Scales both rates.
@export var volatility: float = 1.0
## The lowest mood.
@export var min_mood: float = 0.0
## The highest mood.
@export var max_mood: float = 100.0
