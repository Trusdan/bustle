# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The house's full session, a week long and headless, with every module the house uses: it replays
## a pinned timeline, the stuck watch stays clean, each module leaves its own trace, and the week
## still holds with each module left out in turn and with all of them out.

const House := preload("res://demo/house/house.gd")
const DAY := 1440
const WEEK := 7 * DAY
const EATS: Array[String] = ["stove", "table"]
## The timeline of the seed-1 week with every module on. A change to the demo or the modules it uses
## changes it; update it only for a change that is meant.
const GOLDEN_HASH := "930276aafed2ccd0ae8e4b3d21d8181cef830d5dd47b89b7a77f8ab84696f614"
## Each module and the timeline kinds that show it at work.
const TRACES: Dictionary = {
	House.NEEDS_MOOD: ["thought", "state"],
	House.SOCIAL: ["talk"],
	House.JOBS: ["job"],
	House.ASPIRATIONS: ["want", "points"],
	House.ROMANCE: ["romance"],
	House.LIFE_STAGES: ["stage"],
	House.DIRECTOR: ["director", "effect"],
}


func _week(modules: Array[StringName] = House.MODULES, world_seed: int = 1) -> RefCounted:
	var run := House.session(world_seed, modules)
	run.run(WEEK)
	return run


# The objects [param id] finished using on [param day].
static func _used(run: RefCounted, id: StringName, day: int) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in run.timeline.of(&"used", id):
		if int(entry["t"]) / DAY == day:
			out.append(entry["payload"]["object"])
	return out


# The week's everyday life holds: needs in hand, meals and sleep every day, work every day, nobody stuck.
func _assert_a_good_week(run: RefCounted, label: String) -> void:
	assert_eq(run.timeline.of(&"stuck"), [], "%s: the stuck watch stays clean" % label)
	for id: StringName in [House.RESIDENT_A, House.RESIDENT_B]:
		for need: StringName in run.needs_of(id).ids():
			assert_lte(run.dire_minutes(id, need), 60, "%s: %s keeps %s in hand" % [label, id, need])
		for day: int in 7:
			var used := _used(run, id, day)
			assert_true(used.any(func(o: String) -> bool: return EATS.has(o)), "%s: %s eats on day %d" % [label, id, day])
			assert_true(used.has("bed"), "%s: %s sleeps on day %d" % [label, id, day])
		assert_eq(run.timeline.of(&"attend", id).size(), 7, "%s: %s goes to work every day" % [label, id])


func test_a_week_replays_the_pinned_timeline_with_a_clean_stuck_watch() -> void:
	var first := _week()
	var second := _week()
	assert_eq(first.timeline.hash(), second.timeline.hash())
	assert_eq(first.timeline.hash(), GOLDEN_HASH, "the pinned week")
	assert_eq(first.stuck.spells(), [] as Array[Dictionary], "no stuck spell at all")
	_assert_a_good_week(first, "all modules")
	assert_ne(_week(House.MODULES, 2).timeline.hash(), first.timeline.hash(), "another seed, another week")


func test_every_module_leaves_a_trace() -> void:
	var run := _week()
	for module: StringName in House.MODULES:
		for kind: String in TRACES[module]:
			assert_gt(run.timeline.of(StringName(kind)).size(), 0, "%s leaves %s on the timeline" % [module, kind])
	assert_eq(run.timeline.of(&"event").size(), 2, "the bad news starts and ends")


func test_the_week_holds_with_each_module_left_out_and_with_all_out() -> void:
	var sets: Array = []
	for left_out: StringName in House.MODULES:
		sets.append([left_out, House.MODULES.filter(func(m: StringName) -> bool: return m != left_out)])
	sets.append([&"all", []])
	for pair: Array in sets:
		var on: Array[StringName] = []
		on.assign(pair[1])
		var run := _week(on)
		_assert_a_good_week(run, "without %s" % pair[0])
		for module: StringName in House.MODULES:
			if on.has(module):
				continue
			for kind: String in TRACES[module]:
				assert_eq(run.timeline.of(StringName(kind)), [], "without %s: no %s" % [module, kind])
