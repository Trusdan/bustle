# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSkillSet
extends RefCounted

## Skill levels. A host or the skills module extends this. The standalone default makes everyone equally skilled.
## @experimental


## [param _id]'s level in [param _skill]. Default: 0.0.
## @experimental
func level(_id: StringName, _skill: StringName) -> float:
	return 0.0
