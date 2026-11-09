# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConflictConfig
extends Resource

## The numbers behind [BustleConflict]: who fights, how far help is looked for, how rarely a fight
## turns lethal, and how quarrels turn into scuffles.
## @experimental

## The average of an agent's boldness and temper (0 to 100) at or above which it fights a threat.
## Below it, it fetches help when an ally is near, and flees otherwise.
@export var fight_threshold: float = 60.0
## How far away, in metres, an ally can be and still be fetched.
@export var help_radius: float = 15.0
## How far, in metres, a fleeing agent runs before it feels safe.
@export var flee_distance: float = 10.0
## The chance (0 to 1) that a fight is lethal rather than a scuffle. Rare by default.
@export_range(0.0, 1.0) var lethal_chance: float = 0.02
## The health a scuffle always leaves its victim (see [method BustleConflict.filter_damage]).
@export var scuffle_floor: float = 1.0
## The chance (0 to 1) that a quarrel becomes a scuffle, at temper 100; it scales with temper.
@export_range(0.0, 1.0) var quarrel_chance: float = 0.3
