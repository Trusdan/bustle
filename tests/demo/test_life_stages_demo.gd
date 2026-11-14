# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with life stages: the child settler never works the field while the adults do, ages
## and stages survive a save, and the same seed replays the same.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


func _run(world_seed: int) -> RefCounted:
	var run := Colony.build(world_seed, Colony.MODULES, true, null, null, null, Colony.life_stage_rules())
	run.run(2 * DAY)
	return run


func test_the_child_never_works_the_field() -> void:
	var run := _run(1)
	assert_eq(run.life_stages.stage_of(Colony.SETTLER_D), &"child")
	assert_eq(run.life_stages.stage_of(Colony.SETTLER_C), &"elder")
	assert_eq(run.timeline.of(&"stage").size(), Colony.SETTLERS.size(), "one stage entry per settler, at the start")
	var child_field: Array = run.timeline.of(&"choice", Colony.SETTLER_D).filter(func(e: Dictionary) -> bool:
		return e["payload"]["goal"] == String(Colony.FARM) or e["payload"]["option"] == "field")
	assert_eq(child_field, [], "the child never picks field work")
	var adult_field: Array = run.timeline.of(&"choice", Colony.SETTLER_A).filter(func(e: Dictionary) -> bool:
		return e["payload"]["goal"] == String(Colony.FARM))
	assert_gt(adult_field.size(), 0, "an adult still farms")


func test_ages_survive_a_save_and_the_same_seed_replays_the_same() -> void:
	var first := _run(3)
	var second := _run(3)
	assert_eq(first.timeline.hash(), second.timeline.hash())
	var saved: Dictionary = first.life_stages.export_state()
	assert_eq(saved, second.life_stages.export_state())
	var loaded := BustleLifeStages.new(Colony.life_stage_rules())
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.age_years(Colony.SETTLER_D), 10.0)
