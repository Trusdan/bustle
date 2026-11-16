# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The performance gate (bench/perf_gate.gd) judges the benches' summary lines against the budgets
## in bench/perf_budgets.gd: timings fail only above the headroom, the save size and stuck agents
## fail at the budget, and a missing, unreadable or non-budget line fails.

const Gate := preload("res://bench/perf_gate.gd")
const Budgets := preload("res://bench/perf_budgets.gd")
const PerceptionBench := preload("res://bench/perception_bench.gd")
const RingsBench := preload("res://bench/rings_bench.gd")
const PopulationBench := preload("res://bench/population_bench.gd")

const PERCEPTION := "perception bench: 40 actors, 600 frames: average 0.705 ms, p99 1.162 ms (budget 1.0 / 2.0 ms): OK"
const RINGS := "rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min), Godot 4.7.2-stable (official): LIGHT average 0.097 ms p99 0.327 ms (budget 0.3), OFF_SCREEN average 0.228 ms p99 0.518 ms (budget 0.5): OK"
const POPULATION := "population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days, Godot 4.7.2-stable (official), build abc: FULL average 0.185 ms p99 0.476 ms (budget 1.0 / 2.0), LIGHT average 0.100 ms p99 0.302 ms (budget 0.3), OFF_SCREEN average 0.235 ms p99 0.484 ms (budget 0.5), frame average 0.877 ms p99 1.778 ms, memory 5548.6 KiB (20292 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min: OK"


func _lines(perception: String = PERCEPTION, rings: String = RINGS, population: String = POPULATION) -> Dictionary:
	# Each bench file holds its other output too; the gate picks the summary line.
	return {
		"perception": "perception bench: max 3.1 ms, p95 1.0 ms\n" + perception + "\n",
		"rings": "Godot Engine v4.7.2\n" + rings,
		"population": population + "\r\n",
	}


