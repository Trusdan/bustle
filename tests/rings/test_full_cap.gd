# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The optional FULL cap: over the cap the extra agents stay LIGHT, agents already FULL keep their
## places, free places go to the nearest waiting agent (then by id), a lowered cap or a loaded save
## with too many FULL demotes the lowest-ranked at once, and promotion still goes through the dwell,
## catch-up and no-pop-in rules. Deterministic, with no rolls.


## Areas, an interior flag and the bodies, set by the test.
class FakeWorld:
	extends BustleWorldPort
	var areas: Dictionary = {}
	var here: StringName = &"square"
	var interiors: Array[StringName] = []
	var holder: Node
	var bodies: Array[Node3D] = []
	var spawned: Array[StringName] = []
	var freed: Array[StringName] = []

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"far")

	func player_area() -> StringName:
		return here

	func is_interior(area: StringName) -> bool:
		return interiors.has(area)

	func spawn_body(id: StringName, _xf: Transform3D) -> Node3D:
		spawned.append(id)
		var body := Node3D.new()
		if holder != null:
			holder.add_child(body)
		bodies.append(body)
		return body

	func free_body(id: StringName) -> void:
		freed.append(id)


var _society: BustleSociety
var _world: FakeWorld
var _rings: BustleSimRings


func before_each() -> void:
	_society = BustleSociety.new(3)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_world = FakeWorld.new()
	_world.holder = self
	_society.set_port(&"world", _world)
	_rings = BustleSimRings.new(_society)


func after_each() -> void:
	for body: Node3D in _world.bodies:
		if is_instance_valid(body):
			body.free()


func _agent(id: StringName, area: StringName, x: Variant = null) -> BustleNpcState:
	var state := _society.add_agent(id, &"villager")
	_world.areas[id] = area
	if x != null:
		state.position = Vector3(float(x), 0.0, 0.0)
		state.has_position = true
	return state


func _full() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _society.agent_ids():
		if _rings.ring_of(id) == BustleSimRings.Ring.FULL:
			out.append(id)
	return out


func test_no_cap_by_default() -> void:
	assert_eq(BustleSimRingConfig.new().max_full_bodies, 0)
	assert_eq(BustleSimRingConfig.new().max_full_bodies_interior, 0)
	for i in 6:
		_agent(StringName("v%d" % i), &"square", 5 * i)
	_rings.update(0.0)
	assert_eq(_full().size(), 6, "everyone near is FULL with no cap")
	assert_eq(_rings.last_held_by_cap, 0)


func test_outdoors_the_nearest_get_the_places_and_a_tie_goes_by_id() -> void:
	_rings.config.max_full_bodies = 3
	_agent(&"far_one", &"square", 40)
	_agent(&"b", &"square", 20)
	_agent(&"a", &"square", 20)
	_agent(&"nearest", &"square", 10)
	_agent(&"c", &"square", 30)
	_agent(&"no_spot", &"square")
	_rings.update(0.0)
	assert_eq(_full(), [&"a", &"b", &"nearest"] as Array[StringName], "the nearest three; a and b tie at 20 and both fit")
	assert_eq(_world.spawned.size(), 3, "exactly three bodies")
	assert_eq(_rings.last_held_by_cap, 2, "c and far_one held back (no_spot was LIGHT anyway)")
	assert_eq(_rings.ring_of(&"c"), BustleSimRings.Ring.LIGHT)
	assert_eq(_rings.counts(), {"FULL": 3, "LIGHT": 3, "OFF_SCREEN": 0})
	_rings.config.max_full_bodies = 2
	_rings.update(0.0)
	assert_eq(_full(), [&"a", &"nearest"] as Array[StringName], "of the tie at 20, a keeps its place by id")


