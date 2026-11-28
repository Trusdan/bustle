# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The median of several perf bench runs (bench/perf_median.gd), as the Windows reference run
## reports it: the same numbers and budgets as the gate, the median with the lowest and highest,
## and each median against its budget.

const Median := preload("res://bench/perf_median.gd")

const PERCEPTION := "perception bench: 40 actors, 600 frames: average %s ms, p99 1.200 ms (budget 1.0 / 2.0 ms): OK"
const RINGS := "rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min), Godot 4.7.2-stable (official): LIGHT average 0.120 ms p99 0.400 ms (budget 0.3), OFF_SCREEN average 0.200 ms p99 0.500 ms (budget 0.5): OK"
const POPULATION := "population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames (60 game min), 1 stuck days, Godot 4.7.2-stable (official), build x: FULL average %s ms p99 0.600 ms (budget 1.0 / 2.0), LIGHT average 0.110 ms p99 0.380 ms (budget 0.3), OFF_SCREEN average 0.170 ms p99 0.430 ms (budget 0.5), frame average 0.800 ms p99 2.000 ms, memory 5500.0 KiB (20000 B an agent), save 546 B an agent (budget 2048), stuck spells 0, longest still 0 min: OK"


func _run(perception_avg: String, full_avg: String) -> Dictionary:
	return {"perception": PERCEPTION % perception_avg, "rings": RINGS, "population": POPULATION % full_avg}


func _row(result: Dictionary, label: String) -> Dictionary:
	for row: Dictionary in result["rows"]:
		if row["label"] == label:
			return row
	return {}


func test_the_median_lowest_and_highest_of_five_runs() -> void:
	var runs: Array[Dictionary] = [_run("0.9", "0.2"), _run("0.5", "0.3"), _run("0.7", "0.1"), _run("1.4", "0.2"), _run("0.6", "0.25")]
	var result := Median.summarize(runs)
	assert_true(result["complete"])
	assert_true(result["ok"], "a slow outlier doesn't move the median past the budget")
	var perception := _row(result, "perception average ms")
	assert_almost_eq(float(perception["median"]), 0.7, 1e-9)
	assert_almost_eq(float(perception["min"]), 0.5, 1e-9)
	assert_almost_eq(float(perception["max"]), 1.4, 1e-9)
	assert_eq(perception["budget"], 1.0)
	assert_almost_eq(float(_row(result, "population FULL average ms")["median"]), 0.2, 1e-9)
	assert_eq(_row(result, "population save B per agent")["median"], 546.0)
	assert_eq(result["rows"].size(), 10, "every number the gate judges")


func test_an_even_number_of_runs_averages_the_middle_two() -> void:
	var result := Median.summarize([_run("0.4", "0.2"), _run("0.6", "0.2")] as Array[Dictionary])
	assert_almost_eq(float(_row(result, "perception average ms")["median"]), 0.5, 1e-9)


func test_a_median_over_budget_is_reported() -> void:
	var runs: Array[Dictionary] = [_run("1.2", "0.2"), _run("1.1", "0.2"), _run("0.9", "0.2")]
	var result := Median.summarize(runs)
	assert_true(result["complete"])
	assert_false(result["ok"])
	assert_false(_row(result, "perception average ms")["within"])
	var table := Median.table("Default load", result)
	assert_string_contains(table, "### Default load: median of 3 runs")
	assert_string_contains(table, "| perception average ms | 1.100 | 0.900 | 1.200 | 1.000 | **over** |")
	assert_string_contains(table, "| population save B per agent | 546 | 546 | 546 | 2048 | within |")
	assert_string_contains(table, "**A median is over budget.**")


func test_a_missing_line_makes_it_incomplete() -> void:
	var broken := _run("0.5", "0.2")
	broken["population"] = "population bench: 4 FULL, 4 LIGHT, 20 OFF_SCREEN, seed 1, 600 frames: FULL average 0.2 ms"
	var result := Median.summarize([_run("0.5", "0.2"), broken] as Array[Dictionary])
	assert_false(result["complete"], "a line not at the budget configuration doesn't count")
	assert_false(result["ok"])
	assert_eq(_row(result, "population FULL average ms")["values"].size(), 1, "only the good run's number")
	assert_string_contains(Median.table("Default load", result), "**Incomplete:**")
	assert_false(Median.summarize([] as Array[Dictionary])["complete"], "no runs at all")
