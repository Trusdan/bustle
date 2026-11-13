# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Indoors and outdoors: the environment port's rooms give the need conditions, and the demo's
## outdoors and indoors needs rise and fall with them. No port: no change.

const House := preload("res://demo/house/house.gd")
const OUTDOORS := "res://demo/environment/outdoors.tres"
const INDOORS := "res://demo/environment/indoors.tres"
const DAY := 1440

var _port: BustleEnvironmentPort
var _needs: BustleNeedSet


func before_each() -> void:
	_port = BustleEnvironmentPort.new()
	_needs = BustleNeedSet.new()
	_needs.add_need(load(OUTDOORS))
	_needs.add_need(load(INDOORS))


func _hours(hours: int, port: BustleEnvironmentPort = _port) -> void:
	for hour: int in hours:
		_needs.advance(60.0, BustleEnvironmentPort.conditions_of(port, &"baker"))


func test_a_room_means_indoors() -> void:
	assert_eq(_port.conditions(&"baker"), [BustleEnvironmentPort.OUTDOORS] as Array[StringName])
	_port.set_room(&"baker", &"hall")
	assert_true(_port.is_indoors(&"baker"))
	assert_eq(_port.conditions(&"baker"), [BustleEnvironmentPort.INDOORS] as Array[StringName])
	_port.set_room(&"baker", &"")
	assert_false(_port.is_indoors(&"baker"))


# Acceptance (1): kept indoors, the outdoors need rises; outside, it falls.
func test_the_outdoors_need_rises_indoors_and_falls_outside() -> void:
	_port.set_room(&"baker", &"hall")
	_hours(10)
	assert_almost_eq(_needs.pressure(&"outdoors"), 0.5, 1e-6, "0.05 an hour indoors")
	_port.set_room(&"baker", &"")
	_hours(1)
	assert_almost_eq(_needs.pressure(&"outdoors"), 0.25, 1e-6, "0.25 an hour back outside")
	_hours(4)
	assert_eq(_needs.pressure(&"outdoors"), 0.0, "and no lower than 0")


# Acceptance (2): the indoors need mirrors it.
func test_the_indoors_need_mirrors_it() -> void:
	_hours(10)
	assert_almost_eq(_needs.pressure(&"indoors"), 0.5, 1e-6, "rises outside")
	assert_eq(_needs.pressure(&"outdoors"), 0.0)
	_port.set_room(&"baker", &"hall")
	_hours(1)
	assert_almost_eq(_needs.pressure(&"indoors"), 0.25, 1e-6, "falls indoors")
	assert_almost_eq(_needs.pressure(&"outdoors"), 0.05, 1e-6)


# Acceptance (3): with no environment port, the environment changes no need.
func test_no_port_changes_no_need() -> void:
	_needs.set_pressure(&"outdoors", 0.4)
	_needs.set_pressure(&"indoors", 0.3)
	assert_true(BustleEnvironmentPort.conditions_of(null, &"baker").is_empty())
	_hours(24, null)
	assert_eq(_needs.pressure(&"outdoors"), 0.4)
	assert_eq(_needs.pressure(&"indoors"), 0.3)
	assert_push_error_count(0)


func test_the_house_without_the_environment_is_unchanged() -> void:
	var plain := House.build()
	plain.run(DAY)
	var quiet := House.build()
	for id: StringName in [House.RESIDENT_A, House.RESIDENT_B]:
		quiet.needs_of(id).add_need(load(OUTDOORS))
		quiet.needs_of(id).add_need(load(INDOORS))
		quiet.needs_of(id).set_pressure(&"outdoors", 0.4)
	quiet.run(DAY)
	assert_eq(quiet.needs_of(House.RESIDENT_A).pressure(&"outdoors"), 0.4, "no port, no change")
	assert_eq(quiet.needs_of(House.RESIDENT_B).pressure(&"indoors"), 0.0)
	assert_eq(quiet.timeline.hash(), plain.timeline.hash(), "and the residents behave the same")
	assert_push_error_count(0)


# Acceptance (1)–(2) in the house demo: one resident kept in, one kept out.
func test_the_house_moves_the_needs_with_the_rooms() -> void:
	var house := House.build()
	var port := BustleEnvironmentPort.new()
	house.enable_environment(port)
	for id: StringName in [House.RESIDENT_A, House.RESIDENT_B]:
		house.needs_of(id).add_need(load(OUTDOORS))
		house.needs_of(id).add_need(load(INDOORS))
	port.set_room(House.RESIDENT_A, &"kitchen")
	house.run(8 * 60)
	var kept_in := house.needs_of(House.RESIDENT_A)
	var kept_out := house.needs_of(House.RESIDENT_B)
	assert_almost_eq(kept_in.pressure(&"outdoors"), 0.4, 1e-6)
	assert_eq(kept_in.pressure(&"indoors"), 0.0)
	assert_almost_eq(kept_out.pressure(&"indoors"), 0.4, 1e-6)
	assert_eq(kept_out.pressure(&"outdoors"), 0.0)
	port.set_room(House.RESIDENT_A, &"")
	house.run(60)
	assert_almost_eq(kept_in.pressure(&"outdoors"), 0.15, 1e-6, "out for an hour")


# Acceptance (4): save and load keep the needs and who is indoors; replay matches.
func test_save_and_load_carry_on_the_same() -> void:
	_port.set_room(&"baker", &"hall")
	_hours(5)
	var saved: Variant = JSON.parse_string(JSON.stringify({"needs": _needs.export_state(), "env": _port.export_state()}))
	_hours(3)
	var straight := _needs.export_state()
	before_each()
	assert_true(_needs.import_state(saved["needs"]))
	assert_true(_port.import_state(saved["env"]))
	assert_true(_port.is_indoors(&"baker"), "still indoors after the load")
	_hours(3)
	assert_eq(_needs.export_state(), straight)


func test_the_same_seed_replays_the_same() -> void:
	var runs: Array = []
	for run: int in 2:
		var house := House.build(7)
		var port := BustleEnvironmentPort.new()
		house.enable_environment(port)
		for id: StringName in [House.RESIDENT_A, House.RESIDENT_B]:
			house.needs_of(id).add_need(load(OUTDOORS))
			house.needs_of(id).add_need(load(INDOORS))
		for hour: int in 30:
			port.set_room(House.RESIDENT_A, &"kitchen" if hour % 5 < 3 else &"")
			port.set_room(House.RESIDENT_B, &"" if hour % 4 < 2 else &"hall")
			house.run(60)
		runs.append([house.timeline.hash(), house.needs_of(House.RESIDENT_A).export_state(),
			house.needs_of(House.RESIDENT_B).export_state(), port.export_state()])
	assert_eq(runs[0], runs[1])


# Part 1 review: a rule needs a held thought with reason kind environment.
func test_room_thought_rules_need_a_held_thought() -> void:
	var timed := BustleThoughtDef.new()
	timed.id = &"pleasant_room"
	timed.duration_hours = 2.0
	timed.reason_kind = &"environment"
	var rule := BustleRoomThought.new()
	rule.score = &"beauty"
	rule.at_least = 0.6
	rule.thought = timed
	assert_false(rule.is_valid(), "a timed thought would never be held")
	timed.duration_hours = 0.0
	assert_true(rule.is_valid())
	timed.reason_kind = &"event"
	assert_false(rule.is_valid(), "another reason kind")
	assert_false(BustleRoomThoughts.new().add_rule(rule))
