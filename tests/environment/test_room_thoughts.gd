# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Environment thoughts: room scores change the held thoughts of agents inside, leaving or a score
## change updates them, no port means no thoughts, and saving adds no duplicates. Rooms, scores and
## thoughts are a small neutral test set.

var _ports: BustlePorts
var _env: BustleEnvironmentPort
var _rooms: BustleRoomThoughts
var _defs: Dictionary[StringName, BustleThoughtDef] = {}
var _rules: Array[BustleRoomThought] = []


func _thought(id: StringName, value: float) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.reason_kind = &"environment"
	_defs[id] = def
	return def


func _rule(score: StringName, thought: BustleThoughtDef, at_least: float = NAN, at_most: float = NAN) -> BustleRoomThought:
	var rule := BustleRoomThought.new()
	rule.score = score
	rule.thought = thought
	rule.at_least = at_least
	rule.at_most = at_most
	return rule


func _build() -> void:
	_ports = BustlePorts.new()
	_env = _ports.environment
	_defs.clear()
	_rules = [
		_rule(&"beauty", _thought(&"pleasant_room", 3.0), 0.6),
		_rule(&"beauty", _thought(&"beautiful_room", 6.0), 0.85),
		_rule(&"cleanliness", _thought(&"dirty_room", -4.0), NAN, 0.3),
		_rule(&"cleanliness", _thought(&"filthy_room", -8.0), NAN, 0.1),
		_rule(&"comfort", _thought(&"cramped_room", -3.0), NAN, 0.25),
		_rule(&"impressiveness", _thought(&"grand_room", 5.0), 0.8),
	]
	_rooms = BustleRoomThoughts.new(_rules, _ports)
	_env.set_scores(&"hall", {&"beauty": 0.9, &"impressiveness": 0.85})
	_env.set_scores(&"parlour", {&"beauty": 0.65, &"cleanliness": 0.5})
	_env.set_scores(&"shed", {&"cleanliness": 0.2, &"comfort": 0.1})
	_env.set_scores(&"cellar", {&"cleanliness": 0.05})
	_env.set_scores(&"store", {&"beauty": 0.5})


func before_each() -> void:
	_build()


func _target_in(room: StringName) -> float:
	var mood := BustleMood.new()
	_env.set_room(&"baker", room)
	_rooms.sync(&"baker", mood)
	return mood.target()


# Acceptance (1): a room's scores change the thoughts of agents inside it.
func test_a_better_room_gives_a_better_thought() -> void:
	var mood := BustleMood.new()
	_env.set_room(&"baker", &"hall")
	assert_eq(_rooms.sync(&"baker", mood), [&"beautiful_room", &"grand_room"] as Array[StringName])
	assert_eq(mood.count(&"beautiful_room"), 1)
	assert_eq(mood.count(&"pleasant_room"), 0, "only the most extreme beauty rule it meets")
	var reason: Dictionary = mood.reasons()[0]["reason"]
	assert_eq(reason["kind"], "environment")
	assert_eq(reason["room"], "hall")
	var outdoors := _target_in(&"")
	assert_gt(_target_in(&"hall"), _target_in(&"parlour"), "beauty 0.9 beats 0.65")
	assert_gt(_target_in(&"parlour"), outdoors)
	assert_lt(_target_in(&"shed"), outdoors, "a dirty, cramped room is worse")
	_env.set_scores(&"scullery", {&"cleanliness": 0.2})
	assert_lt(_target_in(&"cellar"), _target_in(&"scullery"), "filthy (cleanliness 0.05) is worse than dirty (0.2)")
	assert_eq(_target_in(&"store"), outdoors, "beauty 0.5 meets no rule")


func test_each_agent_gets_its_own_rooms_thoughts() -> void:
	var baker := BustleMood.new()
	var smith := BustleMood.new()
	_env.set_room(&"baker", &"hall")
	_env.set_room(&"smith", &"shed")
	_rooms.sync(&"baker", baker)
	_rooms.sync(&"smith", smith)
	assert_eq(baker.count(&"dirty_room"), 0)
	assert_eq(smith.count(&"beautiful_room"), 0)
	assert_eq(smith.count(&"dirty_room"), 1)
	assert_eq(smith.count(&"cramped_room"), 1)