func _failures(result: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in result["report"]:
		if line.begins_with("FAIL"):
			out.append(line)
	return out


func test_runs_within_budget_pass() -> void:
	var result := Gate.judge(_lines(), Budgets.CI_HEADROOM)
	assert_true(result["ok"])
	assert_eq(_failures(result).size(), 0)
	assert_eq((result["report"] as PackedStringArray).size(), Gate.METRICS.size() + 1, "a line per number and the verdict")


func test_noise_over_budget_but_within_the_gate_passes_and_says_so() -> void:
	# 1.075 ms is the slowest perception average a shared runner has given (docs/perf.md).
	var result := Gate.judge(_lines(PERCEPTION.replace("average 0.705", "average 1.075")), Budgets.CI_HEADROOM)
	assert_true(result["ok"])
	assert_true("\n".join(result["report"]).contains("perception average ms: 1.075 (budget 1.000, gate 2.000): over budget, within the gate"))


func test_a_timing_over_the_gate_fails() -> void:
	var result := Gate.judge(_lines(PERCEPTION, RINGS, POPULATION.replace("FULL average 0.185", "FULL average 2.400")), Budgets.CI_HEADROOM)
	assert_false(result["ok"])
	assert_eq(_failures(result), PackedStringArray(["FAIL population FULL average ms: 2.400 (budget 1.000, gate 2.000): over the gate"]))


func test_each_timing_is_gated() -> void:
	var cases := [
		["perception", PERCEPTION.replace("p99 1.162", "p99 4.5")],
		["rings", RINGS.replace("LIGHT average 0.097", "LIGHT average 0.7")],
		["rings", RINGS.replace("OFF_SCREEN average 0.228", "OFF_SCREEN average 1.2")],
		["population", POPULATION.replace("p99 0.476", "p99 4.1")],
		["population", POPULATION.replace("LIGHT average 0.100", "LIGHT average 0.61")],
		["population", POPULATION.replace("OFF_SCREEN average 0.235", "OFF_SCREEN average 1.01")],
	]
	for case: Array in cases:
		var lines := _lines()
		lines[case[0]] = case[1]
		var result := Gate.judge(lines, Budgets.CI_HEADROOM)
		assert_false(result["ok"], case[1])
		assert_eq(_failures(result).size(), 1, case[1])


func test_the_save_size_and_stuck_agents_get_no_headroom() -> void:
	var save := Gate.judge(_lines(PERCEPTION, RINGS, POPULATION.replace("save 546 B", "save 2049 B")), Budgets.CI_HEADROOM)
	assert_false(save["ok"])
	assert_eq(_failures(save), PackedStringArray(["FAIL population save B per agent: 2049 (budget 2048, gate 2048): over the gate"]))
	var stuck := Gate.judge(_lines(PERCEPTION, RINGS, POPULATION.replace("stuck spells 0", "stuck spells 1")), Budgets.CI_HEADROOM)
	assert_false(stuck["ok"])
	assert_eq(_failures(stuck).size(), 1)


func test_a_missing_or_crashed_bench_fails() -> void:
	var lines := _lines()
	lines["rings"] = "SCRIPT ERROR: something broke\n"
	var result := Gate.judge(lines, Budgets.CI_HEADROOM)
	assert_false(result["ok"])
	assert_eq(_failures(result), PackedStringArray(["FAIL rings: no summary line from the rings bench (it crashed or printed nothing)"]))
	lines.erase("population")
	assert_eq(_failures(Gate.judge(lines, Budgets.CI_HEADROOM)).size(), 2)


func test_a_bench_run_outside_the_budget_configuration_fails() -> void:
	var result := Gate.judge(_lines(PERCEPTION.replace("40 actors", "20 actors")), Budgets.CI_HEADROOM)
	assert_false(result["ok"])
	assert_eq(_failures(result).size(), 1)
	assert_true(_failures(result)[0].begins_with("FAIL perception: not the budget configuration"))


func test_an_unreadable_number_fails() -> void:
	var result := Gate.judge(_lines(PERCEPTION, RINGS, POPULATION.replace("stuck spells 0", "stuck spells none")), Budgets.CI_HEADROOM)
	assert_false(result["ok"])
	assert_eq(_failures(result), PackedStringArray(["FAIL population stuck spells: not found in the population bench's line"]))


func test_the_headroom_is_what_separates_noise_from_failure() -> void:
	var noisy := _lines(PERCEPTION.replace("average 0.705", "average 1.075"))
	assert_true(Gate.judge(noisy, 2.0)["ok"])
	assert_false(Gate.judge(noisy, 1.0)["ok"])
	assert_eq(Budgets.CI_HEADROOM, 2.0)


func test_the_benches_take_their_budgets_from_the_one_file() -> void:
	assert_eq(PerceptionBench.BUDGET_AVG_MS, Budgets.PERCEPTION_AVG_MS)
	assert_eq(PerceptionBench.BUDGET_P99_MS, Budgets.PERCEPTION_P99_MS)
	assert_eq(RingsBench.BUDGET_LIGHT_MS, Budgets.LIGHT_AVG_MS)
	assert_eq(RingsBench.BUDGET_OFFSCREEN_MS, Budgets.OFFSCREEN_AVG_MS)
	assert_eq(PopulationBench.BUDGET_FULL_MS, Budgets.FULL_AVG_MS)
	assert_eq(PopulationBench.BUDGET_FULL_P99_MS, Budgets.FULL_P99_MS)
	assert_eq(PopulationBench.BUDGET_LIGHT_MS, Budgets.LIGHT_AVG_MS)
	assert_eq(PopulationBench.BUDGET_OFFSCREEN_MS, Budgets.OFFSCREEN_AVG_MS)
	assert_eq(PopulationBench.BUDGET_SAVE_BYTES, Budgets.SAVE_BYTES_PER_AGENT)


func test_the_ratified_budgets() -> void:
	assert_eq([Budgets.PERCEPTION_AVG_MS, Budgets.PERCEPTION_P99_MS, Budgets.FULL_AVG_MS, Budgets.FULL_P99_MS,
		Budgets.LIGHT_AVG_MS, Budgets.OFFSCREEN_AVG_MS, Budgets.SAVE_BYTES_PER_AGENT],
		[1.0, 2.0, 1.0, 2.0, 0.3, 0.5, 2048])
