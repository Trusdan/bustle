# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConflictConfig
extends Resource

## The numbers behind [BustleConflict]: who fights, how far help is looked for, how far agents
## flee, and how much it takes for a quarrel to come to blows. Nothing here is a chance: every
## fight and every intent to kill has a reason.
## @experimental

## The average of an agent's boldness and temper (0 to 100) at or above which it fights a threat.
## Below it, it fetches help when an ally is near, and flees otherwise.
@export var fight_threshold: float = 60.0
## How far away, in metres, an ally can be and still be fetched.
@export var help_radius: float = 15.0
## How far, in metres, a fleeing agent runs before it feels safe.
@export var flee_distance: float = 10.0
## How far past [member flee_distance] a fleeing agent aims, in metres, so a body that stops a
## little short of its target still gets far enough.
@export var flee_margin: float = 2.0
## The health a subdue fight's immediate damage always leaves its victim (see
## [method BustleConflict.filter_damage]). A stopgap until a host's health system takes over.
@export var scuffle_floor: float = 1.0
## What a quarrel's provocation and grudge must reach to come to blows at temper 0. Between temper
## 0, 50 and 100 the threshold runs in straight lines.
@export var quarrel_threshold_calm: float = 1.4
## The quarrel threshold at temper 50.
@export var quarrel_threshold: float = 1.0
## The quarrel threshold at temper 100.
@export var quarrel_threshold_hot: float = 0.6
## How much a low mood lowers the quarrel threshold: at mood 0 it is multiplied by
## [code]1 − quarrel_mood_scale[/code]. No effect at mood 50 or above.
@export var quarrel_mood_scale: float = 0.25
## The sum of an agent's negative opinion entries about another (in opinion points) that counts
## as a full grudge (1).
@export var grudge_scale: float = 50.0
