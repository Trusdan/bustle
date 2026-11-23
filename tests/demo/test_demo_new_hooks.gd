# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The opt-in demo of the hooks added after 1.0 (demo/hooks/demo_hooks.gd, the house session's
## NEW_HOOKS module). Off by default: the week, its pinned hash and the run's wiring are as before.
## On: each hook is called and leaves its "hook" entries on the timeline, the same every run.

const House := preload("res://demo/house/house.gd")
const DemoHooks := preload("res://demo/hooks/demo_hooks.gd")
const WEEK := 7 * 1440
## The house week's pinned hash (as in test_house_session.gd), which the opt-in must leave alone.
const HOUSE_WEEK_HASH := "930276aafed2ccd0ae8e4b3d21d8181cef830d5dd47b89b7a77f8ab84696f614"
## The week with the opt-in on.
const OPT_IN_WEEK_HASH := "486422e6eee5a08aaa670d74190da3613aeee0e0edfde2c0cc41289367960386"

var _on: RefCounted


func before_all() -> void:
	_on = _week(_with_hooks(House.MODULES))


func after_all() -> void:
	_on = null


func _with_hooks(base: Array[StringName]) -> Array[StringName]:
	var modules: Array[StringName] = base.duplicate()
	modules.append(House.NEW_HOOKS)
	return modules


func _week(modules: Array[StringName]) -> RefCounted:
	var run: RefCounted = House.session(1, modules)
	run.run(WEEK)
	return run


