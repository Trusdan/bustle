# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthPort
extends RefCounted

## Health, owned by the host (damage, illness, medicine). A host or the health module extends this.
## The standalone default says everyone is healthy.
## @experimental


## True when [param _id] is hurt. Default: false.
## @experimental
func is_injured(_id: StringName) -> bool:
	return false


## True when [param _id] can't act at all. Default: false.
## @experimental
func is_incapacitated(_id: StringName) -> bool:
	return false


## True when [param _id]'s life is in danger right now (for example badly wounded). Default: false.
## @experimental
func is_life_threatened(_id: StringName) -> bool:
	return false
