# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCareerRank
extends Resource

## One rank of a career track, as data: its id, the wage a career block earns at it, the skill
## level an agent needs to hold it, and how it is reviewed. [BustleCareerDef] lists them lowest
## first. The review numbers are experimental defaults.
## @experimental

## Its id, unique in its track.
@export var id: StringName = &""
## What attending one career block earns at this rank, in the trade port's unit, paid at the
## block's end like any schedule wage. It replaces the block's own wage.
@export var wage: int = 0
## The least level in the track's skill (read through the skill port) an agent needs to hold it.
## 0: none.
@export var min_skill: float = 0.0
## Working days (days with a career block) at this rank in each review window (see
## [method BustleCareers.update]). Days off don't count.
@export var review_days: int = 7
## A window's performance (0 to 1) at or above this makes a promotion due.
@export var promote_if: float = 0.75
## A window's performance at or below this makes a demotion due.
@export var demote_if: float = 0.35


## True when it can be used: an id, a wage of at least 0, a finite, non-negative skill minimum, a
## review window of at least one day, and finite thresholds with [member demote_if] below
## [member promote_if].
## @experimental
func is_valid() -> bool:
	return id != &"" and wage >= 0 and is_finite(min_skill) and min_skill >= 0.0 and review_days >= 1 \
			and is_finite(promote_if) and is_finite(demote_if) and demote_if < promote_if