# The payloads of the opt-in's entries for [param hook], oldest first, each with its minute as "t".
func _hooks(run: RefCounted, hook: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in run.timeline.of(DemoHooks.KIND):
		if entry["payload"]["hook"] == hook:
			var payload: Dictionary = entry["payload"].duplicate()
			payload["t"] = entry["t"]
			payload["agent"] = entry["agent"]
			out.append(payload)
	return out


func test_off_by_default_the_week_is_unchanged() -> void:
	assert_false(House.MODULES.has(House.NEW_HOOKS), "not one of the default modules")
	var off: RefCounted = _week(House.MODULES)
	assert_eq(off.timeline.hash(), HOUSE_WEEK_HASH, "the pinned week")
	assert_eq(off.timeline.of(DemoHooks.KIND), [] as Array[Dictionary], "no hook entries")
	assert_false(off.has_meta(&"new_hooks"))
	assert_null(off.environment, "no rooms")
	assert_eq(off.aspiration_config.max_points, -1, "no cap")
	assert_eq(off.agent_hooks, [] as Array[Callable])
	assert_gt(off.aspirations_of(House.RESIDENT_A).points(), DemoHooks.ASPIRATION_CAP, "points grow past the demo cap")


func test_the_opt_in_is_the_same_every_run() -> void:
	assert_true(_on.has_meta(&"new_hooks"))
	assert_eq(_on.timeline.hash(), OPT_IN_WEEK_HASH, "the pinned opt-in week")
	assert_eq(_week(_with_hooks(House.MODULES)).timeline.hash(), _on.timeline.hash())


func test_aspiration_points_stop_at_the_cap() -> void:
	assert_eq(_on.aspiration_config.max_points, DemoHooks.ASPIRATION_CAP)
	for id: StringName in _on.agent_ids():
		assert_eq(_on.aspirations_of(id).points(), DemoHooks.ASPIRATION_CAP, "%s earns up to the cap" % id)


func test_a_resident_at_home_is_in_the_house_room() -> void:
	var rooms: Array[Dictionary] = _hooks(_on, "room")
	assert_gt(rooms.size(), 0)
	var indoors := rooms.filter(func(r: Dictionary) -> bool: return r["indoors"] == 1)
	var outdoors := rooms.filter(func(r: Dictionary) -> bool: return r["indoors"] == 0)
	assert_gt(indoors.size(), 0)
	assert_gt(outdoors.size(), 0, "away at work, out of the room")
	for room: Dictionary in indoors:
		assert_eq(room["room"], "house_room")
		assert_eq(room["beauty"], 60, "the demo room's score")
	for room: Dictionary in outdoors:
		assert_eq(room["room"], "")
	var hooks: RefCounted = _on.get_meta(&"new_hooks")
	assert_eq(hooks.rooms.scores(&"cellar"), DemoHooks.DemoRooms.scores_of(&"cellar"), "the demo set is installed")


func test_a_career_is_judged_by_period_and_its_window_reset() -> void:
	var reviews: Array[Dictionary] = _hooks(_on, "career_review")
	assert_eq(reviews.size(), 1, "one review, after the busy period's 2 working days")
	assert_eq(reviews[0]["at"], 2 * 1440)
	var periods: Array = _hooks(_on, "window_period").map(func(p: Dictionary) -> String: return p["period"])
	assert_eq(periods, ["busy", "", "busy", "busy", "", ""], "pinned in the busy period, then reset")
	var resets: Array[Dictionary] = _hooks(_on, "reset_window")
	assert_eq(resets.size(), 1)
	assert_eq(resets[0]["ok"], 1)
	assert_eq(resets[0]["period"], "", "the pin is dropped")
	assert_eq(resets[0]["t"], 5 * 1440, "after the closed days")
	var hooks: RefCounted = _on.get_meta(&"new_hooks")
	assert_eq(hooks.careers.window_period(House.RESIDENT_A), &"")
	assert_eq(hooks.careers.rank_of(House.RESIDENT_A), &"hand", "a reset changes no rank")


func test_a_stolen_item_is_traced_after_it_is_sold_on() -> void:
	var theft: Array[Dictionary] = _hooks(_on, "theft")
	assert_eq(theft.size(), 1)
	assert_eq(theft[0]["deed"], 1, "nobody saw it")
	var traced: Array[Dictionary] = _hooks(_on, "deed_of_item")
	assert_eq(traced.size(), 1)
	assert_eq(traced[0]["agent"], String(House.RESIDENT_B), "now held by the buyer")
	assert_eq(traced[0]["deed"], 1, "still points to the deed")
	assert_eq(traced[0]["stolen_goods_of_thief"], 0, "the thief no longer holds it")
	assert_eq(traced[0]["stolen_goods_held_by"], 1, "the buyer does")


func test_work_with_a_capacity_minimum_is_refused_then_released() -> void:
	var refusals: Array[Dictionary] = _hooks(_on, "refusal")
	assert_eq(refusals.size(), 1)
	assert_eq(refusals[0]["reason"], "capacity:moving")
	assert_eq(_hooks(_on, "claim")[0]["ok"], 1, "the fit resident claims it")
	assert_eq(_hooks(_on, "release_unfit")[0]["released"], 1, "and lets go once below the minimum")
	var hooks: RefCounted = _on.get_meta(&"new_hooks")
	assert_eq(hooks.board.claimed_of(House.RESIDENT_A), &"")


func test_a_bystander_fetches_the_healer_by_the_fetch_help_rule() -> void:
	var started: Array[Dictionary] = _hooks(_on, "fetch_healer")
	assert_eq(started.size(), 1)
	assert_eq(started[0]["agent"], String(House.RESIDENT_A))
	assert_eq(started[0]["patient"], String(House.RESIDENT_B))
	var summoned: Array[Dictionary] = _hooks(_on, "summoned")
	assert_eq(summoned.size(), 1)
	assert_eq(summoned[0]["agent"], "neighbour")
	assert_eq(summoned[0]["steps"], 4, "walked 40 m in steps of 10 until within reach")
	assert_eq(_hooks(_on, "recovered")[0]["summons"], "", "the summons ends when the patient recovers")


func test_the_opt_in_runs_without_the_other_modules() -> void:
	var run: RefCounted = House.session(1, [House.NEW_HOOKS] as Array[StringName])
	run.run(WEEK)
	assert_null(run.aspiration_config, "no aspirations, so no cap")
	for hook: String in ["room", "career_review", "reset_window", "deed_of_item", "refusal", "release_unfit", "summoned"]:
		assert_gt(_hooks(run, hook).size(), 0, hook)
