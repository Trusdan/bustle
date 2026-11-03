# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceiver
extends Node3D

## Gives its actor senses. Place it at the actor's eyes, facing the way it looks (its -Z). It
## registers with the [BustlePerceptionSystem] under [member actor_id]; pair it with a
## [BustlePerceivable] with the same id if the actor can also be sensed. Differences between
## actors come from the [member profile] data, never from code.
## @experimental

## The actor's stable id. Empty: the parent's name.
@export var actor_id: StringName = &""
## How it senses.
@export var profile: BustlePerceptionProfile
## Its group, for dispositions (a paired [BustlePerceivable]'s group wins).
@export var group: StringName = &""
## Optional: the system to use. Empty: the first in the group.
@export var system_path: NodePath

var _system: BustlePerceptionSystem


func _ready() -> void:
	if actor_id == &"":
		actor_id = StringName(get_parent().name if get_parent() != null else name)
	if profile == null:
		profile = BustlePerceptionProfile.new()
	_system = get_node_or_null(system_path) as BustlePerceptionSystem if not system_path.is_empty() else BustlePerceptionSystem.find(get_tree())
	if _system != null:
		_system.add_perceiver(self)


func _exit_tree() -> void:
	if _system != null and is_instance_valid(_system):
		_system.remove_component(self, actor_id)


## The system it registered with, or null.
## @experimental
func system() -> BustlePerceptionSystem:
	return _system


## Its awareness list (see [method BustlePerceptionWorld.awareness]).
## @experimental
func awareness() -> Array[BustleAwarenessEntry]:
	if _system == null:
		var empty: Array[BustleAwarenessEntry] = []
		return empty
	return _system.world.awareness(actor_id)
