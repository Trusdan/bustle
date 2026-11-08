# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleGoalDef
extends Resource

## A goal an agent can choose: its band, base weight, preconditions and considerations. Its score is
## [code]base_weight × Π consideration[/code]. A goal that uses advertisements makes one candidate
## per known option, scored as its own score × the option's advertisement score.
## @experimental

## Its id, unique in a library.
@export var id: StringName = &""
## Its band (see [BustleBands]).
@export var band: int = BustleBands.IDLE
## Its base weight.
@export var base_weight: float = 1.0
## It is eligible only when its score is at least this (and above zero). Data, per goal.
@export var min_score: float = 0.0
## Game minutes it is kept before a candidate in the same or a lower band may replace it.
@export var min_commit_minutes: int = 0
## Game minutes after it fails before it can be chosen again (see [BustleChoiceKeeper]). Even at
## zero it can't be chosen again in the same game minute it failed.
@export var fail_cooldown_minutes: int = 0
## Hard preconditions. Each is a dictionary with a [code]kind[/code]: [code]input[/code] (with an
## [code]input[/code] key) passes when that input is present, finite and above zero; any other kind is asked
## of the context's precondition check.
@export var preconditions: Array[Dictionary] = []
## The factors of its score.
@export var considerations: Array[BustleConsideration] = []
## The plan it runs once chosen. Without one, the agent just holds the goal.
@export var sequence: BustleActionSequence
## When true it makes one candidate per advertisement in the context, instead of one candidate.
@export var uses_advertisements: bool = false
