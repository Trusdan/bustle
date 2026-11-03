# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Any actor perceives any actor: per-pair meters, the awareness list, the queries,
## perception_changed, broadcasts and throttling.

const S := BustleDetectionMeter.State
const STEP := 1.0 / 60.0

var _world: BustlePerceptionWorld
var _profile: BustlePerceptionProfile
var _blocked: Dictionary


func before_each() -> void:
	_world = BustlePerceptionWorld.new()
	_profile = BustlePerceptionProfile.new()
	_profile.perception_hz = 0.0
	_blocked = {}
	_world.line_of_sight = func(_from: Vector3, _to: Vector3, perceiver_id: StringName, target_id: StringName) -> bool:
		return not _blocked.has("%s>%s" % [perceiver_id, target_id])


## An actor at [param at] facing [param facing]; a perceiver unless [param watcher] is false.
func _actor(id: StringName, at: Vector3, facing: Vector3 = Vector3.FORWARD, watcher: bool = true) -> BustlePerceptionActor:
	var actor := BustlePerceptionActor.new(id, _profile if watcher else null)
	actor.position = at
	actor.forward = facing
	return _world.add_actor(actor)


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_world.tick(STEP)
		t += STEP


func _state(perceiver: StringName, target: StringName) -> S:
	var entry := _world.actor(perceiver).awareness.entry(target)
	return entry.state if entry != null else S.UNAWARE


func test_any_actor_perceives_any_actor_by_sight() -> void:
	_actor(&"baker", Vector3.ZERO, Vector3.FORWARD)
	_actor(&"smith", Vector3(0, 0, -5), Vector3.BACK)
	_actor(&"well", Vector3(1, 0, -4), Vector3.FORWARD, false)
	_run(2.0)
	assert_eq(_state(&"baker", &"smith"), S.ALERT, "a perceiver sees another perceiver")
	assert_eq(_state(&"smith", &"baker"), S.ALERT, "and is seen back")
	assert_eq(_state(&"baker", &"well"), S.ALERT, "a plain perceivable is seen too")
	assert_false(_world.actor(&"well").awareness.has(&"baker"), "an actor without a profile perceives nothing")


func test_heard_occluded_out_of_cone_and_dark_cases() -> void:
	_actor(&"baker", Vector3.ZERO, Vector3.FORWARD)
	var behind := _actor(&"behind", Vector3(0, 0, 5), Vector3.FORWARD, false)
	var walled := _actor(&"walled", Vector3(2, 0, -5), Vector3.FORWARD, false)
	var dark := _actor(&"dark", Vector3(-2, 0, -5), Vector3.FORWARD, false)
	var lit := _actor(&"lit", Vector3(-1, 0, -5), Vector3.FORWARD, false)
	_blocked["baker>walled"] = true
	dark.visibility = 0.1
	_world.sense(_world.actor(&"baker"), 0.5)
	assert_false(_world.perceives(&"baker", &"behind"), "out of the cone and silent")
	assert_false(_world.perceives(&"baker", &"walled"), "occluded")
	assert_true(_world.perceives(&"baker", &"lit"))
	assert_true(_world.perceives(&"baker", &"dark"), "dark is seen, but slowly")
	assert_lt(_world.actor(&"baker").awareness.meter(&"dark").level, _world.actor(&"baker").awareness.meter(&"lit").level * 0.2)
	behind.noise_radius = 8.0
	walled.noise_radius = 8.0
	_world.sense(_world.actor(&"baker"), 0.1)
	var heard := _world.actor(&"baker").awareness.entry(&"behind")
	assert_true(heard.heard_now and not heard.seen_now, "heard behind its back")
	assert_true(_world.actor(&"baker").awareness.entry(&"walled").heard_now, "heard through the occlusion")
	assert_eq(lit.noise_radius, 0.0)


func test_a_carried_light_profile_sees_only_lit_targets() -> void:
	_profile.sight_light = BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY
	_actor(&"baker", Vector3.ZERO)
	var torch := _actor(&"torch", Vector3(0, 0, -5), Vector3.FORWARD, false)
	_actor(&"unlit", Vector3(1, 0, -5), Vector3.FORWARD, false)
	torch.carries_light = true
	_world.sense(_world.actor(&"baker"), 0.5)
	assert_true(_world.perceives(&"baker", &"torch"))
	assert_false(_world.perceives(&"baker", &"unlit"))
	assert_eq(_world.rays_last_tick, 1, "no ray for a target it can't see anyway")


func test_two_targets_are_tracked_independently() -> void:
	_profile.lose_track_time = 1.0
	_actor(&"baker", Vector3.ZERO)
	_actor(&"smith", Vector3(0, 0, -4), Vector3.FORWARD, false)
	_actor(&"miller", Vector3(1, 0, -4), Vector3.FORWARD, false)
	_run(2.0)
	assert_eq(_state(&"baker", &"smith"), S.ALERT)
	assert_eq(_state(&"baker", &"miller"), S.ALERT)
	_blocked["baker>miller"] = true
	_run(2.0)
	assert_eq(_state(&"baker", &"miller"), S.SEARCHING, "lost one")
	assert_eq(_state(&"baker", &"smith"), S.ALERT, "still has the other")


