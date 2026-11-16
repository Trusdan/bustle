# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted
## A seeded perception scenario that records everything perception decides, for
## test_perception_unchanged.gd: every state change, the rays and senses of each tick, every
## meter's saved state and per-tick flags, and the public meter calls on random inputs. Each
## block of the record is hashed; the fixture holds the hashes made by the code before the
## performance work, so the same results give the same lines.

## Ticks per hashed block.
const BLOCK := 30


## The headless world: mixed profiles (narrow cones, carried light only, deaf, blind, every
## tick), actors that aren't perceivers or stop being perceivable, a removed and an added actor,
## a profile change, broadcast sounds, two actors at the same spot and one with no facing.
static func world_lines() -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 362
	var record: Array[String] = []
	var tick := [0]
	var world := BustlePerceptionWorld.new()
	world.perception_changed.connect(func(p: StringName, t: StringName, old: int, new: int) -> void:
		record.append("changed %s %s %d %d" % [p, t, old, new]))
	world.line_of_sight = func(_from: Vector3, _to: Vector3, p: StringName, t: StringName) -> bool:
		return ("%s|%s|%d" % [p, t, tick[0] / 7]).hash() % 4 != 0
	var profiles := _profiles()
	for i in 24:
		world.add_actor(_actor(i, profiles, rng))
	world.actor(&"a07").position = world.actor(&"a08").position
	world.actor(&"a05").forward = Vector3.ZERO
	var out := PackedStringArray()
	for frame in 600:
		tick[0] = frame
		for id: StringName in world.actor_ids():
			var actor := world.actor(id)
			if actor.forward != Vector3.ZERO:
				actor.forward = actor.forward.rotated(Vector3.UP, rng.randf_range(-0.2, 0.2))
				actor.position += actor.forward.normalized() * rng.randf_range(0.0, 0.12)
				actor.position = actor.position.clamp(Vector3(-25, 0, -25), Vector3(25, 3, 25))
			actor.visibility = clampf(actor.visibility + rng.randf_range(-0.05, 0.05), 0.0, 1.3)
		match frame:
			120:
				world.actor(&"a02").perceivable = false
			260:
				world.actor(&"a02").perceivable = true
			300:
				world.remove_actor(&"a10")
			330:
				world.add_actor(_actor(24, profiles, rng))
			400:
				world.actor(&"a01").profile = profiles[2]
				world.reschedule(&"a01")
			450:
				record.append("heard %d" % world.broadcast(BustleNoiseEvent.new(Vector3(3, 0, -4), 12.0, &"a03")))
			455:
				record.append("heard %d" % world.broadcast(BustleNoiseEvent.new(Vector3(-8, 1, 6), 9.0)))
		world.tick(1.0 / 60.0)
		record.append("tick %d rays %d sensed %d" % [frame, world.rays_last_tick, world.sensed_last_tick])
		if frame % 50 == 49:
			for id: StringName in world.actor_ids():
				record.append("%s %s" % [id, _awareness_hash(world.actor(id).awareness)])
		if frame % BLOCK == BLOCK - 1:
			out.append(_block("world %d" % (frame / BLOCK), record))
	return out


## The public meter calls on random observers and targets: sight_cone(), sight_rate(),
## hearing_rate(), light_allows() and three ticks.
static func meter_lines() -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3620
	var profiles := _profiles()
	var record: Array[String] = []
	var out := PackedStringArray()
	for i in 400:
		var meter := BustleDetectionMeter.new(profiles[i % profiles.size()])
		var observer := Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 2), rng.randf_range(-20, 20))
		var forward := Vector3.ZERO if i % 37 == 0 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		var at := observer if i % 41 == 0 else Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 2), rng.randf_range(-20, 20))
		var target := BustleSenseTarget.new(at, rng.randf_range(-0.2, 1.4), rng.randf_range(0, 12), rng.randf() < 0.8, rng.randf() < 0.3)
		record.append(var_to_str([meter.sight_cone(observer, forward, at), meter.sight_rate(observer, forward, target),
			meter.hearing_rate(observer, target), meter.light_allows(target)]))
		for step in 3:
			record.append(var_to_str([meter.tick(0.25, observer, forward, target), meter.level, meter.state,
				meter.seen_now, meter.heard_now, meter.since_sensed]))
		if i % 50 == 49:
			out.append(_block("meter %d" % (i / 50), record))
	return out


