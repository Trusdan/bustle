# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with romance: two fond settlers court and become partners, two fond siblings never
## court, a partner taking to someone else brings jealousy, and the same seed replays the same.
## Without romance, the colony is unchanged.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


static func _entries(run: RefCounted, kind: String) -> Array:
	return run.timeline.entries().filter(func(entry: Dictionary) -> bool: return entry["kind"] == kind)


# Acceptance (4): on when enabled.
func test_the_colony_shows_courtship_family_and_jealousy() -> void:
	var run := Colony.build(1, Colony.MODULES, false, null, null, Colony.romance_rules())
	run.run(3 * DAY - run.now)
	assert_eq(run.romance.status_of(Colony.SETTLER_C, Colony.SETTLER_D), BustleRomance.PARTNER)
	var steps: Array = _entries(run, "romance").map(func(entry: Dictionary) -> String: return entry["payload"]["status"])
	assert_eq(steps, ["courting", "partner"])
	assert_eq(run.romance.status_of(Colony.SETTLER_A, Colony.SETTLER_B), &"", "siblings never court")
	assert_eq(run.store.kinds_between(Colony.SETTLER_B, Colony.SETTLER_A), PackedStringArray(["friend", "sibling"]))
	run.store.add_opinion(Colony.SETTLER_D, Colony.SETTLER_A, 25.0, {"why": "fond"}, 10.0)
	run.run(DAY)
	var jealous := _entries(run, "jealous")
	assert_eq(jealous.size(), 1)
	assert_eq(jealous[0]["agent"], String(Colony.SETTLER_C))
	assert_eq(jealous[0]["payload"]["rival"], String(Colony.SETTLER_A))


func test_the_same_seed_replays_the_same() -> void:
	var hashes: Array[String] = []
	for i: int in 2:
		var run := Colony.build(5, Colony.MODULES, true, null, null, Colony.romance_rules())
		run.run(4 * DAY - run.now)
		hashes.append(run.timeline.hash())
	assert_eq(hashes[0], hashes[1])


# Acceptance (4): off by default.
func test_without_romance_the_colony_is_unchanged() -> void:
	var plain := Colony.build()
	plain.run(3 * DAY - plain.now)
	assert_null(plain.romance)
	assert_true(_entries(plain, "romance").is_empty())
	assert_eq(plain.store.kinds_between(Colony.SETTLER_B, Colony.SETTLER_A), PackedStringArray(["friend"]))
	assert_push_error_count(0)


func test_romance_needs_the_social_module() -> void:
	var quiet := Colony.build(1, [] as Array[StringName], false, null, null, Colony.romance_rules())
	quiet.run(DAY)
	assert_null(quiet.romance, "no store, no romance")
	assert_push_error_count(0)
