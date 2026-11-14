# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStagePort
extends RefCounted

## Life stages (child, adult and so on, as the host defines them). A host or the life-stages module extends this. The standalone default is ageless.
## @experimental


## The stage [param _id] is in, or empty.
## @experimental
func stage_of(_id: StringName) -> StringName:
	return &""


## Whether [param _id]'s stage lets it choose a goal with any of [param _tags] (the goal's id and
## tags). The default: always.
## @experimental
func allows_goal(_id: StringName, _tags: Array[StringName]) -> bool:
	return true


## Whether [param _id]'s stage lets it use an option with any of [param _tags] (its advertisement's
## tags). The default: always.
## @experimental
func allows_affordance(_id: StringName, _tags: Array[StringName]) -> bool:
	return true
