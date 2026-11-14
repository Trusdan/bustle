# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## A downed agent picks no work and doesn't travel, through the brain's gate; up again, it does.
## Without a gate the brain is unchanged.

const FakeHealth := preload("res://tests/health/fake_health_port.gd")

var _port: FakeHealth
var _health: BustleHealthBehaviour


func before_each() -> void:
	var ports := BustlePorts.new()
	_port = FakeHealth.new()
	ports.health = _port
	_health = BustleHealthBehaviour.new(null, ports)


func _goal(id: StringName, weight: float, tags: Array[StringName] = [], ads: bool = false) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.PERSONAL
	goal.base_weight = weight
	goal.tags = tags
	goal.uses_advertisements = ads
	return goal


func _brain(gated: bool) -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(_goal(&"work", 5.0))
	library.goals.append(_goal(&"visit_town", 4.0, [&"travel"]))
	library.goals.append(_goal(&"use", 3.0, [], true))
	library.goals.append(_goal(&"rest", 1.0))
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(&"a", library, config, 3)
	if gated:
		brain.gate = _health.allows
	return brain


func _picks(brain: BustleBrain, ticks: int) -> Array[String]:
	var out: Array[String] = []
	for i: int in ticks:
		var senses := BustleSenses.new()
		senses.now_minutes = i * 10
		senses.inputs[&"need.food"] = 0.9
		senses.advertisements.append(BustleAdvertisement.new(&"loom", {&"food": 1.0}, {}, [&"work"]))
		senses.advertisements.append(BustleAdvertisement.new(&"bench", {&"food": 0.2}))
		var intent := brain.tick(1.0, senses)
		out.append("%s/%s" % [intent.goal_id, intent.option_id])
	return out


func test_a_downed_agent_picks_no_work_and_does_not_travel() -> void:
	_port.downed = [&"a"]
	var brain := _brain(true)
	var picks := _picks(brain, 30)
	for pick: String in picks:
		assert_false(pick.begins_with("work/") or pick.begins_with("visit_town/") or pick == "use/loom", pick)
	assert_true(picks.has("use/bench") or picks.has("rest/"), "it still does what isn't blocked")
	var work: Array = brain.last_candidates.filter(func(c: BustleCandidate) -> bool: return c.goal_id == &"work")
	assert_false(work[0].eligible)
	assert_eq(work[0].reasons[-1], {"kind": &"gate"})


func test_back_up_it_works_again() -> void:
	_port.downed = [&"a"]
	var brain := _brain(true)
	_picks(brain, 3)
	_port.downed = []
	assert_eq(_picks(brain, 1)[0], "work/")


func test_without_a_gate_or_when_up_nothing_changes() -> void:
	var plain := _picks(_brain(false), 20)
	assert_eq(_picks(_brain(true), 20), plain, "an agent who is up is never gated")
	var reference := _brain(false)
	var gated := _brain(true)
	_picks(reference, 1)
	_picks(gated, 1)
	for i: int in reference.last_candidates.size():
		assert_eq(gated.last_candidates[i].reasons, reference.last_candidates[i].reasons)


func test_the_downed_blocks_are_configurable() -> void:
	var config := BustleHealthConfig.defaults()
	config.downed_blocks = [&"rest"]
	var health := BustleHealthBehaviour.new(config, _health.ports)
	_port.downed = [&"a"]
	assert_true(health.allows(&"a", [&"work"] as Array[StringName], [] as Array[StringName]))
	assert_false(health.allows(&"a", [&"rest"] as Array[StringName], [] as Array[StringName]))
	assert_false(health.allows(&"a", [&"use"] as Array[StringName], [&"rest"] as Array[StringName]))
	assert_true(health.allows(&"b", [&"rest"] as Array[StringName], [] as Array[StringName]), "only the downed")
