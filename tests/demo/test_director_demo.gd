# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with the storyteller switched on: its neutral deck fires beside the cold snap, its
## thoughts reach the settlers, the same seed replays the same, and without it nothing changes.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


func _run(world_seed: int, days: int = 4) -> RefCounted:
	var run := Colony.build(world_seed)
	var rules := BustleDirectorRules.new()
	rules.beat_gap_minutes = 360
	run.enable_director(Colony.director_events(), rules)
	run.run(days * DAY)
	return run


func test_the_deck_fires_beside_the_cold_snap() -> void:
	var run := _run(1)
	var fired: Array = run.timeline.of(&"director").map(func(e: Dictionary) -> String: return e["payload"]["event"])
	assert_true(fired.has("gale") and fired.has("fair_day") and fired.has("travellers"), str(fired))
	assert_gt(run.timeline.of(&"event").size(), 0, "the cold snap still runs")
	var thoughts: Array = run.timeline.of(&"effect").filter(func(e: Dictionary) -> bool: return e["payload"]["kind"] == "thought")
	assert_eq(thoughts.size(), Colony.SETTLERS.size() * fired.filter(func(id: String) -> bool: return id != "travellers").size(),
		"every settler, for every thought event")
	var spawns: Array = run.timeline.of(&"effect").filter(func(e: Dictionary) -> bool: return e["payload"]["kind"] == "spawn")
	assert_eq(spawns.size(), fired.count("travellers"), "asked once per firing")
	assert_true(spawns.all(func(e: Dictionary) -> bool: return not e["payload"]["done"]), "the default world makes nothing")
	assert_gt(run.timeline.of(&"thought").filter(func(e: Dictionary) -> bool: return e["payload"]["thought"] == "windswept").size(), 0)


func test_the_same_seed_replays_the_same_and_off_changes_nothing() -> void:
	var first := _run(2)
	var second := _run(2)
	assert_eq(first.timeline.hash(), second.timeline.hash())
	assert_eq(first.director.export_state(), second.director.export_state())
	var plain := Colony.build(2)
	plain.run(4 * DAY)
	var other := Colony.build(2)
	other.run(4 * DAY)
	assert_eq(plain.timeline.hash(), other.timeline.hash())
	assert_null(plain.director, "off unless switched on")
