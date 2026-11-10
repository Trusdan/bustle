# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Mental states start the moment mood crosses a personality-adjusted line, pick the highest
## score, end on time or when mood recovers, and leave a catharsis thought after a low one. No
## chance, no timer between episodes, no limit shared between agents, and nothing harmful can be
## expressed.

const FILES: Array[String] = ["res://addons/bustle/modules/needs_mood/mental_state.gd",
	"res://addons/bustle/modules/needs_mood/mental_state_def.gd",
	"res://addons/bustle/modules/needs_mood/mental_config.gd"]

var _events: Array = []


func after_each() -> void:
	ProjectSettings.set_setting(BustleMentalConfig.SETTING, null)


func test_bad_thoughts_start_a_state_at_once() -> void:
	var mood := BustleMood.new()
	mood.start(0)
	var state := _state(&"a")
	var gloom := BustleThoughtDef.new()
	gloom.id = &"gloom"
	gloom.value = -40.0
	gloom.duration_hours = 48.0
	mood.add_thought(gloom)
	var entered_at := -1
	var before := mood.mood
	for minute in range(0, 6 * 60, 10):
		mood.advance_to(minute)
		state.update(minute, mood, _person({&"sociability": 10.0}))
		if state.is_active() and entered_at < 0:
			entered_at = minute
			assert_lt(mood.mood, 30.0, "it starts below the line")
			assert_gte(before, 30.0, "and not a step later than it crossed")
		before = mood.mood
	assert_between(entered_at, 1, 6 * 60, "the gloom starts a state within hours, at the step mood crosses 30")
	assert_eq(_events[0].slice(0, 2), [&"a", &"withdraw"], "an unsociable agent withdraws")
	assert_eq(_events[0][2], {"id": "withdraw", "kind": "low", "tier": "minor", "since": entered_at, "until": entered_at + 8 * 60})


func test_the_highest_score_wins() -> void:
	assert_eq(_choose(20.0, {}), &"withdraw", "all scores 0: the quietest wins the tie")
	assert_eq(_choose(20.0, {&"temper": 100.0}), &"sulk", "hot-tempered with nobody nearby: lashing out is skipped")
	assert_eq(_choose(20.0, {&"temper": 100.0}, {"target": "rival", "target_opinion": 10.0}), &"lash_out", "1.0 + 0.4 for the dislike, over sulking's 0.5")
	assert_eq(_choose(20.0, {&"temper": 75.0}, {"target": "rival", "target_opinion": 90.0}), &"sulk", "someone it likes: 0.5 − 0.4 = 0.1 < 0.25")
	assert_eq(_choose(20.0, {&"greed": 100.0}), &"withdraw", "greedy but knows no indulgence")
	assert_eq(_choose(20.0, {&"greed": 100.0}, {"indulgence": true}), &"binge")
	assert_eq(_choose(20.0, {&"curiosity": 100.0}), &"wander")
	assert_eq(_choose(50.0, {&"temper": 100.0}), &"", "above the line, nothing")
	assert_eq(_choose(85.0, {}), &"high_spirits")
	assert_eq(_choose(95.0, {}), &"high_spirits", "inspiration needs a match")
	assert_eq(_choose(95.0, {&"diligence": 60.0}), &"inspired", "inspiration beats high spirits")
	assert_eq(_choose(95.0, {}, {}, {&"mental.inspired": 1.0}), &"inspired", "or a trait that opts in")
	assert_eq(_choose(35.0, {}, {}, {&"mental.break_threshold": 10.0}), &"withdraw", "a trait can raise the line")
	var state := _state(&"a")
	for row: Array in [[25.0, "minor"], [10.0, "major"], [3.0, "extreme"]]:
		state.import_state({"active": {}})
		assert_eq(state.update(0, _mood(row[0]))["tier"], row[1], "tier at mood %s" % row[0])