func test_awareness_entries_and_queries() -> void:
	_actor(&"baker", Vector3.ZERO)
	_actor(&"smith", Vector3(0, 0, -3), Vector3.FORWARD, false)
	_actor(&"miller", Vector3(0, 0, -12), Vector3.FORWARD, false)
	_actor(&"weaver", Vector3(3, 0, 3), Vector3.FORWARD, false)
	_run(2.0)
	var ids: Array[StringName] = []
	for e: BustleAwarenessEntry in _world.awareness(&"baker"):
		ids.append(e.target_id)
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "sorted by id")
	assert_has(ids, &"smith")
	var entry := _world.actor(&"baker").awareness.entry(&"smith")
	assert_eq(entry.target_id, &"smith")
	assert_eq(entry.state, S.ALERT)
	assert_almost_eq(entry.confidence, 1.0, 0.001)
	assert_eq(entry.last_known_position, Vector3(0, 0, -3))
	assert_true(entry.seen_now and not entry.heard_now)
	assert_eq(entry.freshness, 0.0)
	assert_eq(_world.known_nearby(&"baker", 5.0), [&"smith"] as Array[StringName], "within 5 m")
	assert_eq(_world.known_nearby(&"baker", 20.0), [&"miller", &"smith"] as Array[StringName])
	assert_eq(_world.last_known(&"baker", &"miller"), Vector3(0, 0, -12))
	assert_null(_world.last_known(&"baker", &"weaver"), "behind it, never sensed")
	assert_true(_world.perceives(&"baker", &"smith"))
	assert_false(_world.perceives(&"baker", &"weaver"))
	assert_eq(_world.perceivers_of(&"smith"), [&"baker"] as Array[StringName])
	assert_eq(_world.perceivers_of(&"weaver"), [] as Array[StringName])
	_blocked["baker>smith"] = true
	_run(0.5)
	var stale := _world.actor(&"baker").awareness.entry(&"smith")
	assert_false(stale.perceived_now())
	assert_almost_eq(stale.freshness, 0.5, 0.05, "seconds since last sensed")
	assert_false(_world.perceives(&"baker", &"smith"))
	assert_eq(_world.last_known(&"baker", &"smith"), Vector3(0, 0, -3), "still remembered")


func test_perception_changed_fires_on_state_changes_only() -> void:
	var changes := []
	_world.perception_changed.connect(func(p: StringName, t: StringName, old: S, new: S) -> void: changes.append([p, t, old, new]))
	_actor(&"baker", Vector3.ZERO)
	_actor(&"smith", Vector3(0, 0, -3), Vector3.FORWARD, false)
	_run(3.0)
	assert_eq(changes, [[&"baker", &"smith", S.UNAWARE, S.SUSPICIOUS], [&"baker", &"smith", S.SUSPICIOUS, S.ALERT]])
	_run(1.0)
	assert_eq(changes.size(), 2, "no repeats while nothing changes")


func test_a_broadcast_reaches_the_hearers_in_range() -> void:
	_actor(&"baker", Vector3.ZERO)
	_actor(&"smith", Vector3(30, 0, 0))
	var heard := _world.broadcast(BustleNoiseModel.event_noise(10.0, Vector3(4, 0, 0)), &"cart")
	assert_eq(heard, 1)
	assert_eq(_state(&"baker", &"cart"), S.SUSPICIOUS)
	assert_eq(_world.last_known(&"baker", &"cart"), Vector3(4, 0, 0))
	assert_false(_world.actor(&"smith").awareness.has(&"cart"), "out of reach")
	_world.broadcast(BustleNoiseModel.event_noise(10.0, Vector3(2, 0, 0)))
	assert_true(_world.actor(&"baker").awareness.has(BustlePerceptionWorld.NOISE_ID), "a sourceless sound is still a lead")


func test_perceivers_are_throttled_and_staggered() -> void:
	_profile.perception_hz = 10.0
	for i in 20:
		_actor(StringName("villager_%d" % i), Vector3(i * 50, 0, 0))
	var per_tick: Array[int] = []
	var total := 0
	for frame in 60:
		_world.tick(STEP)
		per_tick.append(_world.sensed_last_tick)
		total += _world.sensed_last_tick
	assert_between(total, 180, 220, "about 10 senses a second each")
	assert_lt(per_tick.max(), 20, "never all on the same tick")


func test_rays_are_cast_only_for_candidates_in_range_and_cone() -> void:
	_actor(&"baker", Vector3.ZERO, Vector3.FORWARD)
	_actor(&"ahead", Vector3(0, 0, -5), Vector3.FORWARD, false)
	_actor(&"behind", Vector3(0, 0, 5), Vector3.FORWARD, false)
	_actor(&"far", Vector3(0, 0, -50), Vector3.FORWARD, false)
	_world.sense(_world.actor(&"baker"), STEP)
	assert_eq(_world.rays_last_tick, 1)


func test_removing_an_actor_forgets_it_and_awareness_round_trips() -> void:
	_actor(&"baker", Vector3.ZERO)
	_actor(&"smith", Vector3(0, 0, -3), Vector3.FORWARD, false)
	_run(2.0)
	var data := _world.actor(&"baker").awareness.export_state()
	var copy := BustleAwareness.new()
	copy.import_state(JSON.parse_string(JSON.stringify(data)), _profile)
	assert_eq(copy.entry(&"smith").state, S.ALERT)
	assert_eq(copy.entry(&"smith").last_known_position, Vector3(0, 0, -3))
	_world.remove_actor(&"smith")
	assert_false(_world.actor(&"baker").awareness.has(&"smith"))
	assert_null(_world.actor(&"smith"))
