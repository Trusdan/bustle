# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSimRingConfig
extends Resource

## How agents are sorted into simulation rings (see [BustleSimRings]). Every default here is a
## proposed starting point; projects set their own.
## @experimental

## In the player's area and within this distance of the player (metres): the FULL ring.
@export var full_radius: float = 40.0
## A FULL agent stays FULL until it is farther than [member full_radius] plus this (metres).
@export var hysteresis: float = 8.0
## After a ring change, no further change for this long (real seconds).
@export var min_dwell_seconds: float = 5.0