func test_states_end_on_time_or_when_mood_recovers() -> void:
	var state := _state(&"a")
	var mood := _mood(20.0)
	state.update(0, mood)
	state.update(479, mood)
	assert_true(state.is_active())
	assert_eq(state.update(480, mood), {}, "withdraw lasts 8 hours, and no other starts in the update that ends it")
	assert_eq(_events[-1], [&"a", &"withdraw", &"ended", "state_exited"])
	assert_eq(mood.count(&"catharsis"), 1, "it leaves catharsis behind")
	assert_eq(state.update(481, mood)["id"], "withdraw", "but still below the line, it can start again: no cooldown")
	mood.mood = 39.0
	state.update(500, mood)
	assert_true(state.is_active())
	mood.mood = 40.0
	state.update(510, mood)
	assert_eq(_events[-1][2], &"recovered", "mood back at 40 ends it early")
	mood.mood = 20.0
	state.update(511, mood)
	state.update(511 + 480, mood)
	state.update(512 + 480, mood)
	state.update(512 + 960, mood)
	var catharsis := mood.reasons().filter(func(r: Dictionary) -> bool: return r["thought"] == &"catharsis")
	assert_eq(catharsis.map(func(r: Dictionary) -> float: return snappedf(r["value"], 0.01)), [20.0, 10.0, 5.0],
		"four episodes: catharsis stacks to three, each counting less")
	var rising := _mood(85.0)
	var spirited := _state(&"c")
	spirited.update(0, rising, _person({&"curiosity": 70.0}))
	rising.mood = 95.0
	assert_eq(spirited.update(10, rising, _person({&"curiosity": 70.0}))["id"], "inspired", "high spirits give way to inspiration")
	assert_eq(_events[-2].slice(1, 3), [&"high_spirits", &"replaced"])
	assert_eq(rising.count(&"catharsis"), 0)
	for row: Array in [[85.0, 74.0, &"high_spirits"], [95.0, 84.0, &"inspired"]]:
		var high := _mood(row[0])
		var lifted := _state(&"b")
		lifted.update(0, high, _person({&"diligence": 70.0}))
		assert_eq(lifted.active()["id"], String(row[2]))
		high.mood = row[1]
		lifted.update(10, high)
		assert_eq([_events[-1][1], _events[-1][2], high.count(&"catharsis")], [row[2], &"recovered", 0], "no catharsis after a high state")


func test_locks_and_the_developer_setting_hold_states_off() -> void:
	var state := _state(&"a")
	var mood := _mood(10.0)
	assert_eq(state.update(0, mood, null, {"locked": true}), {}, "a locked agent starts nothing")
	assert_true(BustleMentalConfig.allowed(), "on by default")
	state.update(1, mood)
	ProjectSettings.set_setting(BustleMentalConfig.SETTING, false)
	state.update(2, mood)
	assert_eq([_events[-1][2], mood.count(&"catharsis"), state.update(3, mood)], [&"disabled", 0, {}], "turned off, the state ends and none starts")
	ProjectSettings.set_setting(BustleMentalConfig.SETTING, null)
	state.enabled = false
	assert_eq(state.update(4, mood), {}, "the host's own switch too")


func test_no_chance_no_shared_limit_and_nothing_harmful() -> void:
	assert_eq(BustleMentalStateDef.Behaviour.keys(), ["WITHDRAW", "SULK", "WANDER", "BINGE", "LASH_OUT", "HIGH_SPIRITS", "INSPIRED"],
		"everything a state can be")
	var fields := BustleMentalStateDef.new().get_property_list().map(func(p: Dictionary) -> String: return p["name"])
	for word: String in ["KILL", "HARM", "LETHAL", "SELF", "DEATH", "WOUND", "INTENT"]:
		assert_false(BustleMentalStateDef.Behaviour.keys().any(func(k: String) -> bool: return k.contains(word)), word)
		assert_false(fields.any(func(f: String) -> bool: return f.to_upper().contains(word)), "no %s field" % word)
	for path: String in FILES:
		var text := FileAccess.get_file_as_string(path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "budget", "engage(", "combat"]:
			assert_false(text.contains(word), "%s mentions %s" % [path, word])
	var started := 0
	for i in 200:
		if not _state(StringName("agent_%d" % i)).update(0, _mood(20.0)).is_empty():
			started += 1
	assert_eq(started, 200, "two hundred miserable agents, two hundred states")


