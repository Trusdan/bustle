# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The soak tools: the stuck watch's rule (legitimate long activity against standing still), the
## timeline's thought entries with their reasons and values, and a short soak of both demos with no
## stuck agent and the same hash on a replay. The full 30-day soak is bench/soak.gd, run nightly.

const StuckWatch := preload("res://demo/harness/demo_stuck_watch.gd")
const Soak := preload("res://bench/soak.gd")
const Colony := preload("res://demo/colony/colony.gd")
const STEP := 10


func test_a_long_legitimate_activity_is_never_stuck() -> void:
	var watch := StuckWatch.new()
	for minute: int in range(0, 8 * 60, STEP):
		assert_true(watch.observe(&"a", minute, STEP, {"goal": &"sleep", "legit": true}).is_empty())
	assert_false(watch.is_stuck(&"a"), "eight hours asleep")
	assert_eq(watch.longest_still(&"a"), 0)


func test_standing_still_past_the_bound_is_stuck_and_progress_clears_it() -> void:
	var watch := StuckWatch.new()
	var changes: Array[Dictionary] = []
	for minute: int in range(0, 3 * 60, STEP):
		var change := watch.observe(&"a", minute, STEP, {"goal": &"wait", "position": Vector3(0.3, 0, 0)})
		if not change.is_empty():
			changes.append(change)
	assert_true(watch.is_stuck(&"a"), "three hours on one goal, within the epsilon, nothing consumed")
	assert_eq(changes, [{"event": "stuck", "reason": "still", "since": 0}] as Array[Dictionary],
		"once, just past the two-hour bound")
	assert_gt(watch.longest_still(&"a"), watch.bound_minutes)
	var moved := watch.observe(&"a", 180, STEP, {"goal": &"wait", "position": Vector3(2, 0, 0)})
	assert_eq(moved, {"event": "unstuck", "reason": "still", "minutes": 180}, "moving more than the epsilon is progress")
	assert_eq(watch.spells(), [{"agent": &"a", "since": 0, "reason": "still", "minutes": 180}] as Array[Dictionary])


func test_each_kind_of_progress_resets_the_run() -> void:
	var cases := {
		"consumed": {"consumed": true},
		"goal": {"goal": &"other"},
		"step": {"step": 1},
		"place": {"place": &"elsewhere"},
		"hop": {"hop_pending": true},
	}
	for name: String in cases:
		var watch := StuckWatch.new()
		watch.observe(&"a", 0, 100, {"goal": &"wait", "place": &"here"})
		var seen := {"goal": &"wait", "place": &"here"}
		seen.merge(cases[name], true)
		watch.observe(&"a", 100, 100, seen)
		watch.observe(&"a", 200, 100, seen)
		assert_false(watch.is_stuck(&"a"), "%s counts as progress" % name)


func test_a_failure_loop_or_an_overdue_state_is_stuck_at_once() -> void:
	var watch := StuckWatch.new()
	for minute: int in [0, 10]:
		watch.observe(&"a", minute, STEP, {"goal": &"fetch", "failed": true, "legit": true})
	assert_false(watch.is_stuck(&"a"), "two failures aren't a loop")
	var change := watch.observe(&"a", 20, STEP, {"goal": &"fetch", "failed": true, "legit": true})
	assert_eq(change["reason"], "fail_loop", "the third in a row is, even while busy")
	var other := StuckWatch.new()
	assert_eq(other.observe(&"b", 0, STEP, {"legit": true, "state_overdue": true})["reason"], "state_overdue")


func test_the_bound_and_epsilon_are_settings() -> void:
	var watch := StuckWatch.new()
	watch.bound_minutes = 30
	watch.move_epsilon = 5.0
	for minute: int in range(0, 50, STEP):
		watch.observe(&"a", minute, STEP, {"goal": &"wait", "position": Vector3(minute / 10.0, 0, 0)})
	assert_true(watch.is_stuck(&"a"), "under five metres in forty minutes, with a thirty-minute bound")


func test_a_use_counts_as_busy_only_inside_its_expected_time() -> void:
	var house: RefCounted = preload("res://demo/house/house.gd").build(1)
	var id: StringName = house.agent_ids()[0]
	while house.using_of(id) != &"stove" and house.now < 1440:
		house.step()
	assert_eq(house.using_of(id), &"stove", "it goes to cook")
	assert_true(house.using_on_time(id), "a 30-minute use, just begun")
	house.use_minutes[&"stove"] = 0
	house.step()
	house.step()
	assert_eq(house.using_of(id), &"stove", "still at it")
	assert_false(house.using_on_time(id), "but past the time it should take, so it no longer counts as busy")


func test_the_timeline_logs_each_thought_with_its_reason_and_value() -> void:
	var colony := Colony.build(1)
	colony.run(3 * 1440)
	var thoughts := colony.timeline.of(&"thought")
	var added := thoughts.filter(func(e: Dictionary) -> bool: return e["payload"]["phase"] == "add")
	var ended := thoughts.filter(func(e: Dictionary) -> bool: return e["payload"]["phase"] == "end")
	assert_gt(added.size(), 20)
	assert_gt(ended.size(), 10, "expiries and dropped held thoughts are logged too")
	for entry: Dictionary in added:
		var payload: Dictionary = entry["payload"]
		assert_true(payload["value"] is float, str(payload))
		assert_false(String(payload["reason"].get("kind", "")).is_empty(), "every thought lists its reason: %s" % payload)
	var tired := added.filter(func(e: Dictionary) -> bool: return e["payload"]["thought"] == "tired")
	assert_false(tired.is_empty(), "a long day makes them tired")
	assert_eq(tired[0]["payload"]["reason"]["need"], "sleep", "a need thought names its need")
	assert_gte(float(tired[0]["payload"]["reason"]["pressure"]), 0.75, "and how hard it pressed")
	assert_eq(tired[0]["payload"]["value"], -6.0)
	var snap := added.filter(func(e: Dictionary) -> bool: return e["payload"]["thought"] == "bitter_weather")
	assert_eq(snap.size(), 4, "the cold snap's thought, once per settler")
	assert_eq(snap[0]["payload"]["reason"], {"kind": "event", "event": "cold_snap"})
	for id: StringName in colony.agent_ids():
		for reason: Dictionary in colony.mood_of(id).reasons():
			assert_false((reason["reason"] as Dictionary).is_empty(), "%s: %s has its reason" % [id, reason["thought"]])


func test_a_short_soak_of_both_demos_has_no_stuck_agent_and_replays_its_hash() -> void:
	for demo: String in ["house", "colony"]:
		var first := Soak.soak(demo, 1, 2)
		var second := Soak.soak(demo, 1, 2)
		assert_eq(first["days"], 2)
		assert_eq(first["spells"], [], "%s: nobody stuck" % demo)
		assert_eq(second["hash"], first["hash"], "%s: the same seed gives the same hash" % demo)
		assert_gt(int(first["size"]), 50)
		for id: String in first["longest"]:
			assert_lte(int(first["longest"][id]), 120, "%s: %s never stands still for two hours" % [demo, id])
