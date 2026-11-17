# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## BustleStuckWatch, the addon's stuck watch. The first five tests mirror the demo stuck watch's
## tests in tests/demo/test_soak.gd against the addon class; the rest cover reading an agent's
## state, the hooks and the off-screen case. No random rolls anywhere.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")
const DemoStuckWatch := preload("res://demo/harness/demo_stuck_watch.gd")
const DemoHarness := preload("res://demo/harness/demo_harness.gd")
const STEP := 10


func before_each() -> void:
	_Warn.reset()


func after_each() -> void:
	_Warn.reset()


## An agent named [param id] on [param ring], doing [param goal], with its brain's step at 0.
static func _agent(id: StringName, ring: int, goal: StringName = &"wait") -> BustleNpcState:
	var state := BustleNpcState.new()
	state.id = id
	state.area = &"square"
	state.sim_ring = ring
	state.brain = BustleBrain.new(id)
	_think(state, goal)
	return state


## Gives [param state]'s brain a new intent for [param goal], failed when [param failed].
static func _think(state: BustleNpcState, goal: StringName, failed: bool = false) -> void:
	var intent := BustleIntent.new()
	intent.goal_id = goal
	if failed:
		intent.failure = {"reason": "blocked"}
	state.brain.last_intent = intent


## [param hours] game hours of an OFF_SCREEN [param state] on one goal, watched every [constant STEP]
## minutes. The rings keep it caught up: its last update moves on every [param interval] minutes.
static func _offscreen_hours(watch: BustleStuckWatch, state: BustleNpcState, hours: int, interval: int = 60) -> void:
	for minute: int in range(0, hours * 60, STEP):
		if minute % interval == 0:
			state.last_update_minute = minute
		watch.observe_agent(state, minute, STEP)


# Mirrored from tests/demo/test_soak.gd, against BustleStuckWatch.

func test_a_long_legitimate_activity_is_never_stuck() -> void:
	var watch := BustleStuckWatch.new()
	for minute: int in range(0, 8 * 60, STEP):
		assert_true(watch.observe(&"a", minute, STEP, {"goal": &"sleep", "legit": true}).is_empty())
	assert_false(watch.is_stuck(&"a"), "eight hours asleep")
	assert_eq(watch.longest_still(&"a"), 0)


func test_standing_still_past_the_bound_is_stuck_and_progress_clears_it() -> void:
	var watch := BustleStuckWatch.new()
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
		var watch := BustleStuckWatch.new()
		watch.observe(&"a", 0, 100, {"goal": &"wait", "place": &"here"})
		var seen := {"goal": &"wait", "place": &"here"}
		seen.merge(cases[name], true)
		watch.observe(&"a", 100, 100, seen)
		watch.observe(&"a", 200, 100, seen)
		assert_false(watch.is_stuck(&"a"), "%s counts as progress" % name)


func test_a_failure_loop_or_an_overdue_state_is_stuck_at_once() -> void:
	var watch := BustleStuckWatch.new()
	for minute: int in [0, 10]:
		watch.observe(&"a", minute, STEP, {"goal": &"fetch", "failed": true, "legit": true})
	assert_false(watch.is_stuck(&"a"), "two failures aren't a loop")
	var change := watch.observe(&"a", 20, STEP, {"goal": &"fetch", "failed": true, "legit": true})
	assert_eq(change["reason"], "fail_loop", "the third in a row is, even while busy")
	var other := BustleStuckWatch.new()
	assert_eq(other.observe(&"b", 0, STEP, {"legit": true, "state_overdue": true})["reason"], "state_overdue")


func test_the_bound_and_epsilon_are_settings() -> void:
	var watch := BustleStuckWatch.new()
	watch.bound_minutes = 30
	watch.move_epsilon = 5.0
	for minute: int in range(0, 50, STEP):
		watch.observe(&"a", minute, STEP, {"goal": &"wait", "position": Vector3(minute / 10.0, 0, 0)})
	assert_true(watch.is_stuck(&"a"), "under five metres in forty minutes, with a thirty-minute bound")