func test_saves_loads_and_runs_the_same_twice() -> void:
	var first := _run()
	assert_eq(_run(), first, "the same inputs, the same states")
	var entered := first.filter(func(e: Variant) -> bool: return e is Array and e[3] == "state_entered").map(func(e: Array) -> Array: return [e[0], e[1]])
	assert_true(entered.has([&"a", &"lash_out"]) and entered.has([&"b", &"inspired"]), "the run has both kinds: %s" % [entered])
	var config := BustleMentalConfig.new()
	var state := _state(&"a")
	var mood := _mood(10.0)
	state.update(5, mood)
	var saved := state.export_state()
	var copy := BustleMentalState.new(&"a", config)
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), saved)
	state.update(5 + 480, mood)
	var after := BustleMood.new()
	assert_true(after.import_state(mood.export_state(), [config.catharsis_def()] as Array[BustleThoughtDef]), "catharsis saves with the mood")
	assert_eq(after.count(&"catharsis"), 1)
	assert_true(copy.import_state(saved))
	for bad: Variant in [null, {}, {"active": {"id": "brood"}},
			{"active": {"id": "withdraw", "kind": "low", "tier": "", "since": 0, "until": 9}},
			{"active": {"id": "withdraw", "kind": "high", "tier": "minor", "since": 0, "until": 9}},
			{"active": {"id": "withdraw", "kind": "low", "tier": "minor", "since": 9, "until": 9}},
			{"active": {"id": "high_spirits", "kind": "high", "tier": "minor", "since": 0, "until": 9}}]:
		assert_false(copy.import_state(bad), "refuses %s" % [bad])
	assert_eq(copy.export_state(), saved, "a refused import changes nothing")
	assert_true(copy.import_state({"active": {}}))
	assert_false(copy.is_active())


# Three days of two agents whose thoughts come and go: the log of what happened.
func _run() -> Array:
	_events = []
	var gloom := BustleThoughtDef.new()
	gloom.id = &"gloom"
	gloom.value = -45.0
	gloom.duration_hours = 20.0
	var glee := BustleThoughtDef.new()
	glee.id = &"glee"
	glee.value = 48.0
	glee.duration_hours = 10.0
	var agents := {&"a": [_person({&"temper": 80.0}), BustleMood.new()], &"b": [_person({&"diligence": 70.0}), BustleMood.new()]}
	var states := {&"a": _state(&"a"), &"b": _state(&"b")}
	for id: StringName in agents:
		agents[id][1].start(0)
	for minute in range(0, 3 * 1440, 30):
		if minute % 1440 == 0:
			agents[&"a"][1].add_thought(gloom)
		if minute % 1440 == 600:
			agents[&"b"][1].add_thought(glee)
		for id: StringName in [&"a", &"b"]:
			agents[id][1].advance_to(minute)
			states[id].update(minute, agents[id][1], agents[id][0], {"target": "other", "target_opinion": 20.0})
	return _events.duplicate(true) + [agents[&"a"][1].export_state(), states[&"a"].export_state()]


func _choose(mood: float, sliders: Dictionary, circumstances: Dictionary = {}, modifiers: Dictionary = {}) -> StringName:
	var def := _state(&"a").choose(_mood(mood, modifiers), _person(sliders), circumstances)
	return def.id if def != null else &""


func _state(id: StringName) -> BustleMentalState:
	var state := BustleMentalState.new(id)
	state.state_entered.connect(func(a: StringName, s: StringName, info: Dictionary) -> void: _events.append([a, s, info, "state_entered"]))
	state.state_exited.connect(func(a: StringName, s: StringName, why: StringName) -> void: _events.append([a, s, why, "state_exited"]))
	return state


func _mood(value: float, modifiers: Dictionary = {}) -> BustleMood:
	var mods := BustleModifierSet.new()
	for key: StringName in modifiers:
		mods.set_source(StringName("test_%s" % key), key, modifiers[key])
	var mood := BustleMood.new(null, mods)
	mood.start(0)
	mood.mood = value
	return mood


func _person(sliders: Dictionary) -> BustlePersonality:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	return p

