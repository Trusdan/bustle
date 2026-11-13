# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with romance: when a partner takes to someone else, the jealous settler's opinion of
## that rival drops a little, once, and the same seed replays the same.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


func _run(world_seed: int) -> RefCounted:
	var run := Colony.build(world_seed, Colony.MODULES, false, null, null, Colony.romance_rules())
	run.run(3 * DAY - run.now)
	run.store.add_opinion(Colony.SETTLER_D, Colony.SETTLER_A, 25.0, {"why": "fond"}, 10.0)
	run.run(DAY)
	return run


func test_jealousy_lowers_the_rival_once_in_the_demo() -> void:
	var run := _run(1)
	var entries: Array = run.store.reasons(Colony.SETTLER_C, Colony.SETTLER_A, 20).filter(func(entry: Dictionary) -> bool:
		return entry["reason"].has("jealous"))
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["value"], -5.0)
	assert_eq(entries[0]["reason"]["partner"], String(Colony.SETTLER_D))
	assert_eq(run.romance.status_of(Colony.SETTLER_C, Colony.SETTLER_D), BustleRomance.PARTNER, "still partners")


func test_the_same_seed_replays_the_same_with_jealousy() -> void:
	var first := _run(2)
	var second := _run(2)
	assert_eq(first.timeline.hash(), second.timeline.hash())
	assert_eq(first.store.export_state(), second.store.export_state())
