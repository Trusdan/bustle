# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Stage gates in the brain: a blocked goal or option is never picked, an allowed one runs as
## before, and with no module or the ageless default nothing changes.

const Rules := preload("res://tests/life_stages/test_life_stage_rules.gd")


func _goal(id: StringName, weight: float, tags: Array[StringName] = [], ads: bool = false) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.PERSONAL
	goal.base_weight = weight
	goal.tags = tags
	goal.uses_advertisements = ads
	return goal


func _brain(stages: BustleLifeStagePort, id: StringName = &"x") -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(_goal(&"labour", 3.0))
	library.goals.append(_goal(&"errand", 2.5, [&"labour"]))
	library.goals.append(_goal(&"play", 1.0))
	library.goals.append(_goal(&"eat", 4.0, [], true))
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(id, library, config, 3)
	brain.life_stages = stages
	return brain


func _senses(now: int) -> BustleSenses:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	senses.inputs[&"need.food"] = 0.0
	senses.advertisements.append(BustleAdvertisement.new(&"knife", {&"food": 1.0}, {}, [&"sharp"]))
	senses.advertisements.append(BustleAdvertisement.new(&"bread", {&"food": 0.5}))
	return senses


func _picks(brain: BustleBrain, ticks: int, hungry: bool = false) -> Array[String]:
	var out: Array[String] = []
	for i: int in ticks:
		var senses := _senses(i * 10)
		senses.inputs[&"need.food"] = 0.9 if hungry else 0.0
		var intent := brain.tick(1.0, senses)
		out.append("%s/%s" % [intent.goal_id, intent.option_id])
	return out


func _aged(days: float) -> BustleLifeStages:
	var module := BustleLifeStages.new(Rules.three())
	module.set_age(&"x", days)
	return module


func test_a_blocked_goal_is_never_picked() -> void:
	var picks := _picks(_brain(_aged(10.0)), 40)
	assert_false(picks.has("labour/"), "blocked by its id")
	assert_false(picks.has("errand/"), "blocked by its tag")
	assert_true(picks.has("play/"), "an allowed goal still runs")
	var gated := _brain(_aged(10.0))
	gated.tick(1.0, _senses(0))
	var labour: Array = gated.last_candidates.filter(func(c: BustleCandidate) -> bool: return c.goal_id == &"labour")
	assert_false(labour[0].eligible)
	assert_eq(labour[0].reasons[-1], {"kind": &"stage_gate", "stage": &"young"})


func test_a_blocked_option_is_never_picked() -> void:
	var picks := _picks(_brain(_aged(10.0)), 40, true)
	assert_false(picks.has("eat/knife"), "the sharp option is blocked")
	assert_true(picks.has("eat/bread"), "the allowed option still runs")
	var grown := _picks(_brain(_aged(2000.0)), 40, true)
	assert_true(grown.has("eat/knife"), "a later stage without the gate takes it")


func test_once_past_the_gate_the_goal_runs() -> void:
	var module := _aged(10.0)
	var brain := _brain(module)
	assert_eq(_picks(brain, 3)[-1], "play/")
	module.set_age(&"x", 1600.0)
	assert_eq(_picks(brain, 3)[-1], "labour/")
	module.set_age(&"x", 10.0)
	assert_eq(_picks(brain, 1)[0], "play/", "a running goal its stage now blocks is dropped at once")


func test_no_module_the_default_port_or_no_age_change_nothing() -> void:
	var plain := _picks(_brain(null), 40) + _picks(_brain(null), 40, true)
	assert_eq(_picks(_brain(BustleLifeStagePort.new()), 40) + _picks(_brain(BustleLifeStagePort.new()), 40, true), plain)
	assert_eq(_picks(_brain(_aged(10.0), &"someone_else"), 40) + _picks(_brain(_aged(10.0), &"someone_else"), 40, true), plain)
	var reference := _brain(null)
	var defaulted := _brain(BustleLifeStagePort.new())
	reference.tick(1.0, _senses(0))
	defaulted.tick(1.0, _senses(0))
	for i: int in reference.last_candidates.size():
		assert_eq(defaulted.last_candidates[i].eligible, reference.last_candidates[i].eligible)
		assert_eq(defaulted.last_candidates[i].reasons, reference.last_candidates[i].reasons)
	assert_eq(BustleLifeStagePort.new().stage_of(&"x"), &"")
	assert_true(BustleLifeStagePort.new().allows_goal(&"x", [&"labour"]))
	assert_true(BustleLifeStagePort.new().allows_affordance(&"x", [&"sharp"]))
