# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The population bench's pieces on a small town: the rings it builds, a game day with nobody stuck,
## the same state from the same seed, and the save size. The bench itself (40 / 40 / 200, timed)
## runs in CI as a report.

const Bench := preload("res://bench/population_bench.gd")


func test_the_town_puts_each_agent_in_its_ring() -> void:
	var town := Bench.build(4, 3, 20, 1)
	assert_eq((town["rings"] as BustleSimRings).counts(), {"FULL": 4, "LIGHT": 3, "OFF_SCREEN": 20})


func test_a_game_day_has_nobody_stuck_and_replays_from_the_seed() -> void:
	var first := Bench.stuck_pass(Bench.build(4, 4, 20, 1), 1)
	var second := Bench.stuck_pass(Bench.build(4, 4, 20, 1), 1)
	assert_eq(first["spells"], [], "nobody stuck")
	assert_lte(int(first["longest"]), 120)
	assert_eq(second["hash"], first["hash"], "the same seed, the same state: no rolls")
	assert_ne(Bench.stuck_pass(Bench.build(4, 4, 20, 2), 1)["hash"], first["hash"], "another seed, other phases")


func test_choices_keep_changing_without_rolls() -> void:
	var minute := 0
	var goals := {}
	for i: int in 48:
		var senses := Bench.senses_for(1, &"townsfolk_000", minute)
		var best := ""
		var top := -1.0
		for need: StringName in senses.inputs:
			if senses.inputs[need] > top:
				top = senses.inputs[need]
				best = String(need)
		goals[best] = true
		minute += 60
		assert_eq(Bench.senses_for(1, &"townsfolk_000", minute).inputs, Bench.senses_for(1, &"townsfolk_000", minute).inputs)
	assert_eq(goals.size(), 3, "over two days each need takes its turn on top")


func test_the_save_size_is_reported_per_agent() -> void:
	var town := Bench.build(2, 2, 6, 1)
	Bench.time_hour(town, 120)
	var bytes := Bench.save_bytes(town)
	assert_gt(bytes, 0)
	assert_lte(bytes / 10, Bench.BUDGET_SAVE_BYTES, "within the proposed save budget")


func test_the_timings_cover_every_ring_and_the_whole_frame() -> void:
	var result := Bench.time_hour(Bench.build(2, 2, 6, 1), 600)
	for key: String in ["full_avg", "full_p99", "light_avg", "light_p99", "off_avg", "off_p99", "frame_avg", "frame_p99"]:
		assert_true(result.has(key), key)
		assert_gte(float(result[key]), 0.0)
	assert_eq(result["minutes"], 5, "600 frames at 30× are five game minutes")
	assert_eq(Bench.p99([1.0, 2.0, 3.0] as Array[float]), 3.0)
	assert_almost_eq(Bench.average([1.0, 2.0, 3.0] as Array[float]), 2.0, 1e-9)