# New: the defaults, the demo's watch, and reading an agent's state.

func test_the_defaults_are_the_rules_and_the_demo_watch_is_the_addon_class() -> void:
	var watch := BustleStuckWatch.new()
	assert_eq(watch.bound_minutes, 120)
	assert_eq(watch.move_epsilon, 0.5)
	assert_eq(watch.fail_loop, 3)
	assert_false(watch.check_offscreen_progress)
	assert_eq(watch.ring_config.offscreen_interval_game_minutes, 60)
	assert_true(DemoStuckWatch.new() is BustleStuckWatch)
	assert_true(DemoHarness.new().stuck is BustleStuckWatch, "the demo harness watches with the addon class")


func test_the_fail_loop_is_a_setting() -> void:
	var watch := BustleStuckWatch.new()
	watch.fail_loop = 5
	for minute: int in range(0, 40, STEP):
		watch.observe(&"a", minute, STEP, {"goal": &"fetch", "failed": true})
	assert_false(watch.is_stuck(&"a"), "four failures, with a loop of five")
	assert_eq(watch.observe(&"a", 40, STEP, {"goal": &"fetch", "failed": true})["reason"], "fail_loop")


func test_observe_agent_reads_the_goal_step_and_position_of_an_agent_in_view() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.FULL)
	state.position = Vector3(1, 0, 0)
	state.has_position = true
	for minute: int in range(0, 3 * 60, STEP):
		watch.observe_agent(state, minute, STEP)
	assert_true(watch.is_stuck(&"a"), "one goal and one spot for three hours")
	state.position = Vector3(4, 0, 0)
	assert_eq(watch.observe_agent(state, 180, STEP)["event"], "unstuck", "its position moved")
	for minute: int in range(190, 400, STEP):
		_think(state, &"walk" if minute % 20 == 0 else &"wait")
		watch.observe_agent(state, minute, STEP)
	assert_false(watch.is_stuck(&"a"), "a new goal every step is progress")


func test_observe_agent_counts_one_failed_think_once() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.FULL)
	_think(state, &"fetch", true)
	for minute: int in range(0, 60, STEP):
		watch.observe_agent(state, minute, STEP, {"legit": true})
	assert_false(watch.is_stuck(&"a"), "one failure, watched six times, isn't a loop")
	for minute: int in [60, 70, 80]:
		_think(state, &"fetch", true)
		watch.observe_agent(state, minute, STEP, {"legit": true})
	assert_true(watch.is_stuck(&"a"), "three failed thinks in a row are")
	assert_eq(watch.spells()[0]["reason"], "fail_loop")


## Gives [param state] a new intent for [param goal] (failed when [param failed]) and watches it
## [param times] times, [constant STEP] minutes apart from [param minute]. Returns the next minute.
static func _think_and_watch(watch: BustleStuckWatch, state: BustleNpcState, goal: StringName, failed: bool,
		times: int, minute: int) -> int:
	_think(state, goal, failed)
	for i: int in times:
		watch.observe_agent(state, minute, STEP, {"legit": true})
		minute += STEP
	return minute


func test_a_failed_think_watched_many_times_still_makes_a_loop_on_the_third() -> void:
	for times: int in [2, 3, 5]:
		var watch := BustleStuckWatch.new()
		var state := _agent(&"a", BustleSimRings.Ring.FULL)
		var minute := 0
		for think: int in 2:
			minute = _think_and_watch(watch, state, &"fetch", true, times, minute)
		assert_false(watch.is_stuck(&"a"), "two failed thinks, each watched %d times" % times)
		minute = _think_and_watch(watch, state, &"fetch", true, times, minute)
		assert_true(watch.is_stuck(&"a"), "the third failed think in a row, each watched %d times" % times)
		assert_eq(watch.spells().size(), 1, "one spell (%d)" % times)
		assert_eq(watch.spells()[0]["reason"], "fail_loop")