func test_an_unset_score_is_not_zero() -> void:
	var mood := BustleMood.new()
	_env.set_room(&"baker", &"hall")
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(&"filthy_room"), 0, "no cleanliness score: no low thought")
	assert_eq(mood.count(&"cramped_room"), 0)


# Acceptance (2): leaving, moving or a score change updates or clears the thoughts.
func test_leaving_or_moving_clears_or_swaps_the_thoughts() -> void:
	var mood := BustleMood.new()
	_env.set_room(&"baker", &"hall")
	_rooms.sync(&"baker", mood)
	watch_signals(_rooms)
	_env.set_room(&"baker", &"shed")
	assert_eq(_rooms.sync(&"baker", mood), [&"cramped_room", &"dirty_room"] as Array[StringName])
	assert_eq(mood.count(&"beautiful_room") + mood.count(&"grand_room"), 0)
	assert_signal_emitted_with_parameters(_rooms, "room_changed", [&"baker", &"hall", &"shed"])
	_env.set_room(&"baker", &"")
	assert_true(_rooms.sync(&"baker", mood).is_empty())
	assert_eq(mood.count(), 0, "outside every room: none left")
	assert_signal_emitted_with_parameters(_rooms, "room_changed", [&"baker", &"shed", &""])
	assert_true(_rooms.export_state().is_empty())


func test_a_score_change_updates_the_thoughts_in_place() -> void:
	var mood := BustleMood.new()
	_env.set_room(&"baker", &"parlour")
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(&"pleasant_room"), 1)
	_env.set_scores(&"parlour", {&"beauty": 0.95, &"cleanliness": 0.25})
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(&"pleasant_room"), 0, "swapped for the better one")
	assert_eq(mood.count(&"beautiful_room"), 1)
	assert_eq(mood.count(&"dirty_room"), 1, "it got dirty")
	_env.set_scores(&"parlour", {&"beauty": 0.96, &"cleanliness": 0.8})
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(&"dirty_room"), 0, "cleaned")
	assert_eq(mood.count(&"beautiful_room"), 1, "held once, not twice")
	var reason: Dictionary = mood.reasons()[0]["reason"]
	assert_almost_eq(float(reason["value"]), 0.96, 1e-6, "the reason follows the score")
	_env.set_scores(&"parlour", {})
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(), 0, "an unscored room gives none")


func test_other_thoughts_are_left_alone() -> void:
	var mood := BustleMood.new()
	var other := BustleThoughtDef.new()
	other.id = &"good_meal"
	other.value = 2.0
	other.duration_hours = 4.0
	mood.add_thought(other)
	_env.set_room(&"baker", &"hall")
	_rooms.sync(&"baker", mood)
	_env.set_room(&"baker", &"")
	_rooms.sync(&"baker", mood)
	assert_eq(mood.count(&"good_meal"), 1)
	assert_eq(mood.count(), 1)


# Acceptance (3): with no environment port, or the default one, no thoughts and no errors.
func test_no_port_means_no_environment_thoughts() -> void:
	var mood := BustleMood.new()
	var defaults := BustleRoomThoughts.new(_rules, BustlePorts.new())
	assert_true(defaults.sync(&"baker", mood).is_empty(), "the default port has no rooms")
	_ports.environment = null
	assert_true(_rooms.sync(&"baker", mood).is_empty())
	assert_true(BustleRoomThoughts.new(_rules, null).sync(&"baker", mood).is_empty())
	assert_eq(mood.count(), 0)
	assert_eq(BustleEnvironmentPort.new().room_of(&"baker"), &"")
	assert_true(BustleEnvironmentPort.new().scores(&"hall").is_empty())
	assert_push_error_count(0)


func test_no_mood_means_no_thoughts_and_no_errors() -> void:
	_env.set_room(&"baker", &"hall")
	assert_eq(_rooms.sync(&"baker"), [&"beautiful_room", &"grand_room"] as Array[StringName], "chosen, nothing held")
	assert_push_error_count(0)