func test_a_closer_arrival_waits_and_nobody_is_swapped_out() -> void:
	_rings.config.max_full_bodies = 2
	_agent(&"a", &"square", 20)
	_agent(&"b", &"square", 30)
	_rings.update(0.0)
	_agent(&"close", &"square", 5)
	_rings.update(0.0)
	assert_eq(_full(), [&"a", &"b"] as Array[StringName], "those already FULL keep their places")
	assert_eq(_rings.ring_of(&"close"), BustleSimRings.Ring.LIGHT)
	assert_eq(_rings.last_held_by_cap, 1)
	assert_eq(_world.freed, [] as Array[StringName], "no body freed to make room")


func test_cap_without_bodies_still_limits_the_full_ring() -> void:
	_rings.config.manage_bodies = false
	_rings.config.max_full_bodies = 1
	_agent(&"a", &"square", 10)
	_agent(&"b", &"square", 20)
	_rings.update(0.0)
	assert_eq(_full(), [&"a"] as Array[StringName])
	assert_eq(_world.spawned, [] as Array[StringName])


func test_in_an_interior_the_interior_cap_applies_proposed_twelve() -> void:
	# 12 is a PROPOSED per-interior budget from the design, used here as a test value, not a default.
	_world.here = &"hall"
	_world.interiors = [&"hall"]
	_rings.config.max_full_bodies = 30
	_rings.config.max_full_bodies_interior = 12
	for i in 15:
		_agent(StringName("v%02d" % i), &"hall", i)
	_rings.update(0.0)
	assert_eq(_full().size(), 12, "the interior cap, not the outdoor one")
	assert_eq(_rings.last_held_by_cap, 3)
	assert_eq(_full()[-1], &"v11", "the twelve nearest")
	_rings.config.max_full_bodies_interior = 0
	_rings.config.max_full_bodies = 5
	_rings.update(0.0)
	assert_eq(_full().size(), 5, "with no interior cap, the outdoor cap applies inside too")


func test_a_freed_place_goes_to_the_next_in_order_through_the_usual_rules() -> void:
	_world.here = &"hall"
	_world.interiors = [&"hall"]
	_rings.config.max_full_bodies_interior = 2
	_agent(&"a", &"hall", 1)
	_agent(&"b", &"hall", 2)
	_agent(&"c", &"hall", 3)
	var waiting := _agent(&"d", &"far", 4)
	_rings.update(0.0)
	assert_eq(_full(), [&"a", &"b"] as Array[StringName])
	waiting.last_update_minute = 0
	_society.ports.clock.advance(3 * 60)
	_world.areas[&"d"] = &"hall"
	_world.areas[&"c"] = &"far"
	var order: Array = []
	_rings.caught_up.connect(func(id: StringName, _r: Dictionary) -> void: order.append([&"caught_up", id]))
	_rings.body_spawned.connect(func(id: StringName, _p: Vector3, _m: bool) -> void: order.append([&"body", id]))
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"d"), BustleSimRings.Ring.LIGHT, "no place free yet")
	_society.remove_agent(&"a")
	_rings.update(0.0)
	assert_eq(_full(), [&"b", &"d"] as Array[StringName], "the next in order takes the free place")
	assert_eq(order, [[&"caught_up", &"d"], [&"body", &"d"]], "caught up before its body appears")


func test_promotion_outdoors_still_waits_for_the_dwell() -> void:
	_rings.config.max_full_bodies = 1
	_agent(&"a", &"square", 10)
	_agent(&"b", &"square", 20)
	_rings.update(0.0)
	_world.areas[&"a"] = &"far"
	_rings.update(1.0)
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.LIGHT, "a place is free, but b changed ring too recently")
	_rings.update(4.0)
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.FULL, "after the dwell, b takes it")


func test_no_pop_in_still_holds_for_a_promoted_agent() -> void:
	var view := ViewWorld.new()
	view.holder = self
	view.areas = _world.areas
	_world = view
	_society.set_port(&"world", view)
	_rings.config.max_full_bodies = 1
	_agent(&"a", &"square", 10)
	_rings.update(0.0)
	assert_eq(view.spawned, [] as Array[StringName], "everywhere near is in view: the body waits")
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL)


class ViewWorld:
	extends FakeWorld

	func is_in_view(_position: Vector3) -> bool:
		return true


