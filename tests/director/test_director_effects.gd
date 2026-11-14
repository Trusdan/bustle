# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## What a fired event does: exactly its declared thoughts, orders and spawn requests, only to the
## targets it names; spawns only through the world port; population and wealth as plain inputs.

const DAY := 1440


class Mood extends RefCounted:
	var got: Array = []

	func add_thought(def: BustleThoughtDef, details: Dictionary) -> bool:
		got.append([def.id, details])
		return true


class World extends BustleWorldPort:
	var areas: Dictionary = {}
	var asked: Array = []
	var make := true

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"elsewhere")

	func request_spawn(kind: StringName, area: StringName, count: int, event: StringName) -> bool:
		asked.append([kind, area, count, event])
		return make


var _moods: Dictionary = {}
var _brains: Dictionary = {}
var _world: World
var _effects: BustleDirectorEffects


func before_each() -> void:
	_moods = {}
	_brains = {}
	for id: StringName in [&"a", &"b", &"c", &"d"]:
		_moods[id] = Mood.new()
		_brains[id] = BustleBrain.new(id)
	var ports := BustlePorts.new()
	_world = World.new()
	_world.areas = {&"a": &"square", &"b": &"square", &"c": &"mill"}
	ports.world = _world
	_effects = BustleDirectorEffects.new(ports)
	_effects.agents = func() -> Array[StringName]: return [&"a", &"b", &"c", &"d"]
	_effects.tags_of = func(id: StringName) -> Array[StringName]: return [&"elder"] if id == &"d" else []
	_effects.mood_of = func(id: StringName) -> Object: return _moods.get(id)
	_effects.brain_of = func(id: StringName) -> BustleBrain: return _brains.get(id)


static func _thought(id: StringName) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = -3.0
	def.duration_hours = 6.0
	return def


static func _sequence() -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 30}
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _event(id: StringName, effects: Array[BustleEventEffect], requires: Array[Dictionary] = []) -> BustleEventDef:
	var def := BustleEventDef.new()
	def.id = id
	def.effects = effects
	def.requires = requires
	def.cooldown_minutes = DAY
	assert_eq(def.validate(), "")
	return def


func test_a_fired_event_applies_exactly_its_effects_to_exactly_its_targets() -> void:
	var by_area := BustleEventEffect.new()
	by_area.thought = _thought(&"uneasy")
	by_area.target_area = &"square"
	var by_tag := BustleEventEffect.new()
	by_tag.kind = BustleEventEffect.ORDER
	by_tag.sequence = _sequence()
	by_tag.target_tag = &"elder"
	by_tag.target_ids = [&"c", &"nobody"]
	var director := BustleDirector.new()
	director.effects = _effects
	director.add_event(_event(&"alarm", [by_area, by_tag]))
	var seen: Array = []
	_effects.applied.connect(func(event: StringName, kind: StringName, target: StringName, what: StringName, done: bool) -> void:
		seen.append([event, kind, target, what, done]))
	assert_eq(director.update(100), &"alarm")
	assert_eq(seen, [[&"alarm", &"thought", &"a", &"uneasy", true], [&"alarm", &"thought", &"b", &"uneasy", true],
		[&"alarm", &"order", &"c", &"alarm.100", true], [&"alarm", &"order", &"d", &"alarm.100", true]])
	assert_eq(_moods[&"a"].got, [[&"uneasy", {"event": "alarm"}]])
	assert_eq(_moods[&"c"].got, [], "outside the area: no thought")
	assert_eq(_moods[&"d"].got, [])
	assert_eq(_brains[&"c"].orders.ids(), [&"alarm.100"] as Array[StringName], "named by id")
	assert_eq(_brains[&"d"].orders.ids(), [&"alarm.100"] as Array[StringName], "named by tag")
	assert_eq(_brains[&"a"].orders.ids(), [] as Array[StringName])
	assert_eq(_world.asked, [], "no spawn it didn't declare")
	assert_eq(director.update(200), &"", "cooling down: nothing more")
	assert_eq(seen.size(), 4)


