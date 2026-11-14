# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStageDef
extends Resource

## One life stage, as data: where it starts (an age in game days) and what it rules out. An agent is
## in the last stage whose [member min_days] its age has reached (see [BustleLifeStageRules]).
## @experimental

## Its id, unique in one set of rules.
@export var id: StringName = &""
## The age, in game days, at which it starts. Not negative, and above the stage before it.
@export var min_days: float = 0.0
## Goals it rules out: a goal is blocked when its id or any of its [member BustleGoalDef.tags] is
## listed here.
@export var blocked_goal_tags: Array[StringName] = []
## Options it rules out: an option is blocked when any of its advertisement's tags is listed here.
@export var blocked_affordance_tags: Array[StringName] = []
