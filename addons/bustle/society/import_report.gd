# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleImportReport
extends RefCounted

## What happened when a saved society was imported. When [member ok] is false nothing was changed:
## an import is all or nothing.
## @experimental

## True when the state was imported.
var ok: bool = false
## The schema version the payload claimed, or -1 when it had none.
var schema: int = -1
## Why it was refused, one line each (empty when [member ok]).
var errors: PackedStringArray = PackedStringArray()


## Adds a reason it was refused.
## @experimental
func fail(reason: String) -> void:
	errors.append(reason)
	ok = false
