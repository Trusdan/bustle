# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## An owner who notices its losses doesn't report an item that is back with it: the deed closes
## quietly as recovered. An item still with the thief, passed on to someone else or gone is
## missing, and its deed is found and reported exactly as before. A recovered deed saves, loads
## and stays closed; a save with a malformed recovered mark is refused whole.

var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _memory: BustleMemory
var _needs: Dictionary[StringName, BustleNeedSet] = {}
var _events: Array = []


func before_each() -> void:
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_crime = BustleCrime.new(_society)
	_needs = {}
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_watch = _new_watch()
	_memory = BustleMemory.new()
	_watch.memory_of = func(id: StringName) -> BustleMemory: return _memory if id == &"baker" else null
	_events = []
	_watch.deed_found.connect(func(f: StringName, i: StringName, _r: Dictionary) -> void: _events.append([&"found", f, i]))
	_watch.decided.connect(func(a: StringName, o: StringName, _r: Dictionary) -> void: _events.append([&"decided", a, o]))
	_watch.crime_reported.connect(func(r: StringName, _role: StringName, _report: Dictionary) -> void: _events.append([&"reported", r]))
	_agent(&"drifter", &"market", 1.0)
	_agent(&"baker", &"bakery", 0.0)
	_agent(&"cook", &"bakery", 0.0)
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


# A watch on _crime that reports at once, with an honest baker.
func _new_watch() -> BustleCrimeWatch:
	var watch := BustleCrimeWatch.new(_crime)
	watch.instant = true
	var honest := BustlePersonality.new()
	honest.set_slider(&"honesty", 100.0)
	watch.judge.personality_of = func(id: StringName) -> BustlePersonality: return honest if id == &"baker" else null
	return watch


# The drifter steals the baker's loaf at the market with nobody there to see: record 1, a deed.
func _deed() -> void:
	assert_false(_crime.consider(&"drifter", 10).is_empty(), "the drifter picks the loaf")
	assert_true(_crime.steal(&"drifter", 10)["ok"])
	assert_eq(_society.ports.property.owner_of(&"loaf"), &"drifter")
	assert_true(_watch.record(1)["deed"])


func test_an_item_back_with_its_owner_closes_its_deed_quietly() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"baker"), "the drifter gives it back")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [] as Array[int], "nothing is missing")
	assert_eq(_events, [], "no deed found, no decision, no report")
	var row := _watch.record(1)
	assert_eq([row["found_at"], row["recovered_at"], row["known_by"], row["decisions"], row["reporters"]],
		[-1, 30, [], {}, []], "recovered at 30, never found")
	assert_eq(_watch.open_deeds(), [] as Array[Dictionary], "the deed is closed")
	assert_eq(_watch.known_by(&"baker"), [] as Array[int], "the owner never learns of it")
	assert_eq(_memory.size(), 0, "nor remembers anything")
	assert_eq(_watch.stolen_goods_of(&"drifter"), [] as Array[Dictionary], "the drifter holds no stolen goods")
	assert_eq(_watch.notice_losses(&"baker", &"market", 50), [] as Array[int], "it stays closed")
	assert_eq(_watch.record(1)["recovered_at"], 30, "and keeps the minute it closed")


func test_an_item_still_with_the_thief_is_found_as_today() -> void:
	_deed()
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	assert_eq(_events, [[&"found", &"baker", &"loaf"], [&"decided", &"baker", &"report"], [&"reported", &"baker"]])
	var row := _watch.record(1)
	assert_eq(row["found_at"], 30)
	assert_false(row.has("recovered_at"), "only a recovered deed has the mark")
	assert_eq(_watch.known_by(&"baker"), [1] as Array[int])
	assert_eq(_memory.size(), 1, "the owner remembers the loaf where it was taken")


func test_an_item_passed_on_to_someone_else_is_still_missing() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"), "the drifter sells it on")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	assert_eq(_events, [[&"found", &"baker", &"loaf"], [&"decided", &"baker", &"report"], [&"reported", &"baker"]])
	assert_false(_watch.record(1).has("recovered_at"))


