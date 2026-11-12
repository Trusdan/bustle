# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWyrdRolesPort
extends BustleRolesPort

## The roles port, answered by Wyrd's role bindings. Installed by [method BustleWyrdBridge.install],
## so Wyrd is the one source of who holds which role.
##
## @experimental
## Changes go through Wyrd's stable [code]roles.assign[/code] and [code]roles.vacate[/code].
## [signal BustleRolesPort.holder_changed] repeats Wyrd's role signals, whoever made the change:
## stable [code]role_holder_changed[/code] (a new holder, or a successor Wyrd picked),
## [code]role_vacant[/code] (left empty or abolished) and [code]election_needed[/code], and the
## experimental [code]succession_requested[/code] (both: contested, so empty until someone is
## assigned). For [code]role_vacant[/code] the old holder is the last entry of Wyrd's experimental
## [code]roles.history[/code]. [method holder_of] and [method roles_of] read Wyrd's experimental
## [code]roles.holder[/code] and [code]roles.roles_of[/code], behind the exact release check. Calls go
## by name, so this script compiles with no Wyrd in the project.

## The reason Wyrd's role history records when this port vacates a role.
const VACATE_REASON := &"vacated"

var _wyrd: Object


## A port over [param wyrd]: Wyrd's facade, or anything with the same members.
func _init(wyrd: Object = null) -> void:
	_wyrd = wyrd
	var roles := _roles()
	if roles == null:
		return
	for relay: Array in [
		[&"role_holder_changed", _on_role_holder_changed], [&"role_vacant", _on_role_vacant],
		[&"election_needed", _on_contested], [&"succession_requested", _on_contested],
	]:
		if roles.has_signal(relay[0]):
			roles.connect(relay[0], relay[1])


## Who holds [param role] in Wyrd, or empty.
## @experimental
func holder_of(role: StringName) -> StringName:
	var roles := _roles()
	if roles == null or role == &"":
		return &""
	return StringName(roles.call(&"holder", role))


## The roles [param id] holds in Wyrd, sorted. Empty for an empty id.
## @experimental
func roles_of(id: StringName) -> PackedStringArray:
	var roles := _roles()
	if roles == null or id == &"":
		return PackedStringArray()
	return roles.call(&"roles_of", id)


## Gives [param role] to [param id] with Wyrd's [code]roles.assign[/code]. An empty [param id]
## vacates it with [code]roles.vacate[/code], which runs the role's succession, so the role may
## pass to a successor rather than stay empty. [signal BustleRolesPort.holder_changed] fires from
## Wyrd's signal, once per change.
## @experimental
func set_holder(role: StringName, id: StringName) -> void:
	var roles := _roles()
	if roles == null or role == &"":
		return
	if id != &"":
		roles.call(&"assign", role, id)
	elif holder_of(role) != &"":
		roles.call(&"vacate", role, VACATE_REASON)


func _on_role_holder_changed(role: StringName, old: StringName, new: StringName) -> void:
	holder_changed.emit(role, old, new)


func _on_role_vacant(role: StringName) -> void:
	var history: Array = _roles().call(&"history", role)
	var old := StringName((history.back() as Dictionary).get("holder", &"")) if not history.is_empty() else &""
	if old != &"":
		holder_changed.emit(role, old, &"")


func _on_contested(role: StringName, departed: StringName) -> void:
	if departed != &"":
		holder_changed.emit(role, departed, &"")


func _roles() -> Object:
	return _wyrd.get(&"roles") as Object if _wyrd != null else null
