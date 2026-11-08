# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWorkPort
extends RefCounted

## Jobs. A host extends this to give agents its jobs. The standalone default has none beyond schedule blocks.
## @experimental


## The job [param _id] has, or empty.
## @experimental
func job_of(_id: StringName) -> StringName:
	return &""