func test_an_item_that_is_gone_is_still_missing() -> void:
	_deed()
	assert_true(_society.ports.property.remove(&"loaf"), "the drifter ate it")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	assert_false(_watch.record(1).has("recovered_at"))


func test_only_the_returned_deed_closes_when_one_of_two_is_back() -> void:
	# Two hungry thieves at the market, each unseen (by the hooks), each take one of the baker's goods.
	_society.ports.property.register(&"pie", &"baker", &"market", {&"food": 0.5})
	_agent(&"tinker", &"market", 1.0)
	_crime.is_observed = func(_thief: StringName, _place: StringName) -> bool: return false
	_watch.perceives = func(_agent_id: StringName, _thief: StringName, _place: StringName) -> bool: return false
	for thief: StringName in [&"drifter", &"tinker"]:
		assert_false(_crime.consider(thief, 10).is_empty(), String(thief))
		assert_true(_crime.steal(thief, 10)["ok"], String(thief))
		# Kept out of the next thief's reach, so each takes one of the baker's goods.
		_society.ports.property.set_protected(StringName(_watch.records()[-1]["item"]), true)
	var returned := StringName(_watch.record(1)["item"])
	var missing := StringName(_watch.record(2)["item"])
	assert_eq([_watch.record(1)["owner_id"], _watch.record(2)["owner_id"]], ["baker", "baker"])
	assert_ne(returned, missing)
	_society.ports.property.set_protected(returned, false)
	assert_true(_society.ports.property.transfer(returned, &"drifter", &"baker"), "the first thief gives its take back")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [2] as Array[int])
	assert_eq(_events.filter(func(e: Array) -> bool: return e[0] == &"found"), [[&"found", &"baker", missing]])
	assert_eq([_watch.record(1)["recovered_at"], _watch.record(1)["found_at"], _watch.record(2)["found_at"]], [30, -1, 30])
	assert_false(_watch.record(2).has("recovered_at"))


func test_a_recovered_deed_saves_loads_and_stays_closed() -> void:
	_deed()
	_society.ports.property.transfer(&"loaf", &"drifter", &"baker")
	_watch.notice_losses(&"baker", &"market", 30)
	var saved := _watch.export_state()
	var loaded := _new_watch()
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.records(), _watch.records(), "the mark round-trips")
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.open_deeds(), [] as Array[Dictionary])
	assert_eq(loaded.notice_losses(&"baker", &"market", 60), [] as Array[int])
	assert_eq(loaded.record(1)["recovered_at"], 30)


func test_a_save_without_the_mark_loads_as_before() -> void:
	_deed()
	var saved := _watch.export_state()
	assert_false((saved["records"][0] as Dictionary).has("recovered_at"), "an ordinary deed saves as it always did")
	var loaded := _new_watch()
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.open_deeds().size(), 1, "and loads open")


func test_a_malformed_recovered_mark_is_refused_whole() -> void:
	_deed()
	_society.ports.property.transfer(&"loaf", &"drifter", &"baker")
	_watch.notice_losses(&"baker", &"market", 30)
	var good := _watch.export_state()
	var bad_cases := {
		"not a whole minute": func(row: Dictionary) -> void: row["recovered_at"] = "30",
		"on a found deed": func(row: Dictionary) -> void: row["found_at"] = 20,
		"on a witnessed theft": func(row: Dictionary) -> void:
			row["witnesses"] = ["cook"]
			row["deed"] = false,
	}
	for label: String in bad_cases:
		var loaded := _new_watch()
		assert_true(loaded.import_state(_watch.export_state()), "a good save loads first")
		var saved: Dictionary = good.duplicate(true)
		bad_cases[label].call(saved["records"][0])
		assert_false(loaded.import_state(saved), label)
		assert_eq(loaded.export_state(), good, label + ": nothing changes")


func _agent(id: StringName, area: StringName, hunger: float) -> void:
	_society.add_agent(id, &"villager").area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
