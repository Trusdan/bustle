# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Whose personality the watch's judge uses: its own personality_of when set; otherwise the
## crime's personality_of, so a host wires personalities once; with neither, neutral sliders, as
## before. A judge used on its own, outside a watch, doesn't borrow the crime's hook.

var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _needs: Dictionary[StringName, BustleNeedSet] = {}
var _decided: Array = []
var _honest := BustlePersonality.new()
var _crooked := BustlePersonality.new()


func before_each() -> void:
	_honest.set_slider(&"honesty", 100.0)
	_crooked.set_slider(&"honesty", 0.0)
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_crime = BustleCrime.new(_society)
	_needs = {}
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_watch = BustleCrimeWatch.new(_crime)
	_watch.instant = true
	_decided = []
	_watch.decided.connect(func(agent: StringName, outcome: StringName, _r: Dictionary) -> void: _decided.append([agent, outcome]))
	_agent(&"drifter", &"market", 1.0)
	_agent(&"baker", &"bakery", 0.0)
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


# The drifter steals the baker's loaf unseen; the baker finds the deed and decides.
func _owner_decides() -> StringName:
	assert_false(_crime.consider(&"drifter", 10).is_empty())
	assert_true(_crime.steal(&"drifter", 10)["ok"])
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	assert_eq(_decided.size(), 1)
	return _decided[0][1] if not _decided.is_empty() else &""


# What a judge with [param personality] for the baker decides about the deed, called directly.
func _direct(personality: BustlePersonality) -> Dictionary:
	var judge := BustleWitnessJudge.new(_society)
	if personality != null:
		judge.personality_of = func(_id: StringName) -> BustlePersonality: return personality
	return judge.decide(&"baker", {"thief": "", "owner_id": "baker", "can_confront": false, "gossip_to": ""})


func test_the_cases_differ() -> void:
	# The other tests rest on these three judging differently.
	assert_eq(_direct(_honest)["outcome"], BustleWitnessJudge.REPORT)
	assert_ne(_direct(null)["outcome"], BustleWitnessJudge.REPORT, "neutral sliders don't report")
	assert_ne(_direct(_honest)["scores"], _direct(_crooked)["scores"])


func test_with_only_the_crime_hook_the_judge_uses_it() -> void:
	_crime.personality_of = func(id: StringName) -> BustlePersonality: return _honest if id == &"baker" else null
	assert_false(_watch.judge.personality_of.is_valid(), "the judge's own hook is unset")
	assert_eq(_owner_decides(), BustleWitnessJudge.REPORT, "the honest owner reports, as the crime hook says")
	assert_eq(_watch.judge.decide(&"baker", {"thief": "", "owner_id": "baker"})["scores"], _direct(_honest)["scores"],
		"the same scores as a judge given that personality")


func test_an_explicit_judge_hook_still_wins() -> void:
	# Only the baker's: the crime's hook also decides who steals, and an honest drifter wouldn't.
	_crime.personality_of = func(id: StringName) -> BustlePersonality: return _honest if id == &"baker" else null
	_watch.judge.personality_of = func(_id: StringName) -> BustlePersonality: return _crooked
	assert_eq(_owner_decides(), _direct(_crooked)["outcome"], "the judge's own hook decides")
	assert_eq(_watch.judge.decide(&"baker", {"thief": "", "owner_id": "baker"})["scores"], _direct(_crooked)["scores"])


func test_with_neither_hook_the_sliders_are_neutral_as_before() -> void:
	assert_eq(_owner_decides(), _direct(null)["outcome"])
	assert_eq(_watch.judge.decide(&"baker", {"thief": "", "owner_id": "baker"})["scores"], _direct(null)["scores"])


func test_a_crime_hook_with_nothing_for_an_agent_leaves_it_neutral() -> void:
	_crime.personality_of = func(_id: StringName) -> BustlePersonality: return null
	assert_eq(_owner_decides(), _direct(null)["outcome"])


func test_a_judge_outside_a_watch_doesnt_borrow_the_crime_hook() -> void:
	_crime.personality_of = func(_id: StringName) -> BustlePersonality: return _honest
	var judge := BustleWitnessJudge.new(_society)
	assert_eq(judge.decide(&"baker", {"thief": "", "owner_id": "baker"})["scores"], _direct(null)["scores"])


func _agent(id: StringName, area: StringName, hunger: float) -> void:
	_society.add_agent(id, &"villager").area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
