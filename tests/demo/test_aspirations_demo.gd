# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with aspirations: settlers take wants from their personality, fulfil them at the stove
## and the hearth for points, fear the cold once the cold snap starts, and the same seed replays the
## same. Without aspirations, the colony is unchanged.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


static func _entries(run: RefCounted, kind: String, what: String = "") -> Array:
	return run.timeline.entries().filter(func(entry: Dictionary) -> bool:
		return entry["kind"] == kind and (what == "" or entry["payload"].get("what", "") == what))


# Acceptance (5): the demo shows wants, fears and points.
func test_the_colony_shows_wants_fears_and_points() -> void:
	var run := Colony.build(1, Colony.MODULES, true, null, Colony.aspirations())
	run.run(5 * DAY - run.now)
	for id: StringName in Colony.SETTLERS:
		var asp: BustleAspirations = run.aspirations_of(id)
		assert_gt(asp.points(), 0, String(id) + " earned points")
		var formed := _entries(run, "fear", "formed").filter(func(entry: Dictionary) -> bool: return entry["agent"] == String(id))
		assert_eq(formed.size(), 1, String(id) + " feared the cold once")
		assert_eq(formed[0]["t"], Colony.COLD_START, "as the cold snap began")
	assert_false(_entries(run, "want", "added").is_empty())
	assert_false(_entries(run, "want", "fulfilled").is_empty())
	assert_false(_entries(run, "want", "expired").is_empty(), "some go unmet")
	assert_eq(_entries(run, "fear", "expired").size(), 4, "two days later")
	var points := 0
	for entry: Dictionary in _entries(run, "points"):
		points += int(entry["payload"]["amount"])
	var held := 0
	for id: StringName in Colony.SETTLERS:
		held += run.aspirations_of(id).points()
	assert_eq(points, held, "every point is on the timeline")


func test_the_fear_of_cold_lowers_the_field() -> void:
	var run := Colony.build(1, Colony.MODULES, true, null, Colony.aspirations())
	run.run(Colony.COLD_START + 10 - run.now)
	var asp: BustleAspirations = run.aspirations_of(Colony.SETTLER_A)
	assert_true(asp.has_fear(&"fear_of_cold"))
	assert_almost_eq(asp.score(Colony.FARM, &"field"), 0.5, 1e-9)
	assert_eq(asp.score(Colony.FARM, &"stove"), 1.0)
	assert_eq(run.mood_of(Colony.SETTLER_A).count(&"frightened"), 1)


func test_the_same_seed_replays_the_same() -> void:
	var hashes: Array[String] = []
	for i: int in 2:
		var run := Colony.build(3, Colony.MODULES, true, null, Colony.aspirations())
		run.run(4 * DAY - run.now)
		hashes.append(run.timeline.hash())
	assert_eq(hashes[0], hashes[1])


func test_without_aspirations_the_colony_is_unchanged() -> void:
	var plain := Colony.build()
	plain.run(2 * DAY - plain.now)
	assert_null(plain.aspirations_of(Colony.SETTLER_A))
	assert_true(_entries(plain, "want").is_empty())
	assert_push_error_count(0)