func test_a_successful_think_between_failures_still_breaks_the_run() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.FULL)
	var minute := 0
	for failed: bool in [true, true, false, true, true]:
		minute = _think_and_watch(watch, state, &"fetch", failed, 2, minute)
	assert_false(watch.is_stuck(&"a"), "two failures, a success, then two more: no three in a row")
	_think_and_watch(watch, state, &"fetch", true, 2, minute)
	assert_true(watch.is_stuck(&"a"), "the third failure since the success is a loop")
	assert_eq(watch.spells()[0]["reason"], "fail_loop")


func test_observe_agent_uses_what_the_caller_saw_as_given() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.LIGHT)
	for minute: int in range(0, 4 * 60, STEP):
		watch.observe_agent(state, minute, STEP, {"legit": true})
	assert_false(watch.is_stuck(&"a"), "the caller says it is in a long activity")
	assert_eq(watch.observe_agent(state, 240, STEP, {"state_overdue": true})["reason"], "state_overdue")


func test_the_travel_hook_makes_travel_legitimate_while_it_closes_in() -> void:
	var watch := BustleStuckWatch.new()
	var asked: Array = []
	var closing := {"a": true}
	watch.travel_hook = func(agent: StringName, now: int) -> bool:
		asked.append([agent, now])
		return bool(closing[String(agent)])
	var state := _agent(&"a", BustleSimRings.Ring.LIGHT)
	for minute: int in range(0, 4 * 60, STEP):
		watch.observe_agent(state, minute, STEP)
	assert_false(watch.is_stuck(&"a"), "four hours on the road, still closing in")
	assert_eq(asked[0], [&"a", 0], "asked with the agent and the minute")
	closing["a"] = false
	for minute: int in range(240, 400, STEP):
		watch.observe_agent(state, minute, STEP)
	assert_true(watch.is_stuck(&"a"), "no longer closing in, and nothing else changed")


func test_a_hook_of_the_wrong_type_warns_once_and_counts_as_no() -> void:
	var watch := BustleStuckWatch.new()
	watch.travel_hook = func(_agent: StringName, _now: int) -> Variant: return "yes"
	watch.offscreen_progress_hook = func(_agent: StringName, _now: int) -> Variant: return null
	watch.check_offscreen_progress = true
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, state, 3)
	assert_true(_Warn.has_warned("BustleStuckWatch.travel_hook.wrong_type"))
	assert_true(_Warn.has_warned("BustleStuckWatch.offscreen_progress_hook.wrong_type"))
	assert_true(watch.is_stuck(&"a"), "neither answer counted")


func test_a_null_agent_is_refused_with_a_warning() -> void:
	var watch := BustleStuckWatch.new()
	assert_eq(watch.observe_agent(null, 0, STEP), {})
	assert_true(_Warn.has_warned("BustleStuckWatch.no_agent"))
	assert_eq(watch.spells(), [] as Array[Dictionary], "nothing was recorded")


# New: the off-screen case.

func test_off_screen_catch_up_still_advancing_is_legitimate_by_default() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, state, 6)
	assert_false(watch.is_stuck(&"a"), "six hours on one goal, but the rings keep it caught up")
	assert_eq(watch.longest_still(&"a"), 0)


func test_off_screen_catch_up_that_stopped_advancing_is_not_legitimate() -> void:
	var watch := BustleStuckWatch.new()
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	state.last_update_minute = 0
	for minute: int in range(0, 4 * 60, STEP):
		watch.observe_agent(state, minute, STEP)
	assert_true(watch.is_stuck(&"a"), "its last update stayed at minute 0")
	var never := _agent(&"b", BustleSimRings.Ring.OFF_SCREEN)
	for minute: int in range(0, 4 * 60, STEP):
		watch.observe_agent(never, minute, STEP)
	assert_true(watch.is_stuck(&"b"), "never updated at all")


