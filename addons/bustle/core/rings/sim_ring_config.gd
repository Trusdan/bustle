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
## An agent whose area stops being the player's or a neighbour's goes OFF_SCREEN only after this
## long (real seconds), so stepping through a door and back doesn't thrash.
@export var light_to_offscreen_delay_seconds: float = 10.0
## When the player is in an interior, everyone in it is FULL, wherever they stand.
@export var full_whole_interior: bool = true
