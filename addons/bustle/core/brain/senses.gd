# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSenses
extends RefCounted

## What a [BustleBrain] is told on one tick: the game time, the agent's input values (already
## normalised, see [BustleInputs]) and the options it knows of. Whoever drives the brain (a host,
## or later modules) fills it in; the brain never reads the scene.
## @experimental

## The game minute of this tick.
var now_minutes: int = 0
## Input key → value.
var inputs: Dictionary[StringName, float] = {}
## The options the agent knows of.
var advertisements: Array[BustleAdvertisement] = []
