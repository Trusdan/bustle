# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthPort
extends RefCounted

## Health, owned by the host (damage, illness, medicine). A host or the health module extends this.
## The standalone default says everyone is healthy.


## True when [param _id] is hurt. Default: false.
func is_injured(_id: StringName) -> bool:
	return false


## True when [param _id] can't act at all. Default: false.
func is_incapacitated(_id: StringName) -> bool:
	return false


## True when [param _id]'s life is in danger right now (for example badly wounded). Default: false.
func is_life_threatened(_id: StringName) -> bool:
	return false


## How much of capacity [param _name] [param _id] has, 1 being full and 0 none (for example
## [code]moving[/code], [code]manipulation[/code] or [code]consciousness[/code]; names are the
## host's). Default: 1.
func capacity(_id: StringName, _name: StringName) -> float:
	return 1.0


## How much pain [param _id] is in, 0 (none) to 1. Default: 0.
func pain(_id: StringName) -> float:
	return 0.0


## How urgently [param _id] needs care, 0 (not at all) to 1. Default: 0.
func needs_care(_id: StringName) -> float:
	return 0.0


## True when [param _id] can pass an illness on. Default: false.
func is_contagious(_id: StringName) -> bool:
	return false


## What others can see of [param _id]'s health, as tags (for example [code]sick[/code]). Default:
## none.
func visible_tags(_id: StringName) -> Array[StringName]:
	return []


## Asks the host to have [param _healer] care for [param _patient]. The host decides and does the
## treatment; Bustle only asks. True when it was done. Default: false.
func care(_healer: StringName, _patient: StringName) -> bool:
	return false
