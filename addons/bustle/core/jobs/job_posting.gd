# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleJobPosting
extends RefCounted

## One posting on a [BustleJobBoard]: a work type someone wants done, open until an agent claims
## it, and gone once it's completed, cancelled or expired. Read it; change it only through the
## board.
## @experimental

## Its id, unique on its board.
var id: StringName = &""
## The [BustleWorkType] id.
var type: StringName = &""
## Who posted it (an agent, or a host name such as a household), or empty.
var employer: StringName = &""
## Where the work is done.
var place: StringName = &""
## The game minute it was posted.
var opened: int = 0
## The game minute it expires, or -1 for never.
var due: int = -1
## The agent holding the claim, or empty while it's open.
var claimed_by: StringName = &""
## The game minute it was claimed, or -1 while it's open.
var claimed_at: int = -1


## True while nobody holds a claim on it.
## @experimental
func is_open() -> bool:
	return claimed_by == &""


## As plain data.
## @experimental
func to_dict() -> Dictionary:
	return {"id": String(id), "type": String(type), "employer": String(employer), "place": String(place),
		"opened": opened, "due": due, "claimed_by": String(claimed_by), "claimed_at": claimed_at}
