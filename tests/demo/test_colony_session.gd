# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony's full session, 15 days long and headless, with every optional module plus social and
## jobs: it replays a pinned timeline, the stuck watch stays clean, each module leaves its own trace,
## and the 15 days still hold with each module left out in turn and with all of them out.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440
const DAYS := 15
## The timeline of the seed-1 session with every module on. A change to the demo or the modules it
## uses changes it; update it only for a change that is meant.
const GOLDEN_HASH := "0e34fde1bf5a2bbc1540ad795e064f56df085a5979431a98924c948597fcc60f"
## Each module and the timeline kinds that show it at work.
const TRACES: Dictionary = {
	Colony.NEEDS_MOOD: ["thought", "state"],
	Colony.SOCIAL: ["talk"],
	Colony.PERCEPTION: ["notice"],
	Colony.JOBS: ["job"],
	Colony.SKILLS: ["skill"],
	Colony.CAREERS: ["career"],
	Colony.ENVIRONMENT: ["room"],
	Colony.ASPIRATIONS: ["want"],
	Colony.AMBITIONS: ["ambition"],
	Colony.ROMANCE: ["romance"],
	Colony.LIFE_STAGES: ["stage"],
	Colony.HEALTH: ["health"],
	Colony.DIRECTOR: ["director", "effect"],
}


func _session(modules: Array[StringName] = Colony.SESSION_MODULES, world_seed: int = 1) -> RefCounted:
	var run := Colony.session(world_seed, modules)
	run.run(DAYS * DAY)
	return run


# Turn-ups of [param id] for [param activity].
static func _attended(run: RefCounted, id: StringName, activity: StringName) -> int:
	return run.timeline.of(&"attend", id).filter(func(e: Dictionary) -> bool: return e["payload"]["activity"] == String(activity)).size()


# The everyday life holds: nobody stuck, needs in hand, rest every night, field work every day for
# every settler old enough.
func _assert_good_days(run: RefCounted, label: String, child_gated: bool) -> void:
	assert_eq(run.timeline.of(&"stuck"), [], "%s: the stuck watch stays clean" % label)
	for id: StringName in Colony.SETTLERS:
		for need: StringName in run.needs_of(id).ids():
			assert_lte(run.dire_minutes(id, need), 60, "%s: %s keeps %s in hand" % [label, id, need])
		assert_eq(_attended(run, id, Colony.REST), DAYS, "%s: %s rests every night" % [label, id])
		var farms := 0 if child_gated and id == Colony.SETTLER_D else DAYS
		assert_eq(_attended(run, id, Colony.FARM), farms, "%s: %s works the field %d days" % [label, id, farms])


func test_fifteen_days_replay_the_pinned_timeline_with_a_clean_stuck_watch() -> void:
	var first := _session()
	var second := _session()
	assert_eq(first.timeline.hash(), second.timeline.hash())
	assert_eq(first.timeline.hash(), GOLDEN_HASH, "the pinned fifteen days")
	assert_eq(first.stuck.spells(), [] as Array[Dictionary], "no stuck spell at all")
	_assert_good_days(first, "all modules", true)


func test_every_module_leaves_a_trace() -> void:
	var run := _session()
	for module: StringName in Colony.SESSION_MODULES:
		for kind: String in TRACES[module]:
			assert_gt(run.timeline.of(StringName(kind)).size(), 0, "%s leaves %s on the timeline" % [module, kind])
	assert_eq(run.timeline.of(&"health", Colony.SETTLER_C).size(), 2, "the illness comes and goes")
	assert_eq(run.timeline.of(&"ambition")[0]["payload"]["ambition"], "get_promoted")
	assert_eq(run.timeline.of(&"career").size(), 2, "a review each working week")


func test_the_days_hold_with_each_module_left_out_and_with_all_out() -> void:
	var sets: Array = []
	for left_out: StringName in Colony.SESSION_MODULES:
		sets.append([left_out, Colony.SESSION_MODULES.filter(func(m: StringName) -> bool: return m != left_out)])
	sets.append([&"all", []])
	for pair: Array in sets:
		var on: Array[StringName] = []
		on.assign(pair[1])
		var run := _session(on)
		_assert_good_days(run, "without %s" % pair[0], on.has(Colony.LIFE_STAGES))
		for module: StringName in Colony.SESSION_MODULES:
			if on.has(module):
				continue
			for kind: String in TRACES[module]:
				assert_eq(run.timeline.of(StringName(kind)), [], "without %s: no %s" % [module, kind])
