# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSimRingConfig
extends Resource

## How agents are sorted into simulation rings (see [BustleSimRings]). Every default here is a
## proposed tunable; projects set their own.
## @experimental

## Outdoors, in the player's area and within this distance of the player (metres): the FULL ring.
@export var full_radius: float = 60.0
## Outdoors, a FULL agent stays FULL until it is farther than [member full_radius] plus this
## (metres).
@export var hysteresis: float = 15.0
## After a ring change, a change by distance waits this long (real seconds).
@export var min_dwell_seconds: float = 5.0
## A LIGHT agent whose area stops being the player's or a neighbour's goes OFF_SCREEN only after
## this long (real seconds), so stepping through a door and back doesn't thrash. FULL to
## OFF_SCREEN by area applies at once.
@export var light_to_offscreen_delay_seconds: float = 10.0
## When the player is in an interior, everyone in it is FULL, wherever they stand.
@export var full_whole_interior: bool = true
## A body never appears in view within this distance of the player (metres).
@export var no_pop_in_distance: float = 20.0
## How often a FULL agent's brain thinks (real hertz).
@export var full_brain_hz: float = 2.0
## How often a LIGHT agent's brain thinks (real hertz).
@export var light_rate_hz: float = 1.0
## How often an OFF_SCREEN agent's brain thinks (game minutes).
@export var offscreen_interval_game_minutes: int = 60
## Catch-up simulates at most this many game days; anything older is summarised.
@export var catch_up_cap_game_days: int = 7
## When true, [BustleSimRings] spawns a body when an agent becomes FULL and frees it when it stops
## being FULL, through the world port.
@export var manage_bodies: bool = true
