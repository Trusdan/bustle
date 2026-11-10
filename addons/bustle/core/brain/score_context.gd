# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScoreContext
extends RefCounted

## What the scorer knows about one agent at one moment: its input values, the options it knows of,
## its need weights and tag multipliers, and how to check preconditions it doesn't know itself.
## @experimental

## Input key → its normalised value (see [BustleInputs]).
var inputs: Dictionary[StringName, float] = {}
## The options the agent knows of.
var advertisements: Array[BustleAdvertisement] = []
## Need name → how much it counts. A need not listed counts 1.0.
var need_weights: Dictionary[StringName, float] = {}
## Tag → its multiplier. A tag not listed is 1.0.
var tag_mults: Dictionary[StringName, float] = {}
## [code]func(goal_id: StringName, option_id: StringName) -> float[/code]: a multiplier on that
## candidate's score (for example a long-term aim favouring some goals). It never changes a band.
## Unset: 1.
var score_boost: Callable = Callable()
## [code]func(goal_id: StringName, precondition: Dictionary) -> bool[/code] for precondition kinds
## other than [code]input[/code]. Unset: such preconditions fail.
var precondition_check: Callable = Callable()
