# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCareerRank
extends Resource

## One rank of a career track, as data: its id, the wage a career block earns at it, and the skill
## level an agent needs to hold it. [BustleCareerDef] lists them lowest first.
## @experimental

## Its id, unique in its track.
@export var id: StringName = &""
## What attending one career block earns at this rank, in the trade port's unit, paid at the
## block's end like any schedule wage. It replaces the block's own wage.
@export var wage: int = 0
## The least level in the track's skill (read through the skill port) an agent needs to hold it.
## 0: none.
@export var min_skill: float = 0.0


## True when it can be used: an id, a wage of at least 0 and a finite, non-negative skill minimum.
## @experimental
func is_valid() -> bool:
	return id != &"" and wage >= 0 and is_finite(min_skill) and min_skill >= 0.0
