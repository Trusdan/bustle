# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Simulation rings, re-sorting: [method BustleSimRings.tick] re-sorts only when something calls for
## it (the player's area or position, the clock's minute, the roster, a request, or the fixed
## rate), and ring changes still apply promptly, dwell and delay timers included.

const FakeWorld := preload("res://tests/rings/test_sim_rings.gd").FakeWorld
const FRAME := 1.0 / 60.0

var _society: BustleSociety
var _world: FakeWorld
var _rings: BustleSimRings


func before_each() -> void:
	_society = BustleSociety.new()
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_world = FakeWorld.new()
	_society.set_port(&"world", _world)
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	_rings = BustleSimRings.new(_society, config)


func _agent(id: StringName, area: StringName, position: Vector3) -> BustleNpcState:
	var state := _society.add_agent(id, &"villager")
	state.position = position
	state.has_position = true
	_world.areas[id] = area
	return state


# Ticks [param seconds] of frames; returns how many re-sorted.
func _run(seconds: float) -> int:
	var sorts := 0
	for i: int in roundi(seconds / FRAME):
		_rings.tick(FRAME)
		sorts += 1 if _rings.last_sorted else 0
	return sorts


func test_with_nothing_changing_it_re_sorts_at_the_fixed_rate_not_every_frame() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	_rings.tick(FRAME)
	assert_true(_rings.last_sorted, "the first tick sorts")
	assert_eq(_run(2.0), 8, "two seconds at 60 frames: eight sorts at 4 Hz, not 120")


func test_a_rate_of_zero_re_sorts_every_tick() -> void:
	_rings.config.resort_hz = 0.0
	_agent(&"a", &"square", Vector3.ZERO)
	assert_eq(_run(0.5), 30)


func test_the_player_changing_area_applies_on_that_tick() -> void:
	_agent(&"a", &"lane", Vector3.ZERO)
	_rings.tick(FRAME)
	_rings.tick(FRAME)
	assert_false(_rings.last_sorted)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT)
	_world.here = &"lane"
	_world.next_to = [&"square"] as Array[StringName]
	_rings.tick(FRAME)
	assert_true(_rings.last_sorted, "a new player area re-sorts at once")
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL, "and the change applies on that tick")


func test_the_player_moving_a_metre_re_sorts_at_once() -> void:
	_agent(&"a", &"square", Vector3(70, 0, 0))
	_rings.tick(FRAME)
	_world.player = Vector3(0.5, 0, 0)
	_rings.tick(FRAME)
	assert_false(_rings.last_sorted, "half a metre: wait for the rate")
	_world.player = Vector3(1.0, 0, 0)
	_rings.tick(FRAME)
	assert_true(_rings.last_sorted, "a metre from the last sort: at once")


func test_an_agent_changing_area_applies_within_one_period_or_at_once_on_request() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	_rings.tick(FRAME)
	_world.areas[&"a"] = &"lane"
	var frames := 0
	while _rings.ring_of(&"a") != BustleSimRings.Ring.LIGHT and frames < 600:
		_rings.tick(FRAME)
		frames += 1
	assert_lte(frames * FRAME, 1.0 / _rings.config.resort_hz + 1e-6, "within one period (%d frames)" % frames)
	_world.areas[&"a"] = &"square"
	_rings.request_sort()
	_rings.tick(FRAME)
	assert_true(_rings.last_sorted)
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.FULL, "a request applies it on the next tick")


func test_a_new_minute_or_a_roster_change_re_sorts_at_once() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	_rings.tick(FRAME)
	_society.ports.clock.advance(1)
	_rings.tick(0.0)
	assert_true(_rings.last_sorted, "the clock's minute changed")
	var version := _society.roster_version
	_agent(&"b", &"far", Vector3.ZERO)
	assert_eq(_society.roster_version, version + 1)
	_rings.tick(0.0)
	assert_true(_rings.last_sorted, "an agent joined")
	assert_eq(_rings.ring_of(&"b"), BustleSimRings.Ring.OFF_SCREEN)
	_society.remove_agent(&"b")
	_rings.tick(0.0)
	assert_true(_rings.last_sorted, "an agent left")
	assert_eq(_rings.counts(), {"FULL": 1, "LIGHT": 0, "OFF_SCREEN": 0})
	_society.remove_agent(&"nobody")
	assert_eq(_society.roster_version, version + 2, "removing no one changes nothing")


func test_the_dwell_still_takes_five_seconds_give_or_take_one_period() -> void:
	var a := _agent(&"a", &"square", Vector3.ZERO)
	_world.player = Vector3.ZERO
	_rings.tick(FRAME)
	_run(6.0)
	a.position = Vector3(80, 0, 0)
	var seconds := 0.0
	while _rings.ring_of(&"a") == BustleSimRings.Ring.FULL and seconds < 10.0:
		_rings.tick(FRAME)
		seconds += FRAME
	assert_eq(_rings.ring_of(&"a"), BustleSimRings.Ring.LIGHT, "demoted by distance")
	assert_lte(seconds, 1.0 / _rings.config.resort_hz + 1e-6, "the dwell had passed, so within one period")
	a.position = Vector3.ZERO
	seconds = 0.0
	while _rings.ring_of(&"a") == BustleSimRings.Ring.LIGHT and seconds < 10.0:
		_rings.tick(FRAME)
		seconds += FRAME
	assert_gte(seconds, _rings.config.min_dwell_seconds - 1e-6, "never sooner than the dwell")
	assert_lte(seconds, _rings.config.min_dwell_seconds + 1.0 / _rings.config.resort_hz + 1e-6,
		"and no later than one period after it (%.2f s)" % seconds)


func test_light_to_off_screen_still_waits_ten_seconds_give_or_take_one_period() -> void:
	_agent(&"a", &"lane", Vector3.ZERO)
	_rings.tick(FRAME)
	_world.areas[&"a"] = &"hill"
	var seconds := 0.0
	while _rings.ring_of(&"a") == BustleSimRings.Ring.LIGHT and seconds < 20.0:
		_rings.tick(FRAME)
		seconds += FRAME
	var delay := _rings.config.light_to_offscreen_delay_seconds
	var period := 1.0 / _rings.config.resort_hz
	assert_gte(seconds, delay - period - 1e-6, "no more than one period early")
	assert_lte(seconds, delay + period + 1e-6, "and no more than one period late (%.2f s)" % seconds)


func test_an_import_changes_the_roster_version() -> void:
	_agent(&"a", &"square", Vector3.ZERO)
	var saved := _society.export_state()
	var loaded := BustleSociety.new()
	loaded.register_archetype(&"villager", BustleGoalLibrary.new())
	var before := loaded.roster_version
	assert_true(loaded.import_state(JSON.parse_string(JSON.stringify(saved))).ok)
	assert_gt(loaded.roster_version, before)
