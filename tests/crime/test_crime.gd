# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Guarded theft: driven by need and personality, never by chance and never capped; only with an
## unseen, unprotected item of someone else's that eases the need; only while crime is allowed;
## only moving existing items; never with an intent to kill; and run in the GUARDED band.

const CRIME_DIR := "res://addons/bustle/core/crime/"

var _society: BustleSociety
var _crime: BustleCrime
var _people: Dictionary[StringName, BustlePersonality] = {}
var _needs: Dictionary[StringName, BustleNeedSet] = {}


func before_each() -> void:
	_society = BustleSociety.new(3)
	_society.register_archetype(&"villager", _library())
	_crime = BustleCrime.new(_society)
	_people = {}
	_needs = {}
	_crime.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_agent(&"drifter", &"market", 0.9, {&"honesty": 20.0, &"greed": 70.0, &"boldness": 60.0})
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})


func after_each() -> void:
	ProjectSettings.set_setting(BustleCrimeConfig.SETTING, null)


func test_a_desperate_dishonest_agent_steals_what_it_needs() -> void:
	var plan := _crime.consider(&"drifter", 100)
	assert_eq(plan["item"], "loaf")
	assert_almost_eq(float(plan["score"]), 0.9 + 0.6 + 0.2 + 0.1, 1e-6, "pressure + honesty 20 (×−2) + greed 70 + boldness 60")
	var inputs: Dictionary[StringName, float] = {}
	_crime.fill_inputs(&"drifter", inputs)
	assert_eq(inputs, {BustleCrime.INPUT: 1.0} as Dictionary[StringName, float])
	var events := []
	_crime.theft.connect(func(t: StringName, o: StringName, i: StringName, c: Dictionary) -> void: events.append([t, o, i, c]))
	var runner := _runner()
	runner.start(_sequence(), &"drifter", 101)
	assert_eq(runner.tick(0.1, 101), BustleSequenceRunner.State.SUCCEEDED)
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"drifter", "the loaf changed hands")
	assert_eq(events, [[&"drifter", &"baker", &"loaf", {"place": "market", "need": "food", "pressure": 0.9, "score": plan["score"], "at": 101}]], "one neutral theft event with what drove it")
	_crime.fill_inputs(&"drifter", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float], "the target is gone")
	assert_eq(_crime.consider(&"drifter", 102), {}, "nothing else of anyone's eases its hunger here")


func test_personality_and_need_decide_with_no_cap() -> void:
	_agent(&"saint", &"square", 1.0, {&"honesty": 90.0})
	_agent(&"plain", &"well", 0.9, {})
	_agent(&"plain_starving", &"mill", 1.0, {})
	_agent(&"rogue_fed", &"yard", 0.3, {&"honesty": 0.0, &"greed": 100.0, &"boldness": 100.0})
	for place: StringName in [&"square", &"well", &"mill", &"yard"]:
		_society.ports.property.register(StringName("loaf_" + place), &"baker", place, {&"food": 0.5})
	assert_eq(_crime.consider(&"saint", 0), {}, "honesty holds even the starving back (1.0 − 0.8 < 1)")
	assert_eq(_crime.consider(&"plain", 0), {}, "an ordinary agent who is very hungry doesn't (0.9 < 1)")
	assert_eq(_crime.consider(&"plain_starving", 0)["item"], "loaf_mill", "but one who is starving does (1.0)")
	assert_eq(_crime.consider(&"rogue_fed", 0), {}, "no need, no theft, however dishonest")
	var takers := 0
	for i in 20:
		var id := StringName("hungry_%d" % i)
		var place := StringName("stall_%d" % i)
		_agent(id, place, 0.9, {&"honesty": 20.0, &"greed": 70.0, &"boldness": 60.0})
		_society.ports.property.register(StringName("bun_%d" % i), &"baker", place, {&"food": 0.5})
		if not _crime.consider(id, 0).is_empty():
			takers += 1
	assert_eq(takers, 20, "nothing caps how many: every agent whose circumstances add up steals")


func test_every_circumstance_must_hold() -> void:
	assert_false(_crime.consider(&"drifter", 0).is_empty(), "the baseline steals")
	var checks: Array[Callable] = [
		func() -> void: _society.ports.property.set_protected(&"loaf", true),
		func() -> void: _agent(&"onlooker", &"market", 0.0, {}),
		func() -> void: _crime.is_locked = func(_id: StringName) -> bool: return true,
		func() -> void: _crime.exempt = [&"drifter"],
		func() -> void: _crime.enabled = false,
		func() -> void: ProjectSettings.set_setting(BustleCrimeConfig.SETTING, false),
		func() -> void: _society.get_agent(&"drifter").area = &"field",
		func() -> void: _society.ports.property.transfer(&"loaf", &"baker", &"drifter"),
	]
	var names := ["protected", "seen", "held to a task", "exempt", "switched off", "developer setting off", "elsewhere", "its own"]
	for i in checks.size():
		before_each()
		checks[i].call()
		assert_eq(_crime.consider(&"drifter", 0), {}, "no theft when the item is %s" % names[i])
	before_each()
	_society.ports.property.register(&"rope", &"baker", &"market", {&"rest": 1.0})
	_society.ports.property.set_protected(&"loaf", true)
	assert_eq(_crime.consider(&"drifter", 0), {}, "nor when nothing eases the need")


