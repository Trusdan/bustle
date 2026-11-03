# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The perception bench: a neutral village square with 40 villagers, each both a perceiver and a
## perceivable, walking about among walls, at 60 physics frames a second with real sight rays.
## It reports the perception time per physics frame (average and 99th percentile) against the
## budget, and exits 1 when over it.
##   godot --headless --path . -s res://bench/perception_bench.gd [-- --frames=600 --actors=40]

const BUDGET_AVG_MS := 1.0
const BUDGET_P99_MS := 2.0

var _frames := 600
var _actors := 40
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--actors="):
			_actors = arg.get_slice("=", 1).to_int()
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 7
	var square := Node3D.new()
	root.add_child(square)
	_box(square, Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	for i in 12:
		_box(square, Vector3(6, 3, 0.5), Vector3(_rng.randf_range(-30, 30), 1.5, _rng.randf_range(-30, 30)))
	var system := BustlePerceptionSystem.new()
	system.running = false
	square.add_child(system)
	var profile := BustlePerceptionProfile.new()
	var walkers: Array[Node3D] = []
	for i in _actors:
		var villager := Node3D.new()
		villager.name = "villager_%d" % i
		villager.position = Vector3(_rng.randf_range(-35, 35), 0, _rng.randf_range(-35, 35))
		villager.rotation.y = _rng.randf_range(-PI, PI)
		var eyes := BustlePerceiver.new()
		eyes.profile = profile
		eyes.position = Vector3(0, 1.6, 0)
		villager.add_child(eyes)
		var body := BustlePerceivable.new()
		body.position = Vector3(0, 1.2, 0)
		body.noise_radius = 7.0
		villager.add_child(body)
		square.add_child(villager)
		walkers.append(villager)
	await physics_frame
	await physics_frame
	var samples: Array[float] = []
	var step := 1.0 / 60.0
	for frame in _frames:
		for villager: Node3D in walkers:
			villager.position += -villager.global_basis.z * 1.4 * step
			villager.rotation.y += _rng.randf_range(-0.05, 0.05)
			if absf(villager.position.x) > 38.0 or absf(villager.position.z) > 38.0:
				villager.rotation.y += PI
		system.step(step)
		samples.append(system.last_tick_usec / 1000.0)
		await physics_frame
	samples.sort()
	var total := 0.0
	for value: float in samples:
		total += value
	var average := total / samples.size()
	var p99 := samples[mini(samples.size() - 1, int(ceil(samples.size() * 0.99)) - 1)]
	var ok := average <= BUDGET_AVG_MS and p99 <= BUDGET_P99_MS
	print("perception bench: max %.3f ms, p95 %.3f ms" % [samples[-1], samples[int(samples.size() * 0.95)]])
	print("perception bench: %d actors, %d frames: average %.3f ms, p99 %.3f ms (budget %.1f / %.1f ms): %s" % [
		_actors, _frames, average, p99, BUDGET_AVG_MS, BUDGET_P99_MS, "OK" if ok else "OVER BUDGET"])
	quit(0 if ok else 1)


func _box(parent: Node, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
