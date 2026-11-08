# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Simulation rings, part 1: selection by area then distance, the FULL/LIGHT hysteresis, dwell for
## distance changes, immediate area changes, the delay before OFF_SCREEN, whole interiors, a
## scripted walk-past and rapid reversal, and ring changes leaving agents' state untouched. Uses a
## fake world port and the default clock port.


## Areas and positions set by the test.
class FakeWorld:
	extends BustleWorldPort
	var areas: Dictionary = {}
	var here: StringName = &"square"
	var next_to: Array[StringName] = [&"lane"]
	var player := Vector3.ZERO
	var interiors: Array[StringName] = []

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"")

	func player_area() -> StringName:
		return here

	func neighbour_areas(area: StringName) -> Array[StringName]:
		return next_to if area == here else []

	func player_position() -> Vector3:
		return player

	func is_interior(area: StringName) -> bool:
		return interiors.has(area)


var _society: BustleSociety
var _world: FakeWorld
var _rings: BustleSimRings


func before_each() -> void:
	_society = BustleSociety.new()
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_world = FakeWorld.new()
	assert_true(_society.set_port(&"world", _world))
	_rings = BustleSimRings.new(_society)


func _agent(id: StringName, area: StringName, position: Variant = null) -> BustleNpcState:
	var state := _society.add_agent(id, &"villager")
	_world.areas[id] = area
	if position != null:
		state.position = position
		state.has_position = true
	return state


func test_agents_are_sorted_by_area_then_distance_with_the_radius_inclusive() -> void:
	_agent(&"at_edge", &"square", Vector3(60, 0, 0))
	_agent(&"past_edge", &"square", Vector3(60.01, 0, 0))
	_agent(&"nowhere", &"square")
	_agent(&"next_door", &"lane", Vector3.ZERO)
	_agent(&"far", &"hill", Vector3.ZERO)
	_rings.update(0.0)
	var R := BustleSimRings.Ring
	assert_eq([_rings.ring_of(&"at_edge"), _rings.ring_of(&"past_edge"), _rings.ring_of(&"nowhere"),
		_rings.ring_of(&"next_door"), _rings.ring_of(&"far")], [R.FULL, R.LIGHT, R.LIGHT, R.LIGHT, R.OFF_SCREEN])
	assert_eq(_rings.counts(), {"FULL": 1, "LIGHT": 3, "OFF_SCREEN": 1})
	assert_eq(_rings.ring_of(&"unknown"), R.OFF_SCREEN)


func test_full_holds_until_past_the_hysteresis_band() -> void:
	var a := _agent(&"a", &"square", Vector3(10, 0, 0))
	var b := _agent(&"b", &"square", Vector3(70, 0, 0))
	_rings.update(0.0)
	a.position = Vector3(75, 0, 0)
	_rings.update(10.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL, "75 m is still inside 60 + 15")
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.LIGHT, "a LIGHT agent at 70 m needs 60 m to come in")
	a.position = Vector3(75.01, 0, 0)
	_rings.update(10.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT)
	b.position = Vector3(60, 0, 0)
	_rings.update(10.0)
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.FULL)


func test_a_change_by_distance_waits_five_seconds_either_way() -> void:
	var a := _agent(&"a", &"square", Vector3.ZERO)
	_rings.update(0.0)
	a.position = Vector3(80, 0, 0)
	_rings.update(4.9)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL, "4.9 s: held")
	_rings.update(0.1)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "5.0 s: demoted")
	a.position = Vector3.ZERO
	_rings.update(4.9)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "promotion by distance is held too")
	_rings.update(0.1)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL)


func test_area_changes_apply_at_once_full_to_off_screen_included() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	_rings.update(0.0)
	_world.areas[&"a"] = &"lane"
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "into a neighbour area: at once")
	_world.areas[&"a"] = &"square"
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL, "back into the player's area: at once")
	_world.areas[&"a"] = &"hill"
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.OFF_SCREEN, "FULL to out of reach: at once")
	_world.areas[&"a"] = &"lane"
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "off-screen to light: at once")


