# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleActionHandler
extends RefCounted

## The code behind one action id. Subclasses override all three methods. A handler keeps no state
## of its own: everything about a step lives in [member BustleActionContext.data].
##
## The runner calls [method start] once per attempt, then [method tick] each tick until it returns
## DONE or FAILED. It calls [method cancel] exactly once for an attempt that started and didn't
## finish DONE (it failed, or was interrupted or cancelled), to release what the attempt held.
## @experimental

## What [method tick] returns.
enum Status { RUNNING, DONE, FAILED }


## Begins an attempt.
## @experimental
func start(_context: BustleActionContext) -> void:
	pass


## Works on the attempt for [param _delta] seconds.
## @experimental
func tick(_context: BustleActionContext, _delta: float) -> Status:
	return Status.DONE


## Releases what the attempt held.
## @experimental
func cancel(_context: BustleActionContext) -> void:
	pass
