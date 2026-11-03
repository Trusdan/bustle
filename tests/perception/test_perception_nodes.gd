# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The scene components: a system, perceivers and perceivables, with physics sight rays.

const S := BustleDetectionMeter.State

var _square: Node3D
var _system: BustlePerceptionSystem
var _profile: BustlePerceptionProfile


func before_each() -> void:
	_square = Node3D.new()
	_system = BustlePerceptionSystem.new()
	_system.running = false
	_square.add_child(_system)
	_profile = BustlePerceptionProfile.new()
	_profile.perception_hz = 0.0
	add_child_autofree(_square)


## A villager with a body (which must not block its own view), eyes and a perceivable.
func _villager(villager_name: String, at: Vector3, yaw: float = 0.0, eyes: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = villager_name
	body.position = at
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0, 1, 0)
	body.add_child(shape)
	if eyes:
		var perceiver := BustlePerceiver.new()
		perceiver.profile = _profile
		perceiver.position = Vector3(0, 1.6, -0.35)
		body.add_child(perceiver)
	var perceivable := BustlePerceivable.new()
	perceivable.position = Vector3(0, 1.2, 0)
	body.add_child(perceivable)
	_square.add_child(body)
	return body


func _wall(at: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.4)
	shape.shape = box
	wall.add_child(shape)
	_square.add_child(wall)


func _run(seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in frames:
		_system.step(1.0 / 60.0)


func test_villagers_see_each_other_through_the_components() -> void:
	_villager("baker", Vector3.ZERO)
	_villager("smith", Vector3(0, 0, -6), PI)
	await wait_physics_frames(2)
	_run(2.0)
	var world := _system.world
	assert_eq(world.actor_ids(), [&"baker", &"smith"] as Array[StringName], "ids default to the parent's name")
	assert_true(world.perceives(&"baker", &"smith"), "its own body doesn't block its view")
	assert_eq(world.actor(&"baker").awareness.entry(&"smith").state, S.ALERT)
	assert_true(world.perceives(&"smith", &"baker"))
	assert_eq((_square.get_node("baker").get_child(1) as BustlePerceiver).awareness().size(), 1)


func test_a_wall_blocks_the_ray() -> void:
	_villager("baker", Vector3.ZERO)
	_villager("smith", Vector3(0, 0, -6), 0.0, false)
	_wall(Vector3(0, 1.5, -3))
	await wait_physics_frames(2)
	_run(1.0)
	assert_false(_system.world.perceives(&"baker", &"smith"))


func test_state_changes_are_passed_on_and_components_unregister() -> void:
	var changes := []
	_system.perception_changed.connect(func(p: StringName, t: StringName, _old: S, new: S) -> void: changes.append([p, t, new]))
	_villager("baker", Vector3.ZERO)
	var smith := _villager("smith", Vector3(0, 0, -6), 0.0, false)
	await wait_physics_frames(2)
	_run(2.0)
	assert_has(changes, [&"baker", &"smith", S.ALERT])
	smith.free()
	assert_null(_system.world.actor(&"smith"), "gone with its components")
	assert_false(_system.world.actor(&"baker").awareness.has(&"smith"))


func test_the_perceivable_state_reaches_the_world() -> void:
	var baker := _villager("baker", Vector3.ZERO)
	var target := baker.get_child(2) as BustlePerceivable
	target.visibility = 0.3
	target.noise_radius = 5.0
	target.carries_light = true
	target.group = &"village"
	await wait_physics_frames(1)
	_system.step(1.0 / 60.0)
	var actor := _system.world.actor(&"baker")
	assert_eq(actor.visibility, 0.3)
	assert_eq(actor.noise_radius, 5.0)
	assert_true(actor.carries_light)
	assert_eq(actor.group, &"village")
	assert_almost_eq(actor.position, baker.get_child(1).global_position, Vector3.ONE * 0.001, "the eyes win")