func test_theft_only_moves_existing_items_and_never_means_harm() -> void:
	_society.ports.property.register(&"jar", &"cooper", &"market", {&"food": 0.2})
	var before := _society.ports.property.export_state()
	_crime.consider(&"drifter", 0)
	assert_true(_crime.steal(&"drifter", 1)["ok"])
	var after := _society.ports.property.export_state()
	assert_eq((after["items"] as Array).size(), (before["items"] as Array).size(), "no item made or lost")
	for i in (before["items"] as Array).size():
		var a: Dictionary = before["items"][i]
		var b: Dictionary = after["items"][i]
		a.erase("owner_id")
		b.erase("owner_id")
		assert_eq(b, a, "only the owner changed")
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"drifter", "the bigger relief was taken")
	assert_eq(_society.ports.combat.status(&"drifter"), BustleCombatPort.Status.NONE, "no fight engaged")
	for file: String in DirAccess.get_files_at(CRIME_DIR):
		if file.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(CRIME_DIR + file)
			for word: String in ["RandomNumberGenerator", "randf", "randi", "KILL", "lethal", "engage("]:
				assert_false(text.contains(word), "%s mentions %s" % [file, word])
	assert_eq(_crime.steal(&"drifter", 2), {"ok": false, "reason": &"no_target"})


func test_guards_are_checked_again_at_the_moment_of_taking() -> void:
	_crime.consider(&"drifter", 0)
	_agent(&"onlooker", &"market", 0.0, {})
	assert_eq(_crime.steal(&"drifter", 5), {"ok": false, "reason": &"guards_failed"}, "someone came along")
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"baker")
	assert_eq(_crime.consider(&"drifter", 6), {})
	for i in 10:
		assert_eq(_crime.consider(&"drifter", 6), {}, "the same answer every time")


func test_a_brain_steals_in_the_guarded_band_then_goes_back_to_work() -> void:
	var library := _library()
	library.goals.append_array(BustleCrime.goal_defs())
	var brain := BustleBrain.new(&"drifter", library, BustleScoringConfig.new(), 3)
	brain.runner.share_handlers_with(_runner())
	assert_eq(BustleBands.name_of(BustleBands.GUARDED), "GUARDED")
	assert_true(BustleBands.GUARDED > BustleBands.DUTY and BustleBands.GUARDED < BustleBands.URGENT)
	_crime.consider(&"drifter", 0)
	assert_eq(_tick(brain, 0).goal_id, &"steal", "a guarded theft outranks duty")
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"drifter")
	_crime.consider(&"drifter", 1)
	assert_eq(_tick(brain, 1).goal_id, &"work", "with nothing left to take, back to work")


func test_the_property_register_saves_and_refuses_bad_data() -> void:
	var port := _society.ports.property
	assert_false(port.register(&"loaf", &"cooper", &"market"), "ids are unique")
	assert_false(port.register(&"", &"cooper", &"market"))
	assert_false(port.register(&"nail", &"", &"market"))
	assert_false(port.register(&"nail", &"cooper", &"market", {&"food": INF}))
	port.register(&"relic", &"cooper", &"market", {}, true)
	assert_false(port.transfer(&"relic", &"cooper", &"drifter"), "protected things never move")
	assert_false(port.transfer(&"loaf", &"cooper", &"drifter"), "only the owner's things move from the owner")
	assert_false(port.transfer(&"ghost", &"baker", &"drifter"), "nothing that doesn't exist")
	var saved: Variant = JSON.parse_string(JSON.stringify(port.export_state()))
	var other := BustlePropertyPort.new()
	assert_true(other.import_state(saved))
	assert_eq(other.export_state(), port.export_state())
	for bad: Variant in [null, {}, {"items": [{"id": "", "owner_id": "a", "place": "", "relieves": {}, "protected": false}]},
			{"items": [{"id": "a", "owner_id": "b", "place": "", "relieves": [], "protected": false}]},
			{"items": [{"id": "a", "owner_id": "b", "place": "", "relieves": {}, "protected": "no"}]}]:
		assert_false(other.import_state(bad), str(bad))
	assert_true(other.is_protected(&"relic"), "refused data changes nothing")


func _agent(id: StringName, area: StringName, hunger: float, sliders: Dictionary) -> void:
	var state := _society.add_agent(id, &"villager")
	state.area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	_people[id] = p


func _library() -> BustleGoalLibrary:
	var work := BustleGoalDef.new()
	work.id = &"work"
	work.band = BustleBands.DUTY
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 60}
	work.sequence = BustleActionSequence.new()
	work.sequence.steps.append(step)
	var library := BustleGoalLibrary.new()
	library.goals = [work] as Array[BustleGoalDef]
	return library


func _sequence() -> BustleActionSequence:
	return BustleCrime.goal_defs()[0].sequence


func _runner() -> BustleSequenceRunner:
	var runner := BustleSequenceRunner.new()
	runner.register(&"steal", BustleStealAction.new(_crime))
	return runner


func _tick(brain: BustleBrain, now: int) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	_crime.fill_inputs(&"drifter", senses.inputs)
	return brain.tick(0.1, senses)