func test_checked_off_screen_agents_need_goal_or_step_progress() -> void:
	var watch := BustleStuckWatch.new()
	watch.check_offscreen_progress = true
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, state, 3)
	assert_true(watch.is_stuck(&"a"), "caught up all along, but on one goal and step at one place")
	assert_eq(watch.spells()[0]["reason"], "still")
	var moving := _agent(&"b", BustleSimRings.Ring.OFF_SCREEN)
	for minute: int in range(0, 6 * 60, STEP):
		if minute % 60 == 0:
			moving.last_update_minute = minute
			moving.brain.runner.step_index = (minute / 60) % 2
		watch.observe_agent(moving, minute, STEP)
	assert_false(watch.is_stuck(&"b"), "a new step each think is progress")


func test_checked_off_screen_agents_progress_through_place_hop_and_the_hook() -> void:
	var cases := {"place": {}, "hop": {"hop_pending": true}, "hook": {}}
	for name: String in cases:
		var watch := BustleStuckWatch.new()
		watch.check_offscreen_progress = true
		var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
		if name == "hook":
			watch.offscreen_progress_hook = func(_agent: StringName, now: int) -> bool: return now % 60 == 0
		for minute: int in range(0, 6 * 60, STEP):
			state.last_update_minute = minute - minute % 60
			if name == "place":
				state.area = &"square" if (minute / 60) % 2 == 0 else &"market"
			watch.observe_agent(state, minute, STEP, cases[name])
		assert_false(watch.is_stuck(&"a"), "%s counts as off-screen progress" % name)


func test_the_progress_hook_is_asked_only_off_screen() -> void:
	var watch := BustleStuckWatch.new()
	var asked: Array[StringName] = []
	watch.offscreen_progress_hook = func(agent: StringName, _now: int) -> bool:
		asked.append(agent)
		return true
	watch.observe_agent(_agent(&"in_view", BustleSimRings.Ring.FULL), 0, STEP)
	watch.observe_agent(_agent(&"away", BustleSimRings.Ring.OFF_SCREEN), 0, STEP)
	assert_eq(asked, [&"away"] as Array[StringName])


func test_the_off_screen_interval_is_read_from_the_ring_config() -> void:
	var config := BustleSimRingConfig.new()
	config.offscreen_interval_game_minutes = 240
	var watch := BustleStuckWatch.new()
	watch.ring_config = config
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, state, 12, 240)
	assert_false(watch.is_stuck(&"a"), "a think every four hours is still catching up at a 240-minute interval")
	var other := BustleStuckWatch.new()
	var same := _agent(&"b", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(other, same, 12, 240)
	assert_true(other.is_stuck(&"b"), "at the default 60-minute interval it has fallen behind")
	config.offscreen_interval_game_minutes = 30
	var late := _agent(&"c", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, late, 4, 240)
	assert_true(watch.is_stuck(&"c"), "a change to the config applies at once")


func test_a_null_ring_config_warns_once_and_uses_the_default_interval() -> void:
	var watch := BustleStuckWatch.new()
	watch.ring_config = null
	var state := _agent(&"a", BustleSimRings.Ring.OFF_SCREEN)
	_offscreen_hours(watch, state, 6)
	assert_true(_Warn.has_warned("BustleStuckWatch.no_ring_config"))
	assert_false(watch.is_stuck(&"a"), "the default 60-minute interval applies")


func test_the_same_observations_give_the_same_spells() -> void:
	var runs: Array = []
	for run: int in 2:
		var watch := BustleStuckWatch.new()
		watch.check_offscreen_progress = true
		for id: StringName in [&"a", &"b", &"c"]:
			_offscreen_hours(watch, _agent(id, BustleSimRings.Ring.OFF_SCREEN), 4)
		runs.append(watch.spells())
	assert_eq(runs[0].size(), 3)
	assert_eq(runs[1], runs[0])
