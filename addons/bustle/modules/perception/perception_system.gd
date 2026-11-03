# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceptionSystem
extends Node

## Runs a [BustlePerceptionWorld] for a scene: [BustlePerceiver] and [BustlePerceivable] nodes
## register with it, it copies their state into the world each physics frame, ticks the world and
## casts the sight rays with physics.
##
## Put one in a scene (or as an autoload). Components find it through the group [constant GROUP]
## unless their [code]system_path[/code] points at one. A ray is blocked by any body on
## [member sight_mask] except the perceiver's and the target's own bodies.
## @experimental

## A perceiver's awareness of a target changed state (the world's signal, passed on).
signal perception_changed(perceiver_id: StringName, target_id: StringName, old_state: BustleDetectionMeter.State, new_state: BustleDetectionMeter.State)

## The group the system joins.
const GROUP := &"bustle_perception_system"

## Physics layers that block sight.
@export_flags_3d_physics var sight_mask: int = 1
## False: the world isn't ticked (the components still register).
@export var running := true

## The world.
var world := BustlePerceptionWorld.new()
## Microseconds the last physics frame spent in perception (sync, senses and rays), for benches.
var last_tick_usec: int = 0

var _perceivers: Dictionary = {}
var _perceivables: Dictionary = {}
var _space: PhysicsDirectSpaceState3D


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	world.line_of_sight = _ray
	world.perception_changed.connect(func(p: StringName, t: StringName, old: BustleDetectionMeter.State, new: BustleDetectionMeter.State) -> void: perception_changed.emit(p, t, old, new))


func _physics_process(delta: float) -> void:
	if running:
		step(delta)


## Copies the components' state into the world and ticks it by [param delta]. The physics frame
## calls it; tests can too.
## @experimental
func step(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_sync()
	world.tick(delta)
	last_tick_usec = Time.get_ticks_usec() - start


## Registers a perceiver component.
## @experimental
func add_perceiver(node: BustlePerceiver) -> void:
	_perceivers[node.actor_id] = node
	_actor_for(node.actor_id).profile = node.profile
	world.reschedule(node.actor_id)


## Registers a perceivable component.
## @experimental
func add_perceivable(node: BustlePerceivable) -> void:
	_perceivables[node.actor_id] = node
	_actor_for(node.actor_id).perceivable = true


## Unregisters a component. The actor leaves the world once neither of its components is left.
## @experimental
func remove_component(node: Node, actor_id: StringName) -> void:
	if _perceivers.get(actor_id) == node:
		_perceivers.erase(actor_id)
		var actor := world.actor(actor_id)
		if actor != null:
			actor.profile = null
	if _perceivables.get(actor_id) == node:
		_perceivables.erase(actor_id)
		var actor := world.actor(actor_id)
		if actor != null:
			actor.perceivable = false
	if not _perceivers.has(actor_id) and not _perceivables.has(actor_id):
		world.remove_actor(actor_id)


## The first system in [param tree], or null.
## @experimental
static func find(tree: SceneTree) -> BustlePerceptionSystem:
	return tree.get_first_node_in_group(GROUP) as BustlePerceptionSystem


func _actor_for(id: StringName) -> BustlePerceptionActor:
	var actor := world.actor(id)
	if actor == null:
		actor = world.add_actor(BustlePerceptionActor.new(id))
		actor.perceivable = false
	return actor


func _sync() -> void:
	var world_3d := get_viewport().world_3d if is_inside_tree() and get_viewport() != null else null
	_space = world_3d.direct_space_state if world_3d != null else null
	for id: StringName in _perceivables:
		var node: BustlePerceivable = _perceivables[id]
		var actor := world.actor(id)
		actor.position = node.global_position
		actor.visibility = node.visibility
		actor.noise_radius = node.noise_radius
		actor.carries_light = node.carries_light
		actor.group = node.group
	for id: StringName in _perceivers:
		var node: BustlePerceiver = _perceivers[id]
		var actor := world.actor(id)
		actor.position = node.global_position
		actor.forward = -node.global_basis.z
		actor.profile = node.profile
		if not _perceivables.has(id):
			actor.group = node.group


func _ray(from: Vector3, to: Vector3, perceiver_id: StringName, target_id: StringName) -> bool:
	if _space == null:
		return true
	var exclude: Array[RID] = []
	for node: Variant in [_perceivers.get(perceiver_id), _perceivables.get(perceiver_id), _perceivers.get(target_id), _perceivables.get(target_id)]:
		var body := (node as Node).get_parent() as CollisionObject3D if node != null else null
		if body != null:
			exclude.append(body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, sight_mask, exclude)
	return _space.intersect_ray(query).is_empty()