func test_light_to_off_screen_waits_ten_seconds_and_re_entry_resets_it() -> void:
	_agent(&"a", &"lane", Vector3.ZERO)
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT)
	_world.areas[&"a"] = &"hill"
	_rings.update(9.9)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "9.9 s out of reach: held")
	_world.areas[&"a"] = &"lane"
	_rings.update(0.1)
	_world.areas[&"a"] = &"hill"
	_rings.update(9.9)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "re-entry reset the wait")
	_rings.update(0.1)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.OFF_SCREEN, "10.0 s out of reach")


func test_an_interior_puts_everyone_in_it_in_full() -> void:
	_world.interiors = [&"hall"]
	_world.here = &"hall"
	_agent(&"far_corner", &"hall", Vector3(300, 0, 0))
	_agent(&"no_position", &"hall")
	_agent(&"outside", &"square", Vector3.ZERO)
	_rings.update(0.0)
	var R := BustleSimRings.Ring
	assert_eq([_rings.ring_of(&"far_corner"), _rings.ring_of(&"no_position"), _rings.ring_of(&"outside")],
		[R.FULL, R.FULL, R.OFF_SCREEN])
	var config := BustleSimRingConfig.new()
	config.full_whole_interior = false
	var by_distance := BustleSimRings.new(_society, config)
	by_distance.update(0.0)
	assert_eq([by_distance.ring_of(&"far_corner"), by_distance.ring_of(&"no_position")], [R.LIGHT, R.LIGHT])


func test_a_scripted_walk_past_and_rapid_reversal_change_rings_no_faster_than_the_dwell() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	var changes: Array[float] = []
	var clock := [0.0]
	_rings.ring_changed.connect(func(_id: StringName, _old: int, _new: int) -> void: changes.append(clock[0]))
	_world.player = Vector3(-150, 0, 0)
	_rings.update(0.0)
	for i in 1500:
		# 120 s walking past at 2.5 m/s, then 30 s dithering across the 60 and 75 m edges every 0.2 s.
		var t := i * 0.1
		clock[0] = t
		if t < 120.0:
			_world.player = Vector3(-150 + 2.5 * t, 0, 0)
		else:
			_world.player = Vector3(59.5 if int(t * 5) % 2 == 0 else 75.5, 0, 0)
		_rings.update(0.1)
	assert_gt(changes.size(), 1, "it did change ring on the way past")
	for i in range(1, changes.size()):
		assert_true(changes[i] - changes[i - 1] >= 5.0 - 1e-6, "changes %.1f s and %.1f s apart enough" % [changes[i - 1], changes[i]])


func test_ring_changes_leave_agent_state_untouched() -> void:
	var a := _agent(&"a", &"square", Vector3(1, 0, 2))
	a.data = {"kept": [1, 2]}
	a.area = &"square"
	var senses := BustleSenses.new()
	a.brain.tick(0.1, senses)
	var body := Node3D.new()
	add_child_autofree(body)
	a.attach_body(body)
	body.global_position = Vector3(1, 0, 2)
	var hash := _society.state_hash()
	var brain := a.brain.export_state()
	var seen: Array = []
	_rings.ring_changed.connect(func(_id: StringName, _old: int, new: int) -> void: seen.append(new))
	_rings.update(0.0)
	for area: StringName in [&"lane", &"hill", &"lane", &"square"]:
		_world.areas[&"a"] = area
		_rings.update(10.0)
	var R := BustleSimRings.Ring
	assert_eq(seen, [R.LIGHT, R.OFF_SCREEN, R.LIGHT, R.FULL], "FULL, LIGHT, OFF_SCREEN and back")
	assert_eq(_society.state_hash(), hash)
	assert_eq(a.brain.export_state(), brain)
	assert_eq([a.body(), a.data, a.position], [body, {"kept": [1, 2]}, Vector3(1, 0, 2)])


func test_entry_minutes_come_from_the_clock_and_removed_agents_are_dropped() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	_society.ports.clock.advance(90)
	_rings.update(0.0)
	assert_eq(_rings.entered_minutes(&"a"), 90)
	_society.ports.clock.advance(30)
	_world.areas[&"a"] = &"lane"
	_rings.update(0.0)
	assert_eq(_rings.entered_minutes(&"a"), 120)
	_agent(&"b", &"hill")
	_rings.update(0.0)
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.OFF_SCREEN, "a new agent is sorted at once")
	_society.remove_agent(&"a")
	_rings.update(0.0)
	assert_eq([_rings.entered_minutes(&"a"), _rings.counts()["OFF_SCREEN"]], [-1, 1])
