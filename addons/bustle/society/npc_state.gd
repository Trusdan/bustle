# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleNpcState
extends RefCounted

## One agent's state, independent of any scene: who it is, where it is, its brain and its modules'
## data. A body (a scene node the host makes) can be attached and freed at any time; the state
## stays in the [BustleSociety].
## @experimental

## The agent's id, unique in its society.
var id: StringName = &""
## The archetype it was made from (see [method BustleSociety.register_archetype]).
var archetype: StringName = &""
## Its group, for dispositions.
var group: StringName = &""
## The area it is in.
var area: StringName = &""
## Its last known position, when [member has_position].
var position: Vector3 = Vector3.ZERO
## True once a position is known.
var has_position: bool = false
## Modules' saved data for this agent, as plain data (numbers, strings, string names, arrays and
## dictionaries).
var data: Dictionary = {}
## Its brain.
var brain: BustleBrain

var _body: WeakRef = null


## The attached body, or null when there is none or it has been freed.
## @experimental
func body() -> Node3D:
	if _body == null:
		return null
	var node := _body.get_ref() as Node3D
	return node if node != null and is_instance_valid(node) else null


## Attaches [param node] as the body. When a position is known, the body is moved there.
## @experimental
func attach_body(node: Node3D) -> void:
	_body = weakref(node) if node != null else null
	if node != null and has_position and node.is_inside_tree():
		node.global_position = position


## Copies the body's position into the state (when it has one) and detaches it.
## @experimental
func detach_body() -> void:
	sync_from_body()
	_body = null


## Copies the attached body's position into the state. Nothing happens without a body.
## @experimental
func sync_from_body() -> void:
	var node := body()
	if node != null and node.is_inside_tree() and node.global_position.is_finite():
		position = node.global_position
		has_position = true