## The same through a [BustlePerceptionSystem] in [param parent]'s tree: components on walking
## nodes, synced and stepped. Nothing is on the sight mask, so every ray is clear.
static func system_lines(parent: Node) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 36200
	var record: Array[String] = []
	var system := BustlePerceptionSystem.new()
	system.running = false
	parent.add_child(system)
	system.perception_changed.connect(func(p: StringName, t: StringName, old: int, new: int) -> void:
		record.append("changed %s %s %d %d" % [p, t, old, new]))
	var walkers: Array[Node3D] = []
	for i in 12:
		var walker := Node3D.new()
		walker.position = Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		walker.rotation.y = rng.randf_range(-PI, PI)
		if i % 3 != 2:
			var eyes := BustlePerceiver.new()
			eyes.actor_id = StringName("w%02d" % i)
			eyes.profile = BustlePerceptionProfile.new()
			eyes.position = Vector3(0, 1.6, 0.1)
			walker.add_child(eyes)
		if i % 4 != 3:
			var body := BustlePerceivable.new()
			body.actor_id = StringName("w%02d" % i)
			body.position = Vector3(0, 1.2, 0)
			body.noise_radius = 6.0
			walker.add_child(body)
		parent.add_child(walker)
		walkers.append(walker)
	var out := PackedStringArray()
	for frame in 240:
		for walker: Node3D in walkers:
			walker.position += -walker.global_basis.z * 0.03
			walker.rotation.y += rng.randf_range(-0.08, 0.08)
		system.step(1.0 / 60.0)
		for id: StringName in system.world.actor_ids():
			var actor := system.world.actor(id)
			record.append(var_to_str([id, actor.position, actor.forward, actor.visibility, actor.noise_radius, actor.group]))
		record.append("rays %d sensed %d" % [system.world.rays_last_tick, system.world.sensed_last_tick])
		if frame % 60 == 59:
			for id: StringName in system.world.actor_ids():
				record.append("%s %s" % [id, _awareness_hash(system.world.actor(id).awareness)])
			out.append(_block("system %d" % (frame / 60), record))
	for walker: Node3D in walkers:
		walker.free()
	system.free()
	return out


static func _profiles() -> Array[BustlePerceptionProfile]:
	var plain := BustlePerceptionProfile.new()
	var narrow := BustlePerceptionProfile.new()
	narrow.sight_range = 25.0
	narrow.sight_angle_deg = 40.0
	narrow.peripheral_angle_deg = 100.0
	narrow.perception_hz = 5.0
	var lit := BustlePerceptionProfile.new()
	lit.sight_light = BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY
	lit.perception_hz = 30.0
	var deaf := BustlePerceptionProfile.new()
	deaf.hears = false
	deaf.perception_hz = 0.0
	var blind := BustlePerceptionProfile.new()
	blind.sees = false
	blind.hearing_scale = 2.0
	var out: Array[BustlePerceptionProfile] = [plain, narrow, lit, deaf, blind]
	return out


static func _actor(i: int, profiles: Array[BustlePerceptionProfile], rng: RandomNumberGenerator) -> BustlePerceptionActor:
	var actor := BustlePerceptionActor.new(StringName("a%02d" % i), profiles[i % 6] if i % 6 < 5 else null)
	actor.position = Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 2), rng.randf_range(-20, 20))
	actor.forward = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	actor.perceivable = i % 7 != 3
	actor.visibility = 0.0 if i % 9 == 0 else rng.randf_range(0.1, 1.3)
	actor.noise_radius = rng.randf_range(0, 9)
	actor.carries_light = i % 4 == 0
	actor.group = StringName("g%d" % (i % 3))
	return actor


# Every meter's saved state and per-tick flags, in the awareness list's own order.
static func _awareness_hash(awareness: BustleAwareness) -> String:
	var flags := []
	for id: StringName in awareness.target_ids():
		var meter := awareness.meter(id)
		flags.append([id, meter.seen_now, meter.heard_now, meter.level, meter.since_sensed])
	return _sha(var_to_bytes([awareness.export_state(), flags]))


# One fixture line for the record so far, which it then clears.
static func _block(label: String, record: Array[String]) -> String:
	var line := "%s: %d lines %s" % [label, record.size(), _sha("\n".join(record).to_utf8_buffer())]
	record.clear()
	return line


static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().substr(0, 24)
