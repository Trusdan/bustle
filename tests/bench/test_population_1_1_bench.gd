# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The opt-in 1.1 load on the population bench (bench/population_1_1_bench.gd), on a small town:
## each hook added after 1.0 is called, the agents choose as they do on the plain bench, the same
## seed gives the same run, and the summary line is one the performance gate reads. The bench
## itself (40 / 40 / 200, timed) runs through tools/perf_bench.sh --load 1.1; the default bench is
## untouched.

const Load := preload("res://bench/population_1_1_bench.gd")
const Population := preload("res://bench/population_bench.gd")
const Gate := preload("res://bench/perf_gate.gd")


func test_the_town_is_the_population_bench_town() -> void:
	var town := Load.build(4, 3, 20, 1)
	assert_eq((town["rings"] as BustleSimRings).counts(), {"FULL": 4, "LIGHT": 3, "OFF_SCREEN": 20})
	assert_false(Population.build(4, 3, 20, 1).has("load"), "the plain bench carries no load")


func test_the_agents_choose_as_on_the_plain_bench() -> void:
	var plain := Population.stuck_pass(Population.build(4, 4, 20, 1), 1)
	var loaded := Population.stuck_pass(Load.build(4, 4, 20, 1), 1)
	assert_eq(loaded["spells"], [], "nobody stuck")
	assert_eq(loaded["hash"], plain["hash"], "the same choices: the load adds cost, not behaviour")


func test_each_hook_is_called() -> void:
	var town := Load.build(4, 4, 20, 1)
	Population.time_hour(town, 1200)
	var load: RefCounted = town["load"]
	var society: BustleSociety = town["society"]
	var ids := society.agent_ids()
	var aims := {}
	for id: StringName in ids:
		aims[(load.ambitions[id] as BustleAmbitions).active().get("id", "")] = true
	assert_true(aims.has("learn_trade"), "the trade filler and learn_trade")
	assert_true(aims.has("open_business"), "open_business on the host's fact")
	assert_eq((load.aspirations[ids[0]] as BustleAspirations).points(), Load.ASPIRATION_CAP, "points stop at the cap")
	load.senses(ids[0], BustleSimRings.Ring.FULL, 2 * 1440)
	var career: Dictionary = (load.careers as BustleCareers).export_state()[String(ids[0])]
	assert_eq(career["closed"], 1, "days 0 and 1 closed")
	assert_eq(career["window"], [], "reviewed after the busy period's 2 days, not the rank's 3")
	assert_false((load.watch as BustleCrimeWatch).stolen_goods_held_by(ids[2]).is_empty(), "goods traced after they're sold on")
	assert_false((load.watch as BustleCrimeWatch).deed_of_item(load.items[ids[0]]).is_empty())
	var refused := 0
	for id: StringName in ids:
		if (load.board as BustleJobBoard).refusal(BustleJobSeeker.new(id), load.jobs[0]) == &"capacity:moving":
			refused += 1
	assert_gt(refused, 0, "the agents who can barely move are refused the hauling")
	var goals: Array = (society.get_agent(ids[0]) as BustleNpcState).brain.library.goals.map(
		func(goal: BustleGoalDef) -> StringName: return goal.id)
	for goal: StringName in [&"seek_care", &"rest_sick", &"fetch_healer"]:
		assert_true(goals.has(goal), "%s is in the library" % goal)
	assert_gt(Load.save_bytes(town), Population.save_bytes(town), "the save adds the 1.1 modules'")


func test_the_same_seed_gives_the_same_load() -> void:
	var first := Load.build(4, 4, 20, 1)
	var second := Load.build(4, 4, 20, 1)
	Population.time_hour(first, 600)
	Population.time_hour(second, 600)
	assert_eq(Load.save_bytes(second), Load.save_bytes(first))
	assert_eq((second["load"].careers as BustleCareers).export_state(), (first["load"].careers as BustleCareers).export_state())


func test_the_gate_reads_the_summary_line() -> void:
	var perf := {"counts": {"FULL": 40, "LIGHT": 40, "OFF_SCREEN": 200}, "minutes": 60, "full_avg": 0.5, "full_p99": 1.5,
		"light_avg": 0.25, "light_p99": 0.9, "off_avg": 0.2, "off_p99": 0.5, "frame_avg": 1.5, "frame_p99": 3.0}
	var line := Load.summary(perf, 1, 7200, 1, 1024, 280, 280 * 900, {"spells": [], "longest": 0})
	assert_true(line.contains(", 1.1 load, "), "labelled")
	assert_true(line.ends_with(": OK"))
	var result := Gate.judge({
		"perception": "perception bench: 40 actors, 600 frames: average 0.5 ms, p99 1.0 ms (budget 1.0 / 2.0 ms): OK",
		"rings": "rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames (120 real s, 60 game min): LIGHT average 0.1 ms p99 0.3 ms (budget 0.3), OFF_SCREEN average 0.2 ms p99 0.4 ms (budget 0.5): OK",
		"population": line}, 2.0)
	assert_true(result["ok"], "the budget configuration, read by the gate")
	var report := "\n".join(result["report"])
	assert_string_contains(report, "ok population FULL average ms: 0.500")
	assert_string_contains(report, "ok population LIGHT average ms: 0.250")
	assert_string_contains(report, "ok population save B per agent: 900")
	perf["light_avg"] = 0.4
	assert_true(Load.summary(perf, 1, 7200, 1, 1024, 280, 280 * 900, {"spells": [], "longest": 0}).ends_with(": OVER BUDGET"))
