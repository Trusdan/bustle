# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The colony with life stages over a week, ages moving on each step: the child still never works
## the field, a death stops a settler, a table with no gates changes nothing else, and the same seed
## replays the same.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440


func _run(world_seed: int, rules: BustleLifeStageRules = Colony.life_stage_rules(), days: int = 7) -> RefCounted:
	var run := Colony.build(world_seed, Colony.MODULES, true, null, null, null, rules)
	run.age_each_step = true
	run.run(days * DAY)
	return run


func test_a_week_of_aging_keeps_the_gates_and_replays_the_same() -> void:
	var run := _run(1)
	assert_eq(run.life_stages.now(), run.now - run.step_minutes, "aged to the last step")
	assert_almost_eq(run.life_stages.age_years(Colony.SETTLER_D), 10.0 + 7.0 / 360.0, 0.01)
	var child_field: Array = run.timeline.of(&"choice", Colony.SETTLER_D).filter(func(e: Dictionary) -> bool:
		return e["payload"]["goal"] == String(Colony.FARM) or e["payload"]["option"] == "field")
	assert_eq(child_field, [], "the child never picks field work")
	assert_gt(run.timeline.of(&"choice", Colony.SETTLER_A).filter(func(e: Dictionary) -> bool:
		return e["payload"]["goal"] == String(Colony.FARM)).size(), 0)
	var again := _run(1)
	assert_eq(run.timeline.hash(), again.timeline.hash())
	assert_eq(run.life_stages.export_state(), again.life_stages.export_state())


func test_a_death_stops_the_settler() -> void:
	var run := Colony.build(2, Colony.MODULES, true, null, null, null, Colony.life_stage_rules())
	run.age_each_step = true
	run.run(DAY)
	assert_eq(run.life_stages.note_death(Colony.SETTLER_B, "illness"), "")
	var at: int = run.now
	run.run(2 * DAY)
	assert_eq(run.timeline.of(&"died").size(), 1)
	assert_eq(run.timeline.of(&"died")[0]["payload"], {"cause": "illness"})
	var after: Array = run.timeline.of(&"choice", Colony.SETTLER_B).filter(func(e: Dictionary) -> bool: return e["t"] >= at)
	assert_eq(after, [], "a dead settler isn't stepped")
	assert_gt(run.timeline.of(&"choice", Colony.SETTLER_A).filter(func(e: Dictionary) -> bool: return e["t"] >= at).size(), 0)
	assert_eq(run.life_stages.living_ids().size(), 3)


func test_a_table_with_no_gates_changes_nothing_else() -> void:
	var rules := Colony.life_stage_rules()
	for stage: BustleLifeStageDef in rules.stages:
		stage.blocked_goal_tags = []
		stage.blocked_affordance_tags = []
	var gated := _run(1, rules, 3)
	var plain := Colony.build(1)
	plain.run(3 * DAY)
	var lines: PackedStringArray = []
	for line: String in gated.timeline.lines():
		if line.split("|")[2] != "stage":
			lines.append(line)
	assert_eq(lines, plain.timeline.lines())