func test_spawns_go_only_through_the_world_port() -> void:
	var visit := BustleEventEffect.new()
	visit.kind = BustleEventEffect.SPAWN
	visit.spawn_kind = &"visitor"
	visit.spawn_area = &"square"
	visit.count = 2
	var def := _event(&"arrival", [visit])
	assert_eq(_effects.apply(def, 0), [{"event": &"arrival", "kind": &"spawn", "target": &"square", "what": &"visitor", "done": true}])
	assert_eq(_world.asked, [[&"visitor", &"square", 2, &"arrival"]])
	for id: StringName in _moods:
		assert_eq(_moods[id].got, [], "a spawn touches no agent")
	var plain := BustleDirectorEffects.new(BustlePorts.new())
	assert_eq(plain.apply(def, 0)[0]["done"], false, "the default world port makes nothing")
	assert_false(BustleWorldPort.new().request_spawn(&"visitor", &"", 1, &"arrival"))
	_world.make = false
	assert_eq(_effects.apply(def, 0)[0]["done"], false, "the host may refuse")


func test_population_and_wealth_change_eligibility_and_scores() -> void:
	var hire := _event(&"hire", [], [{"input": BustleDirector.INPUT_POPULATION, "at_most": 20}, {"input": BustleDirector.INPUT_WEALTH, "at_least": 50}])
	var fair := _event(&"fair", [])
	fair.score_inputs = {BustleDirector.INPUT_WEALTH: 0.05}
	var director := BustleDirector.new()
	director.add_event(hire)
	director.add_event(fair)
	assert_eq(director.eligible(0, BustleDirector.hooks(30, 80.0), false).map(func(d: BustleEventDef) -> StringName: return d.id), [&"fair"],
		"too many people to hire")
	assert_eq(director.eligible(0, BustleDirector.hooks(10, 20.0), false).map(func(d: BustleEventDef) -> StringName: return d.id), [&"fair"],
		"too little wealth to hire")
	assert_eq(director.eligible(0, BustleDirector.hooks(10, 80.0), false).map(func(d: BustleEventDef) -> StringName: return d.id), [&"fair", &"hire"],
		"wealth lifts the fair's score above the hire's")
	assert_eq(director.eligible(0, BustleDirector.hooks(10, 60.0), false).map(func(d: BustleEventDef) -> StringName: return d.id), [&"fair", &"hire"])
	assert_eq(director.eligible(0, BustleDirector.hooks(10, 50.0), false).map(func(d: BustleEventDef) -> StringName: return d.id), [&"fair", &"hire"])
	assert_eq(director.update(0, BustleDirector.hooks(10, 80.0)), &"fair")
	assert_eq(director.update(10, BustleDirector.hooks(10, 80.0)), &"hire")
	var rules := BustleDirectorRules.new()
	rules.tension_inputs = {BustleDirector.INPUT_POPULATION: 0.01}
	assert_almost_eq(BustleDirector.new(rules).tension(0, BustleDirector.hooks(50, 0.0)), 0.5, 1e-9, "crowds can raise tension")
	var mine := {&"fact.season": 1.0}
	assert_eq(BustleDirector.hooks(3, 7.0, mine), {&"fact.season": 1.0, &"fact.population": 3.0, &"fact.wealth": 7.0})
	assert_eq(mine, {&"fact.season": 1.0}, "the host's inputs are left alone")


func test_bad_effects_are_refused_and_saving_still_round_trips() -> void:
	var cases: Array = [[BustleEventEffect.THOUGHT, "a thought effect needs a valid timed thought"],
		[BustleEventEffect.ORDER, "an order effect needs a sequence"],
		[BustleEventEffect.SPAWN, "a spawn effect needs a kind and a count of at least 1"],
		[&"party", "unknown effect kind 'party'"]]
	for row: Array in cases:
		var effect := BustleEventEffect.new()
		effect.kind = row[0]
		assert_eq(effect.validate(), row[1])
	var untargeted := BustleEventEffect.new()
	untargeted.thought = _thought(&"uneasy")
	assert_eq(untargeted.validate(), "a thought effect needs targets")
	var def := BustleEventDef.new()
	def.id = &"x"
	def.effects = [untargeted]
	assert_false(BustleDirector.new().add_event(def))
	var by_area := BustleEventEffect.new()
	by_area.thought = _thought(&"uneasy")
	by_area.target_area = &"square"
	var first := BustleDirector.new()
	first.effects = _effects
	first.add_event(_event(&"alarm", [by_area]))
	first.update(0)
	var second := BustleDirector.new()
	second.add_event(_event(&"alarm", [by_area]))
	assert_true(second.import_state(first.export_state()))
	assert_eq(second.export_state(), first.export_state())
