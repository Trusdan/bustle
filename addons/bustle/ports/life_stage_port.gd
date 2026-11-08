# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStagePort
extends RefCounted

## Life stages (child, adult and so on, as the host defines them). A host or the life-stages module extends this. The standalone default is ageless.
## @experimental


## The stage [param _id] is in, or empty.
## @experimental
func stage_of(_id: StringName) -> StringName:
	return &""
