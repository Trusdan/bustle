# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The life-stages module: the stage comes from the age, stage_changed fires once per real change,
## and ages and stages survive a save.

const Rules := preload("res://tests/life_stages/test_life_stage_rules.gd")

var _changes: Array = []


func _module() -> BustleLifeStages:
	_changes = []
	var module := BustleLifeStages.new(Rules.three())
	module.stage_changed.connect(_on_changed)
	return module


func _on_changed(id: StringName, old: StringName, new: StringName) -> void:
	_changes.append([id, old, new])


func test_the_stage_comes_from_the_age() -> void:
	var module := _module()
	assert_eq(module.stage_of(&"x"), &"", "no age, no stage")
	assert_true(module.set_age(&"x", 20.0))
	assert_eq(module.stage_of(&"x"), &"young")
	module.set_age(&"x", 1600.0)
	assert_eq(module.stage_of(&"x"), &"grown")
	module.set_age(&"x", 7000.0)
	assert_eq(module.stage_of(&"x"), &"old")


func test_stage_changed_fires_once_per_real_change() -> void:
	var module := _module()
	module.set_age(&"x", 20.0)
	module.set_age(&"x", 30.0)
	module.set_age(&"x", 1599.0)
	assert_eq(_changes, [[&"x", &"", &"young"]], "the first age is a change; ages in the same stage aren't")
	module.set_age(&"x", 1600.0)
	module.set_age(&"x", 1600.0)
	module.set_age(&"x", 2000.0)
	assert_eq(_changes.size(), 2)
	assert_eq(_changes[1], [&"x", &"young", &"grown"])
	module.set_age(&"x", 6500.0)
	assert_eq(_changes[2], [&"x", &"grown", &"old"])
	assert_eq(_changes.size(), 3)


func test_bad_ages_are_refused() -> void:
	var module := _module()
	assert_false(module.set_age(&"x", -1.0))
	assert_false(module.set_age(&"x", NAN))
	assert_false(module.set_age(&"", 5.0))
	assert_false(module.has_age(&"x"))
	assert_eq(_changes, [])


func test_ages_and_stages_survive_save_and_load() -> void:
	var module := _module()
	module.set_age(&"b", 1700.0)
	module.set_age(&"a", 10.0)
	module.set_age(&"c", 6100.0)
	var saved := module.export_state()
	assert_eq(saved["ages"].keys(), ["a", "b", "c"], "in id order")
	var loaded := _module()
	assert_true(loaded.import_state(saved))
	assert_eq(_changes, [], "loading emits nothing")
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.stage_of(&"b"), &"grown")
	assert_eq(loaded.age_days(&"a"), 10.0)
	assert_false(loaded.allows_goal(&"a", [&"labour"]))
	loaded.set_age(&"a", 1600.0)
	assert_eq(_changes, [[&"a", &"young", &"grown"]], "a change after loading fires once")


func test_a_bad_save_is_refused_and_changes_nothing() -> void:
	var module := _module()
	module.set_age(&"a", 10.0)
	var good := module.export_state()
	var bad: Array[Dictionary] = []
	for i: int in 5:
		bad.append(good.duplicate(true))
	bad[0]["version"] = 99
	bad[1]["stages"]["a"] = "nobody"
	bad[2]["ages"]["a"] = -5.0
	bad[3]["stages"]["z"] = "young"
	bad[4]["ages"] = []
	var target := _module()
	target.set_age(&"q", 2000.0)
	var before := target.export_state()
	for saved: Dictionary in bad:
		assert_false(target.import_state(saved))
		assert_eq(target.export_state(), before)


func test_the_same_ages_give_the_same_state() -> void:
	var first := _module()
	var second := _module()
	for module: BustleLifeStages in [first, second]:
		for row: Array in [[&"a", 5.0], [&"b", 1600.0], [&"a", 1700.0], [&"c", 9000.0]]:
			module.set_age(row[0], row[1])
	assert_eq(first.export_state(), second.export_state())
