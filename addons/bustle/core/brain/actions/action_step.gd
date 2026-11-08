# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleActionStep
extends Resource

## One step of a [BustleActionSequence]: an action id, its parameters, and what to do when it fails.
## @experimental

## What to do when the step fails.
enum OnFail {
	## Try the step again, up to [member max_retries] more times, then abort.
	RETRY,
	## Go on to the next step.
	SKIP,
	## End the sequence as failed.
	ABORT,
}

## The action id, as registered with [method BustleSequenceRunner.register].
@export var action: StringName = &""
## The action's parameters.
@export var params: Dictionary = {}
## What to do when it fails.
@export var on_fail: OnFail = OnFail.ABORT
## With [constant OnFail.RETRY]: how many more attempts after the first.
@export var max_retries: int = 1
