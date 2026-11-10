# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## An agent's ambition: assigned at once by the highest score (no chance, ties by id, a pin first,
## never a disabled template), completed by its progress or a fact, ended as moot when it can no
## longer happen, never given up, and kept from repeating right after it's done.

const FILES: Array[String] = ["res://addons/bustle/modules/ambitions/ambitions.gd",
	"res://addons/bustle/modules/ambitions/ambition_def.gd", "res://addons/bustle/modules/ambitions/ambition_config.gd"]
const DAY := 1440

var _events: Array = []


func before_each() -> void:
	_events = []


func after_each() -> void:
	ProjectSettings.set_setting(BustleAmbitionConfig.SETTING, null)


func test_the_highest_scoring_eligible_template_is_assigned_at_once() -> void:
	var a := _ambitions(&"a")
	assert_eq(a.update(0, _person({&"greed": 90.0, &"diligence": 70.0}))["id"], "save_money", "greedy and diligent: 0.48")
	assert_eq(_events, [[&"a", &"save_money", {"id": "save_money", "since": 0, "progress": 0.0}, "started"]], "at spawn, no waiting")
	assert_eq(_pick({&"diligence": 100.0}, {"has_role": true}), &"get_promoted", "a worker: 0.5")
	assert_eq(_pick({&"diligence": 100.0}), &"save_money", "without a role, promotion doesn't suit: saving's 0.2 is the best left")
	assert_eq(_pick({&"greed": 40.0, &"diligence": 100.0}), &"leave_settlement", "too little greed to save: 3 left eligible, all at 0 or less")
	assert_eq(_pick({&"sociability": 100.0}, {"has_court_target": true, "has_rival": true}), &"court_someone", "0.5 over settling's 0.2")
	assert_eq(_pick({}, {"has_role": true, "has_court_target": true, "has_rival": true}), &"court_someone",
		"all at 0: ties go to the lowest id")
	var pinned := _ambitions(&"b")
	pinned.pin = &"settle_feud"
	assert_eq(pinned.update(0, _person({&"greed": 100.0}), {"has_rival": true})["id"], "settle_feud", "a pin wins over scoring")
	var stuck := _ambitions(&"c")
	stuck.pin = &"settle_feud"
	assert_eq(stuck.update(0, _person({&"greed": 100.0}))["id"], "save_money", "a pin that isn't eligible is passed over")


func test_a_disabled_template_is_never_assigned() -> void:
	var config := BustleAmbitionConfig.new()
	config.find(&"leave_settlement").enabled = false
	for curiosity in range(0, 101, 10):
		for boldness in range(0, 101, 10):
			var a := BustleAmbitions.new(&"a", config)
			var picked := a.update(0, _person({&"curiosity": float(curiosity), &"boldness": float(boldness), &"greed": 0.0}))
			assert_ne(picked.get("id", ""), "leave_settlement")
	var a := BustleAmbitions.new(&"a", config)
	a.pin = &"leave_settlement"
	assert_eq(a.update(0, _person({&"greed": 0.0})), {}, "not even pinned; with nothing else eligible, nothing")


func test_completion_is_causal_and_nothing_is_given_up() -> void:
	var store := BustleSocialStore.new()
	var a := _ambitions(&"a")
	a.social = store
	var greedy := _person({&"greed": 90.0})
	a.update(0, greedy, {"wallet": 100.0})
	assert_eq(a.update(DAY, greedy, {"wallet": 1999.0})["progress"], 1999.0)
	assert_eq(a.update(365 * DAY, greedy, {"wallet": 1999.0})["id"], "save_money", "a year without getting there, and it's still its aim")
	a.update(365 * DAY + 1, greedy, {"wallet": 2000.0})
	assert_eq(_events[-2].slice(0, 2) + [_events[-2][3]], [&"a", &"save_money", "completed"], "reaching the target completes it")
	var deed: Dictionary = store.deeds_of(&"a", 1)[0]
	assert_eq([deed["verb"], deed["target"]], [&"achieved_ambition", &"save_money"], "and records the deed")
	assert_eq(a.active()["id"], "leave_settlement", "the library is scored again at once, without the template just done")
	for path: String in FILES:
		var text := FileAccess.get_file_as_string(path).to_lower()
		for word: String in ["abandon", "give_up", "timeout", "randf", "randi", "randomnumbergenerator", "budget"]:
			assert_false(text.contains(word), "%s mentions %s" % [path, word])
	var config := BustleAmbitionConfig.new()
	config.find(&"leave_settlement").enabled = false
	var b := BustleAmbitions.new(&"b", config)
	b.update(0, greedy, {"wallet": 0.0})
	b.update(10, greedy, {"wallet": 2500.0})
	assert_eq(b.update(11, greedy, {"wallet": 0.0}), {}, "spent it all, but not again for 7 days")
	assert_eq(b.update(10 + 7 * DAY - 1, greedy, {"wallet": 0.0}), {})
	assert_eq(b.update(10 + 7 * DAY, greedy, {"wallet": 0.0})["id"], "save_money", "then it can save again")
	assert_eq(b.update(10 + 8 * DAY, greedy, {"wallet": 3000.0}).get("id", ""), "", "done again")
	assert_eq(b.update(10 + 20 * DAY, greedy, {"wallet": 3000.0}), {}, "and while its target is still met, saving isn't eligible")
	config.find(&"save_money").next = &"get_promoted"
	var c := BustleAmbitions.new(&"c", config)
	c.update(0, greedy, {"wallet": 0.0, "has_role": true})
	assert_eq(c.update(1, greedy, {"wallet": 2000.0, "has_role": true})["id"], "get_promoted", "its next template, when eligible")


