# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Ring ticks and catch-up: how often each ring thinks, OFF_SCREEN phases, catch-up capped at seven
## game days with the rest summarised, determinism, and catch-up on leaving OFF_SCREEN.


## Areas set by the test; everyone not listed is far away.
class Areas:
	extends BustleWorldPort
	var areas: Dictionary = {}

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"far")

	func player_area() -> StringName:
		return &"square"

	var holder: Node
	var bodies: Array[Node3D] = []

	func spawn_body(_id: StringName, _xf: Transform3D) -> Node3D:
		if holder == null:
			return null
		var body := Node3D.new()
		holder.add_child(body)
		bodies.append(body)
		return body

	func neighbour_areas(area: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		if area == &"square":
			out.append(&"lane")
		return out


var _society: BustleSociety
var _world: Areas
var _rings: BustleSimRings
var _thinks: Array = []


func before_each() -> void:
	_society = BustleSociety.new(9)
	_society.register_archetype(&"villager", _library())
	_world = Areas.new()
	_society.set_port(&"world", _world)
	_rings = _make_rings(_society)
	_thinks = []


func _library() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	for id: StringName in [&"a", &"b", &"c"]:
		var goal := BustleGoalDef.new()
		goal.id = id
		goal.band = BustleBands.PERSONAL
		library.goals.append(goal)
	return library


func _make_rings(society: BustleSociety) -> BustleSimRings:
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	var rings := BustleSimRings.new(society, config)
	rings.senses_provider = func(id: StringName, ring: int, minute: int) -> BustleSenses:
		_thinks.append([id, ring, minute])
		return BustleSenses.new()
	return rings


func _count(id: StringName) -> int:
	return _thinks.filter(func(t: Array) -> bool: return t[0] == id).size()


func test_full_thinks_twice_a_second_and_light_once() -> void:
	var near := _society.add_agent(&"near", &"villager")
	near.position = Vector3.ZERO
	near.has_position = true
	_world.areas[&"near"] = &"square"
	_world.areas[&"next"] = &"lane"
	_society.add_agent(&"next", &"villager")
	for i in 100:
		_rings.tick(0.1)
	assert_eq(_count(&"near"), 20, "FULL: 2 Hz over 10 s")
	assert_eq(_count(&"next"), 10, "LIGHT: 1 Hz over 10 s")
	assert_eq(near.last_update_minute, 0)


func test_off_screen_thinks_hourly_at_spread_phases() -> void:
	for i in 200:
		_society.add_agent(StringName("far_%d" % i), &"villager")
	_rings.tick(0.0)
	var minutes: Dictionary = {}
	for id: StringName in _society.agent_ids():
		minutes[_society.get_agent(id).last_update_minute] = true
	assert_gt(minutes.size(), 30, "phases are spread across the hour")
	for m in 120:
		_society.ports.clock.advance(1)
		_rings.tick(0.0)
	for id: StringName in _society.agent_ids():
		assert_eq(_count(id), 2, "%s thought twice in two hours" % id)
	assert_true(_thinks.all(func(t: Array) -> bool: return t[1] == BustleSimRings.Ring.OFF_SCREEN))


func test_catch_up_simulates_whole_hours_up_to_the_cap() -> void:
	var a := _society.add_agent(&"a", &"villager")
	a.last_update_minute = 0
	_society.ports.clock.advance(3 * 1440 + 30)
	var report := _rings.catch_up(&"a")
	assert_eq(report, {"agent": &"a", "from": 0, "to": 3 * 1440 + 30, "ticks": 72,
		"simulated_minutes": 72 * 60, "skipped_minutes": 0})
	assert_eq(a.last_update_minute, 3 * 1440, "the leftover 30 minutes carry over")
	assert_eq(_rings.catch_up(&"a")["ticks"], 0, "nothing more to do")


func test_a_long_absence_is_capped_at_seven_days_and_summarised() -> void:
	var a := _society.add_agent(&"a", &"villager")
	a.last_update_minute = 100
	var summaries: Array = []
	_rings.summary_hook = func(id: StringName, report: Dictionary) -> void: summaries.append([id, report["skipped_minutes"]])
	_society.ports.clock.advance(365 * 1440 + 100)
	var report := _rings.catch_up(&"a")
	assert_eq(report["ticks"], 168, "7 days of hourly thinking, no more")
	assert_eq(_count(&"a"), 168)
	assert_eq(report["skipped_minutes"], (365 - 7) * 1440)
	assert_eq(summaries, [[&"a", (365 - 7) * 1440]])
	assert_eq(_thinks[0][2], 100 + (365 - 7) * 1440 + 60, "the most recent week is the one simulated")
	assert_eq(a.last_update_minute, 365 * 1440 + 100)


func test_catch_up_is_deterministic() -> void:
	var hashes: Array = []
	for run in 2:
		var society := BustleSociety.new(4)
		society.register_archetype(&"villager", _library())
		var a := society.add_agent(&"a", &"villager")
		a.last_update_minute = 0
		society.ports.clock.advance(10 * 1440)
		_make_rings(society).catch_up(&"a")
		hashes.append(society.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_leaving_off_screen_catches_up_first() -> void:
	var a := _society.add_agent(&"a", &"villager")
	_rings.tick(0.0)
	a.last_update_minute = 0
	_society.ports.clock.advance(5 * 60)
	var caught: Array = []
	_rings.caught_up.connect(func(id: StringName, report: Dictionary) -> void: caught.append([id, report["ticks"]]))
	_world.areas[&"a"] = &"lane"
	_rings.tick(0.0)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT)
	assert_eq(caught, [[&"a", 5]])
	assert_eq(a.last_update_minute, 300)


func test_a_save_and_load_carries_on_exactly_as_if_never_saved() -> void:
	var runs: Array = []
	for saving in [false, true]:
		_thinks = []
		var society := _town(4)
		var rings := _make_rings(society)
		for m in 90:
			society.ports.clock.advance(1)
			rings.tick(0.0)
		if saving:
			var loaded := BustleSociety.new(1)
			loaded.register_archetype(&"villager", _library())
			assert_true(loaded.import_state(JSON.parse_string(JSON.stringify(society.export_state()))).ok)
			loaded.set_port(&"world", society.ports.world)
			loaded.ports.clock.advance(90)
			society = loaded
			rings = _make_rings(society)
		for m in 150:
			society.ports.clock.advance(1)
			rings.tick(0.0)
		runs.append([society.state_hash(), _thinks.size()])
	assert_eq(runs[0], runs[1], "the same state and the same number of thinks")


func test_a_promoted_agent_is_caught_up_before_its_body_appears() -> void:
	var society := _town(1)
	var config := BustleSimRingConfig.new()
	var rings := BustleSimRings.new(society, config)
	var order: Array = []
	rings.caught_up.connect(func(id: StringName, _r: Dictionary) -> void: order.append([&"caught_up", id]))
	rings.body_spawned.connect(func(id: StringName, _p: Vector3, _m: bool) -> void: order.append([&"body", id]))
	rings.tick(0.0)
	var a := society.get_agent(&"villager_0")
	a.last_update_minute = 0
	a.position = Vector3.ZERO
	a.has_position = true
	society.ports.clock.advance(10 * 1440)
	(society.ports.world as Areas).holder = self
	(society.ports.world as Areas).areas[&"villager_0"] = &"square"
	rings.tick(0.0)
	assert_eq(rings.ring_of(&"villager_0"), BustleSimRings.Ring.FULL)
	assert_eq(order.map(func(o: Array) -> StringName: return o[0]), [&"caught_up", &"body"],
		"promoted from OFF_SCREEN: the missed week is replayed before the body appears")
	assert_eq(a.last_update_minute, 10 * 1440)
	assert_not_null(a.body())
	for body: Node3D in (society.ports.world as Areas).bodies:
		body.free()


func _town(count: int) -> BustleSociety:
	var society := BustleSociety.new(1)
	society.register_archetype(&"villager", _library())
	var areas := Areas.new()
	society.set_port(&"world", areas)
	for i in count:
		society.add_agent(StringName("villager_%d" % i), &"villager")
	return society
