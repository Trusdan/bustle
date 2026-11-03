# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceivable
extends Node3D

## Lets its actor be sensed. Place it where others look and listen (about chest height). Its
## owner keeps [member visibility], [member noise_radius] and [member carries_light] current
## (for example from [BustleVisibilityModel] and [BustleNoiseModel]); the defaults are a visible,
## silent actor with no light.
## @experimental

## The actor's stable id. Empty: the parent's name.
@export var actor_id: StringName = &""
## How visible it is (1.0: standing and walking in full light).
@export var visibility: float = 1.0
## How far its noise carries, in metres.
@export var noise_radius: float = 0.0
## True while it carries a lit light of its own.
@export var carries_light := false
## Its group, for dispositions.
@export var group: StringName = &""
## Optional: the system to use. Empty: the first in the group.
@export var system_path: NodePath

var _system: BustlePerceptionSystem


func _ready() -> void:
	if actor_id == &"":
		actor_id = StringName(get_parent().name if get_parent() != null else name)
	_system = get_node_or_null(system_path) as BustlePerceptionSystem if not system_path.is_empty() else BustlePerceptionSystem.find(get_tree())
	if _system != null:
		_system.add_perceivable(self)


func _exit_tree() -> void:
	if _system != null and is_instance_valid(_system):
		_system.remove_component(self, actor_id)
