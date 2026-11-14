# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Aging on the clock: ages move on with game days, one long catch-up step equals many short ones,
## and every stage crossed fires once, in order.

const Rules := preload("res://tests/life_stages/test_life_stage_rules.gd")
const DAY := 1440

var _changes: Array = []


func _module(ages: Dictionary = {}) -> BustleLifeStages:
	var module := BustleLifeStages.new(Rules.three())
	for id: StringName in ages:
		module.set_age(id, ages[id])
	module.stage_changed.connect(func(id: StringName, old: StringName, new: StringName) -> void:
		_changes.append([id, old, new]))
	return module


func before_each() -> void:
	_changes = []


func test_ages_move_on_by_the_day_and_match_set_age() -> void:
	var module := _module({&"a": 10.0, &"b": 1595.0})
	assert_true(module.advance_to(5 * DAY))
	assert_eq(module.now(), 5 * DAY)
	assert_eq(module.age_days(&"a"), 15.0)
	assert_eq(module.age_days(&"b"), 1600.0)
	var direct := BustleLifeStages.new(Rules.three())
	direct.set_age(&"b", 1600.0)
	assert_eq(module.stage_of(&"b"), direct.stage_of(&"b"), "the same stage as setting the age")
	assert_eq(_changes, [[&"b", &"young", &"grown"]])
	module.advance_to(5 * DAY + 720)
	assert_eq(module.age_days(&"a"), 15.5, "part days count")


func test_one_catch_up_equals_day_by_day_and_crosses_each_stage_in_order() -> void:
	var ages := {&"a": 1590.0, &"b": 1599.5, &"c": 5999.0, &"d": 20.0}
	var caught := _module(ages)
	caught.advance_to(4500 * DAY)
	var caught_changes := _changes.duplicate()
	_changes = []
	var stepped := _module(ages)
	for day: int in range(1, 4501):
		stepped.advance_to(day * DAY)
	assert_eq(caught.export_state(), stepped.export_state(), "the same state")
	assert_eq(caught_changes, _changes, "the same signals, in the same order")
	assert_eq(caught_changes, [
		[&"b", &"young", &"grown"], [&"c", &"grown", &"old"], [&"a", &"young", &"grown"],
		[&"d", &"young", &"grown"], [&"b", &"grown", &"old"], [&"a", &"grown", &"old"],
	], "every stage crossed, once, in the order the ages reached them")
	assert_eq(caught.stage_of(&"d"), &"grown")


func test_no_change_fires_nothing_and_time_never_goes_back() -> void:
	var module := _module({&"a": 10.0})
	assert_true(module.advance_to(DAY))
	assert_true(module.advance_to(DAY), "the same minute again is a no-op")
	assert_eq(_changes, [])
	assert_false(module.advance_to(DAY - 1))
	assert_eq(module.now(), DAY)
	assert_eq(module.age_days(&"a"), 11.0)


func test_set_age_anchors_at_the_current_minute() -> void:
	var module := _module()
	module.advance_to(3 * DAY)
	module.set_age(&"a", 100.0)
	module.advance_to(5 * DAY)
	assert_eq(module.age_days(&"a"), 102.0)


func test_the_day_length_is_configurable() -> void:
	var rules := Rules.three()
	rules.minutes_per_day = 100
	var module := BustleLifeStages.new(rules)
	module.set_age(&"a", 0.0)
	module.advance_to(250)
	assert_eq(module.age_days(&"a"), 2.5)
	rules.minutes_per_day = 0
	assert_eq(module.revalidate(), "minutes_per_day must be above 0")
	assert_false(module.advance_to(300))
