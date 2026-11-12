# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## A theft by someone who isn't an agent of the society: recorded with BustleCrime.record_theft,
## followed by the crime watch like any other, with nothing moved and steal() unchanged.


var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _thefts: Array = []
var _cases: Array = []


func before_each() -> void:
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	for row: Array in [[&"baker", &"market"], [&"onlooker", &"market"], [&"far", &"well"]]:
		_society.add_agent(row[0], &"villager").area = row[1]
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})
	_crime = BustleCrime.new(_society)
	_watch = BustleCrimeWatch.new(_crime)
	_watch.instant = true
	_thefts = []
	_cases = []
	_crime.theft.connect(func(t: StringName, o: StringName, i: StringName, c: Dictionary) -> void: _thefts.append([t, o, i, c]))
	_watch.should_report = func(agent: StringName, case: Dictionary) -> StringName:
		_cases.append([agent, case["thief"], case["can_confront"]])
		return BustleWitnessJudge.SILENT


func test_a_theft_by_someone_who_isnt_an_agent_is_recorded_with_its_witnesses() -> void:
	assert_null(_society.get_agent(&"p1"), "the thief isn't an agent of the society")
	assert_true(_crime.record_theft(&"p1", &"baker", &"loaf", {"place": "market", "at": 30, "seen_by": 2}))
	assert_eq(_thefts, [[&"p1", &"baker", &"loaf", {"place": &"market", "at": 30, "seen_by": 2}]],
		"the theft signal, with the place and minute in steal()'s types and the host's other keys as given")
	var row := _watch.record(1)
	assert_eq([row["thief"], row["owner_id"], row["item"], row["place"], row["at"]], ["p1", "baker", "loaf", "market", 30])
	assert_eq([row["witnesses"], row["deed"]], [["baker", "onlooker"], false], "the agents there saw it; the one elsewhere didn't")
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"baker", "nothing moved: the host moves the item")
	assert_eq(_cases, [[&"baker", "p1", false], [&"onlooker", "p1", false]], "no one can confront a thief the society can't place")
	assert_eq(_crime.target_of(&"p1"), {}, "and no target was made")


func test_the_host_can_let_witnesses_reach_the_thief() -> void:
	_watch.can_reach = func(agent: StringName, other: StringName) -> bool: return agent == &"onlooker" and other == &"p1"
	assert_true(_crime.record_theft(&"p1", &"baker", &"loaf", {"place": &"market", "at": 30.0}))
	assert_eq(_cases, [[&"baker", "p1", false], [&"onlooker", "p1", true]], "confront is open where the host says it can reach")
	assert_eq(_thefts[0][3], {"place": &"market", "at": 30}, "a whole float minute is an int")


func test_a_theft_nobody_saw_is_a_deed() -> void:
	assert_true(_crime.record_theft(&"p1", &"baker", &"loaf", {"place": "well_road", "at": 5}))
	assert_eq([_watch.record(1)["witnesses"], _watch.record(1)["deed"]], [[], true])
	assert_eq(_watch.open_deeds().size(), 1)


func test_bad_arguments_record_nothing() -> void:
	for args: Array in [
		[&"", &"baker", &"loaf", {"place": "market", "at": 1}],
		[&"p1", &"", &"loaf", {"place": "market", "at": 1}],
		[&"p1", &"baker", &"", {"place": "market", "at": 1}],
		[&"baker", &"baker", &"loaf", {"place": "market", "at": 1}],
		[&"p1", &"baker", &"loaf", {"at": 1}],
		[&"p1", &"baker", &"loaf", {"place": "", "at": 1}],
		[&"p1", &"baker", &"loaf", {"place": "market"}],
		[&"p1", &"baker", &"loaf", {"place": "market", "at": 1.5}],
		[&"p1", &"baker", &"loaf", {"place": "market", "at": "1"}],
		[&"p1", &"baker", &"loaf", {"place": 7, "at": 1}],
	]:
		assert_false(_crime.record_theft(args[0], args[1], args[2], args[3]), str(args))
	assert_eq(_thefts, [], "no signal")
	assert_eq(_watch.records(), [], "no record")


func test_steal_still_needs_a_known_agent_and_moves_the_item() -> void:
	var hungry := BustleNeedSet.new()
	var def := BustleNeedDef.new()
	def.id = &"food"
	def.start = 1.0
	hungry.add_need(def)
	_crime.needs_of = func(_id: StringName) -> BustleNeedSet: return hungry
	_crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	assert_eq(_crime.consider(&"p1", 10), {}, "someone who isn't an agent can't be considered")
	assert_eq(_crime.steal(&"p1", 10), {"ok": false, "reason": &"no_target"}, "or steal")
	_society.add_agent(&"drifter", &"villager").area = &"market"
	assert_false(_crime.consider(&"drifter", 10).is_empty())
	assert_true(_crime.steal(&"drifter", 10)["ok"], "an agent still steals as before")
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"drifter", "moving the item")
	assert_eq(_thefts.size(), 1)
