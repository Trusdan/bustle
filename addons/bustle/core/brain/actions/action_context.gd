# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleActionContext
extends RefCounted

## What a [BustleActionHandler] works with for one step: who, the step's parameters, the game time,
## and two dictionaries it owns.
## @experimental

## The agent.
var agent_id: StringName = &""
## The step's parameters.
var params: Dictionary = {}
## The game minute of this tick.
var now_minutes: int = 0
## The handler's state for this step. Keep **all** of it here, as plain data (numbers, strings,
## string names, arrays, dictionaries), so the runner can save and restore a step mid-way.
var data: Dictionary = {}
## What the handler asks the agent's body to do this tick (for example a move target or an
## animation), read by the brain.
var output: Dictionary = {}
## Why the step failed, set by the handler when it returns FAILED.
var failure: StringName = &""
