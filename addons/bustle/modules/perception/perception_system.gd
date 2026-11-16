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
var _query := PhysicsRayQueryParameters3D.new()


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
func step(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_sync()
	world.tick(delta)
	last_tick_usec = Time.get_ticks_usec() - start


## Registers a perceiver component.
func add_perceiver(node: BustlePerceiver) -> void:
	_perceivers[node.actor_id] = node
	_actor_for(node.actor_id).profile = node.profile
	world.reschedule(node.actor_id)


## Registers a perceivable component.
func add_perceivable(node: BustlePerceivable) -> void:
	_perceivables[node.actor_id] = node
	_actor_for(node.actor_id).perceivable = true


## Unregisters a component. The actor leaves the world once neither of its components is left.
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
	var actors := world._actors
	for id: StringName in _perceivables:
		var node: BustlePerceivable = _perceivables[id]
		var actor: BustlePerceptionActor = actors.get(id)
		actor.position = node.global_position
		actor.visibility = node.visibility
		actor.noise_radius = node.noise_radius
		actor.carries_light = node.carries_light
		actor.group = node.group
	for id: StringName in _perceivers:
		var node: BustlePerceiver = _perceivers[id]
		var actor: BustlePerceptionActor = actors.get(id)
		# One global transform for both: global_position and global_basis each work it out.
		var xform := node.global_transform
		actor.position = xform.origin
		actor.forward = -xform.basis.z
		actor.profile = node.profile
		if not _perceivables.has(id):
			actor.group = node.group


func _ray(from: Vector3, to: Vector3, perceiver_id: StringName, target_id: StringName) -> bool:
	if _space == null:
		return true
	var exclude: Array[RID] = []
	_exclude(exclude, _perceivers.get(perceiver_id))
	_exclude(exclude, _perceivables.get(perceiver_id))
	_exclude(exclude, _perceivers.get(target_id))
	_exclude(exclude, _perceivables.get(target_id))
	# One query, reused: every field is set for each ray, as create() would.
	_query.from = from
	_query.to = to
	_query.collision_mask = sight_mask
	_query.exclude = exclude
	return _space.intersect_ray(_query).is_empty()


# Adds the body [param node] sits on (its parent, if a physics body) to [param exclude].
static func _exclude(exclude: Array[RID], node: Node) -> void:
	if node == null:
		return
	var body := node.get_parent() as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
