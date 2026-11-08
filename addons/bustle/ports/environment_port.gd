# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleEnvironmentPort
extends RefCounted

## Rooms and surroundings. A host extends this from its own room detection. The standalone default has no rooms.
## @experimental


## The room [param _id] is in, or empty.
## @experimental
func room_of(_id: StringName) -> StringName:
	return &""
