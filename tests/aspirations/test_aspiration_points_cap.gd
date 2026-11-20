# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The optional cap on aspiration points (BustleAspirationConfig.max_points). Unset (negative, the
## default), points grow as before. Set, add_points adds only what reaches the cap, and
## points_changed and on_points get the amount actually added; at the cap it adds nothing and
## returns false. The cap only limits earning: a save above it loads as saved, a cap lowered later
## takes nothing away, and in both cases the agent earns nothing until spending takes it below.

const HOUR := 60

var _config: BustleAspirationConfig
var _asp: BustleAspirations
var _changes: Array = []
var _hook: Array = []


func _want(id: StringName, points: int) -> BustleWantDef:
	var def := BustleWantDef.new()
	def.id = id
	def.auto = false
	def.done_fact = StringName("done." + String(id))
	def.points = points
	def.thought = load("res://demo/aspirations/want_met.tres")
	return def


func before_each() -> void:
	_config = BustleAspirationConfig.new()
	_config.wants = [_want(&"chat", 5), _want(&"feast", 8)] as Array[BustleWantDef]
	_asp = BustleAspirations.new(&"baker", _config)
	_changes = []
	_hook = []
	_asp.points_changed.connect(func(agent: StringName, amount: int, reason: StringName, total: int) -> void:
		_changes.append([agent, amount, reason, total]))
	_asp.on_points = func(agent: StringName, amount: int, reason: StringName) -> void: _hook.append([agent, amount, reason])


func test_unset_points_grow_as_before() -> void:
	assert_eq(_config.max_points, -1, "no cap by default")
	for i in 3:
		assert_true(_asp.add_points(1000000, &"gift"))
	assert_eq(_asp.points(), 3000000)
	assert_eq(_changes[-1], [&"baker", 1000000, &"gift", 3000000])
	_config.max_points = -7
	assert_true(_asp.add_points(5, &"gift"), "any negative cap is no cap")
	assert_eq(_asp.points(), 3000005)


func test_earning_stops_at_the_cap_and_reports_what_was_added() -> void:
	_config.max_points = 10
	assert_true(_asp.add_points(4, &"gift"))
	assert_true(_asp.add_points(9, &"gift"), "part of it fits")
	assert_eq(_asp.points(), 10)
	assert_eq(_changes, [[&"baker", 4, &"gift", 4], [&"baker", 6, &"gift", 10]], "the real change, 6 not 9")
	assert_eq(_hook, [[&"baker", 4, &"gift"], [&"baker", 6, &"gift"]], "on_points gets what was added")
	assert_false(_asp.add_points(3, &"gift"), "at the cap nothing is added")
	assert_eq([_asp.points(), _changes.size(), _hook.size()], [10, 2, 2], "and nothing is reported")
	assert_true(_asp.spend_points(3, &"reward"))
	assert_true(_asp.add_points(5, &"gift"))
	assert_eq(_asp.points(), 10)
	assert_eq(_changes[-1], [&"baker", 3, &"gift", 10], "after spending, it earns back up to the cap")


func test_a_fulfilled_want_earns_only_up_to_the_cap() -> void:
	_config.max_points = 10
	_asp.post_want(&"chat", 0)
	_asp.post_want(&"feast", 0)
	_asp.update(HOUR, null, {"done.chat": true, "done.feast": true})
	assert_eq(_asp.points(), 10)
	assert_eq(_changes, [[&"baker", 5, &"want:chat", 5], [&"baker", 5, &"want:feast", 10]], "feast is worth 8; 5 fit")
	assert_eq(_hook, [[&"baker", 5, &"want:chat"], [&"baker", 5, &"want:feast"]])


func test_a_cap_of_zero_earns_nothing() -> void:
	_config.max_points = 0
	assert_false(_asp.add_points(5, &"gift"))
	assert_eq([_asp.points(), _changes, _hook], [0, [], []])


func test_a_save_above_the_cap_loads_as_saved_and_earns_nothing_until_spent() -> void:
	_asp.add_points(25, &"gift")
	var saved := _asp.export_state()
	_config.max_points = 10
	var loaded := BustleAspirations.new(&"baker", _config)
	assert_true(loaded.import_state(saved), "a save above the cap loads")
	assert_eq(loaded.points(), 25, "with its points as saved")
	assert_eq(loaded.export_state(), saved, "and round-trips")
	assert_false(loaded.add_points(5, &"gift"), "above the cap, nothing is earned")
	assert_eq(loaded.points(), 25)
	assert_true(loaded.spend_points(20, &"reward"))
	assert_true(loaded.add_points(10, &"gift"))
	assert_eq(loaded.points(), 10, "once below, it earns up to the cap")


func test_a_lowered_cap_takes_nothing_away() -> void:
	_asp.add_points(25, &"gift")
	_config.max_points = 10
	assert_eq(_asp.points(), 25, "nothing is taken")
	assert_false(_asp.add_points(1, &"gift"))
	assert_eq(_asp.points(), 25)
	_config.max_points = 30
	assert_true(_asp.add_points(10, &"gift"), "a raised cap leaves room again")
	assert_eq(_asp.points(), 30)


func test_saves_with_and_without_points_still_load_under_a_cap() -> void:
	_config.max_points = 10
	var saved := _asp.export_state()
	saved.erase("points")
	assert_true(_asp.import_state(saved), "an older save without points")
	assert_eq(_asp.points(), 0)
	saved["points"] = -1
	assert_false(_asp.import_state(saved), "a negative total is still refused")
	assert_eq(_asp.points(), 0, "and changes nothing")
