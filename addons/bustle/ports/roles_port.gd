# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRolesPort
extends RefCounted

## Who holds which role (a job or an office). A host extends this and overrides [method holder_of]
## and [method roles_of], and emits [signal holder_changed] when a holder changes. The standalone
## default is a static table, read from a [BustleRoleTable] if one is given, changed with
## [method set_holder]. What a role means is the host's business.
## @experimental

## [param role] passed from [param old] to [param new] (either may be empty).
signal holder_changed(role: StringName, old: StringName, new: StringName)

var _holders: Dictionary[StringName, StringName] = {}


func _init(table: BustleRoleTable = null) -> void:
	if table != null:
		for role: StringName in table.holders:
			if role != &"" and table.holders[role] != &"":
				_holders[role] = table.holders[role]


## Who holds [param role], or empty.
## @experimental
func holder_of(role: StringName) -> StringName:
	return _holders.get(role, &"")


## The roles [param id] holds, sorted. Empty for an unknown or empty id.
## @experimental
func roles_of(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		return out
	for role: StringName in _holders:
		if _holders[role] == id:
			out.append(String(role))
	out.sort()
	return out


## Gives [param role] to [param id] (empty vacates it), emitting [signal holder_changed] when that
## changes anything. Empty roles are ignored.
## @experimental
func set_holder(role: StringName, id: StringName) -> void:
	var old := holder_of(role)
	if role == &"" or old == id:
		return
	if id == &"":
		_holders.erase(role)
	else:
		_holders[role] = id
	holder_changed.emit(role, old, id)
