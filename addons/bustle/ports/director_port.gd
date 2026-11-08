# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDirectorPort
extends RefCounted

## A storyteller that paces events. A host or the director module extends this. The standalone
## default allows every event (any limit on drama is left to the core's own budget).
## @experimental


## True when an event of [param _event_kind] may happen now. Default: true.
## @experimental
func allows(_event_kind: StringName) -> bool:
	return true