func test_an_impossible_ambition_ends_moot_and_another_starts_at_once() -> void:
	var config := BustleAmbitionConfig.new()
	config.find(&"court_someone").next = &"save_money"
	var a := BustleAmbitions.new(&"a", config)
	_listen(a)
	var warm := _person({&"sociability": 100.0})
	a.update(0, warm, {"has_court_target": true})
	assert_eq(a.update(DAY, warm, {"has_court_target": true, "court_opinion": 70.0})["progress"], 70.0)
	var after := a.update(2 * DAY, warm, {"has_court_target": true, "court_target_gone": false})
	assert_eq(after["id"], "court_someone")
	after = a.update(3 * DAY, warm, {"court_target_gone": true})
	assert_eq(_events[-2], [&"a", &"court_someone", &"court_target_gone", "moot"], "the one it courted is gone for good")
	assert_eq(after["id"], "leave_settlement", "nobody else to court: the library is scored again (no next chain)")
	var only_court := BustleAmbitionConfig.new()
	for def: BustleAmbitionDef in only_court.templates:
		def.enabled = def.id == &"court_someone"
	a = BustleAmbitions.new(&"a", only_court)
	_listen(a)
	a.update(0, warm, {"has_court_target": true})
	assert_eq(a.update(DAY, warm, {"has_court_target": true, "court_target_gone": true}), {}, "while that fact holds, it's moot")
	assert_eq(a.update(DAY + 1, warm, {"has_court_target": true})["id"], "court_someone", "someone else to court: it starts again, no cooldown")
	assert_eq(_events.filter(func(e: Array) -> bool: return e[3] == "completed"), [], "moot isn't completion")


func test_the_developer_setting_and_no_shared_limit() -> void:
	assert_true(BustleAmbitionConfig.allowed(), "on by default")
	ProjectSettings.set_setting(BustleAmbitionConfig.SETTING, false)
	assert_eq(_ambitions(&"a").update(0), {}, "turned off, nothing is assigned")
	ProjectSettings.set_setting(BustleAmbitionConfig.SETTING, null)
	var off := _ambitions(&"b")
	off.enabled = false
	assert_eq(off.update(0), {})
	var given := 0
	for i in 200:
		if not _ambitions(StringName("agent_%d" % i)).update(0, _person({&"greed": 80.0})).is_empty():
			given += 1
	assert_eq(given, 200, "two hundred agents, two hundred ambitions")


func test_saves_loads_and_runs_the_same_twice() -> void:
	var first := _run()
	assert_eq(_run(), first, "the same inputs, the same ambitions")
	var kinds := first.filter(func(e: Variant) -> bool: return e is Array).map(func(e: Array) -> String: return "%s %s" % [e[1], e[3]])
	assert_true(kinds.has("save_money completed") and kinds.has("get_promoted completed") and kinds.has("court_someone moot"), "%s" % [kinds])
	var a := _ambitions(&"a")
	a.update(0, _person({&"greed": 90.0}), {"wallet": 0.0})
	a.update(5, _person({&"greed": 90.0}), {"wallet": 2000.0})
	a.update(6, _person({&"greed": 90.0}), {"has_role": true, "wallet": 2000.0})
	var saved := a.export_state()
	assert_eq(saved["completed"], {"save_money": 5}, "enough history for the cooldown")
	var copy := BustleAmbitions.new(&"a")
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), saved)
	assert_eq(copy.update(7, _person({&"greed": 90.0}), {"wallet": 0.0, "has_role": true})["id"], saved["active"]["id"])
	for bad: Variant in [null, {}, {"active": {"id": "become_king", "since": 0, "progress": 0.0}, "completed": {}},
			{"active": {}, "completed": {"save_money": "soon"}}, {"active": {"id": "save_money"}, "completed": {}}]:
		assert_false(copy.import_state(bad), "refuses %s" % [bad])


# Thirty days of three agents whose circumstances change: the log of what happened.
func _run() -> Array:
	_events = []
	var agents := {&"saver": _person({&"greed": 90.0}), &"worker": _person({&"diligence": 90.0}), &"suitor": _person({&"sociability": 90.0})}
	var states := {}
	for id: StringName in agents:
		states[id] = _ambitions(id)
	for day in 30:
		var inputs := {"wallet": float(day * 150), "has_role": true, "promotion_granted": day == 12,
			"has_court_target": day < 20, "court_opinion": 50.0 + day, "court_target_gone": day >= 20}
		for id: StringName in [&"saver", &"worker", &"suitor"]:
			states[id].update(day * DAY, agents[id], inputs)
	return _events.duplicate(true) + [states[&"saver"].export_state()]


func _pick(sliders: Dictionary, inputs: Dictionary = {}) -> StringName:
	var def := BustleAmbitions.new(&"x").choose(0, _person(sliders), inputs)
	return def.id if def != null else &""


func _ambitions(id: StringName) -> BustleAmbitions:
	var a := BustleAmbitions.new(id)
	_listen(a)
	return a


func _listen(a: BustleAmbitions) -> void:
	a.ambition_started.connect(func(agent: StringName, id: StringName, info: Dictionary) -> void: _events.append([agent, id, info, "started"]))
	a.ambition_completed.connect(func(agent: StringName, id: StringName, info: Dictionary) -> void: _events.append([agent, id, info, "completed"]))
	a.ended_moot.connect(func(agent: StringName, id: StringName, fact: StringName) -> void: _events.append([agent, id, fact, "moot"]))


func _person(sliders: Dictionary) -> BustlePersonality:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	return p