func test_a_lowered_cap_or_a_crowded_save_demotes_the_lowest_ranked_at_once() -> void:
	_rings.config.max_full_bodies = 3
	_agent(&"a", &"square", 10)
	_agent(&"b", &"square", 20)
	_agent(&"c", &"square", 30)
	_rings.update(0.0)
	_rings.config.max_full_bodies = 1
	_rings.update(0.0)
	assert_eq(_full(), [&"a"] as Array[StringName], "the farthest two go first")
	assert_eq(_world.freed, [&"b", &"c"] as Array[StringName], "and their bodies are freed")
	assert_eq(_rings.last_held_by_cap, 2)
	var loaded := BustleSociety.new(3)
	loaded.register_archetype(&"villager", BustleGoalLibrary.new())
	var saved := _society.export_state()
	for agent: Dictionary in saved["agents"]:
		if String(agent["id"]) in ["b", "c"]:
			agent["sim_ring"] = BustleSimRings.Ring.FULL
	assert_true(loaded.import_state(JSON.parse_string(JSON.stringify(saved))).ok)
	loaded.set_port(&"world", _world)
	var config := BustleSimRingConfig.new()
	config.max_full_bodies = 2
	config.manage_bodies = false
	var rings := BustleSimRings.new(loaded, config)
	rings.update(0.0)
	assert_eq(rings.ring_of(&"a"), BustleSimRings.Ring.FULL)
	assert_eq(rings.ring_of(&"b"), BustleSimRings.Ring.FULL)
	assert_eq(rings.ring_of(&"c"), BustleSimRings.Ring.LIGHT, "three saved FULL, a cap of two: the farthest goes")


# A town of 8 near the player (5 to 40 m), 4 next door and 4 far, with a cap of 3, run for
# [param minutes] game minutes at half a second a minute. FULL and LIGHT think every tick at 2 Hz,
# so the run doesn't depend on per-instance think phases.
func _capped_run(saving: bool, thinks: Array) -> String:
	var society := BustleSociety.new(5)
	society.register_archetype(&"villager", BustleGoalLibrary.new())
	var world := FakeWorld.new()
	society.set_port(&"world", world)
	for i in 16:
		var state := society.add_agent(StringName("v%02d" % i), &"villager")
		world.areas[state.id] = &"square" if i < 8 else (&"lane" if i < 12 else &"far")
		state.position = Vector3(5.0 * (i + 1), 0.0, 0.0)
		state.has_position = true
	var make := func(s: BustleSociety) -> BustleSimRings:
		var config := BustleSimRingConfig.new()
		config.manage_bodies = false
		config.max_full_bodies = 3
		config.light_rate_hz = 2.0
		var rings := BustleSimRings.new(s, config)
		rings.senses_provider = func(id: StringName, ring: int, minute: int) -> BustleSenses:
			thinks.append([id, ring, minute])
			return BustleSenses.new()
		return rings
	var rings: BustleSimRings = make.call(society)
	for m in 90:
		society.ports.clock.advance(1)
		rings.tick(0.5)
	if saving:
		var loaded := BustleSociety.new(1)
		loaded.register_archetype(&"villager", BustleGoalLibrary.new())
		assert_true(loaded.import_state(JSON.parse_string(JSON.stringify(society.export_state()))).ok)
		loaded.set_port(&"world", world)
		loaded.ports.clock.advance(90)
		society = loaded
		rings = make.call(society)
	for m in 150:
		society.ports.clock.advance(1)
		rings.tick(0.5)
	assert_eq(rings.counts()["FULL"], 3, "the cap holds")
	return society.state_hash()


func test_a_capped_run_saved_and_loaded_carries_on_exactly_as_if_never_saved() -> void:
	var runs: Array = []
	for saving in [false, true]:
		var thinks: Array = []
		runs.append([_capped_run(saving, thinks), thinks.size()])
	assert_eq(runs[0], runs[1], "the same state and the same number of thinks")


func test_a_capped_run_is_deterministic() -> void:
	assert_eq(_capped_run(false, []), _capped_run(false, []))