# Acceptance (4): save and load round-trip with no duplicate thoughts; same inputs, same result.
func test_save_and_load_without_duplicates() -> void:
	var mood := BustleMood.new()
	_env.set_room(&"baker", &"hall")
	_env.set_room(&"smith", &"shed")
	_rooms.sync(&"baker", mood)
	var saved: Variant = JSON.parse_string(JSON.stringify({"env": _env.export_state(), "rooms": _rooms.export_state(),
		"mood": mood.export_state()}))
	var before := [_env.export_state(), _rooms.export_state(), mood.export_state()]
	_build()
	var loaded := BustleMood.new()
	assert_true(_env.import_state(saved["env"]))
	assert_true(_rooms.import_state(saved["rooms"]))
	assert_true(loaded.import_state(saved["mood"], _defs.values() as Array[BustleThoughtDef]))
	assert_eq([_env.export_state(), _rooms.export_state(), loaded.export_state()], before)
	assert_eq(_env.room_of(&"smith"), &"shed", "room membership survives")
	for i: int in 3:
		_rooms.sync(&"baker", loaded)
	assert_eq(loaded.count(&"beautiful_room"), 1, "no duplicate after load and repeated syncs")
	assert_eq(loaded.count(), 2)


func test_same_inputs_give_the_same_thoughts() -> void:
	var runs: Array = []
	for run: int in 2:
		_build()
		var mood := BustleMood.new()
		for step: int in 12:
			_env.set_room(&"baker", [&"hall", &"parlour", &"shed", &"", &"cellar"][step % 5])
			_env.set_scores(&"parlour", {&"beauty": 0.1 * (step % 10), &"cleanliness": 0.05 * step})
			_rooms.sync(&"baker", mood)
			mood.advance_to(step * 60)
		runs.append([mood.export_state(), _rooms.export_state()])
	assert_eq(runs[0], runs[1])


func test_imports_refuse_bad_data_and_change_nothing() -> void:
	_env.set_room(&"baker", &"hall")
	_rooms.sync(&"baker", BustleMood.new())
	var env_before := _env.export_state()
	for saved: Variant in [null, {}, {"rooms": {}, "scores": {"hall": {"warmth": 0.5}}},
			{"rooms": {}, "scores": {"hall": {"beauty": 1.5}}}, {"rooms": {"baker": ""}, "scores": {}},
			{"rooms": {}, "scores": {"hall": {}}}]:
		assert_false(_env.import_state(saved), str(saved))
		assert_eq(_env.export_state(), env_before, str(saved))
	var rooms_before := _rooms.export_state()
	for saved: Variant in [null, {"baker": {"room": "hall"}}, {"baker": {"room": "hall", "thoughts": ["sunny_room"]}},
			{"baker": {"room": "hall", "thoughts": ["grand_room", "grand_room"]}}, {"": {"room": "", "thoughts": []}}]:
		assert_false(_rooms.import_state(saved), str(saved))
		assert_eq(_rooms.export_state(), rooms_before, str(saved))


func test_bad_scores_and_rules_are_refused() -> void:
	assert_false(_env.set_scores(&"hall", {&"warmth": 0.5}))
	assert_false(_env.set_scores(&"hall", {&"beauty": -0.1}))
	assert_false(_env.set_scores(&"", {&"beauty": 0.5}))
	assert_false(_env.set_room(&"", &"hall"))
	assert_eq(_env.scores(&"hall"), {&"beauty": 0.9, &"impressiveness": 0.85} as Dictionary[StringName, float])
	var thought := _thought(&"odd_room", 1.0)
	assert_false(_rule(&"warmth", thought, 0.5).is_valid(), "unknown score")
	assert_false(_rule(&"beauty", thought).is_valid(), "no line")
	assert_false(_rule(&"beauty", thought, 0.5, 0.2).is_valid(), "both lines")
	assert_false(_rule(&"beauty", thought, 1.5).is_valid())
	assert_false(_rule(&"beauty", null, 0.5).is_valid())
	assert_false(_rooms.add_rule(null))
