# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## prune(before_minute) removes closed crime records whose last event was before the cutoff and
## returns them: witnessed thefts and found or recovered deeds, never an open deed or a record an
## errand still refers to. Ids aren't reused, and a pruned watch saves and loads. import_state()
## refuses a non-positive next_id, a found_at below -1 and a found_at on a witnessed theft, and a
## refusal changes nothing.

var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _needs: Dictionary[StringName, BustleNeedSet] = {}


func before_each() -> void:
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_crime = BustleCrime.new(_society)
	_needs = {}
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_crime.is_observed = func(_thief: StringName, _place: StringName) -> bool: return false
	_watch = BustleCrimeWatch.new(_crime)
	_watch.instant = true
	var honest := BustlePersonality.new()
	honest.set_slider(&"honesty", 100.0)
	_watch.judge.personality_of = func(id: StringName) -> BustlePersonality: return honest if id in [&"baker", &"cook"] else null
	_agent(&"drifter", &"market", 1.0)
	_agent(&"baker", &"bakery", 0.0)
	_agent(&"cook", &"bakery", 0.0)
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


# The drifter steals a new loaf of the baker's at [param at], seen by the cook when [param seen],
# and eats it unless [param keep].
func _theft(at: int, seen: bool, keep: bool = false) -> int:
	var item := StringName("loaf_%d" % at)
	_society.ports.property.register(item, &"baker", &"market", {&"food": 0.5})
	_society.get_agent(&"cook").area = &"market" if seen else &"bakery"
	_needs[&"drifter"].raise(&"food", 1.0)
	assert_false(_crime.consider(&"drifter", at).is_empty())
	assert_true(_crime.steal(&"drifter", at)["ok"])
	if not keep:
		_society.ports.property.remove(item)
	return _watch.records()[-1]["id"]


func _ids() -> Array:
	return _watch.records().map(func(r: Dictionary) -> int: return r["id"])


func test_without_a_call_every_record_is_kept() -> void:
	_theft(10, true)
	_theft(20, false)
	var saved := _watch.export_state()
	assert_eq(_ids(), [1, 2])
	assert_eq(_watch.export_state(), saved)


func test_a_closed_witnessed_theft_older_than_the_cutoff_is_pruned_and_returned() -> void:
	var id := _theft(10, true)
	assert_false(_watch.record(id)["deed"])
	var before := _watch.record(id)
	assert_eq(_watch.prune(10), [] as Array[Dictionary], "not before minute 10")
	assert_eq(_watch.prune(11), [before], "returned as it was")
	assert_eq(_watch.records(), [] as Array[Dictionary])
	assert_eq(_watch.known_by(&"cook"), [] as Array[int])
	assert_eq(_watch.prune(1000), [] as Array[Dictionary], "pruned once")


func test_an_open_deed_is_never_pruned() -> void:
	var id := _theft(10, false)
	assert_true(_watch.record(id)["deed"])
	assert_eq(_watch.prune(100000), [] as Array[Dictionary])
	assert_eq(_watch.open_deeds().size(), 1)


func test_a_found_deed_is_aged_from_when_it_was_found() -> void:
	var id := _theft(10, false)
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [id])
	assert_eq(_watch.prune(30), [] as Array[Dictionary], "found at 30, so it's newer than the theft")
	assert_eq(_watch.prune(31).size(), 1)


func test_a_recovered_deed_is_aged_from_when_it_was_recovered() -> void:
	var id := _theft(10, false, true)
	_society.ports.property.transfer(StringName(_watch.record(id)["item"]), &"drifter", &"baker")
	assert_eq(_watch.notice_losses(&"baker", &"market", 40), [] as Array[int])
	assert_eq(_watch.record(id)["recovered_at"], 40)
	assert_eq(_watch.prune(40), [] as Array[Dictionary])
	assert_eq(_watch.prune(41).size(), 1)


func test_a_record_an_errand_still_refers_to_is_kept_until_it_is_delivered() -> void:
	_watch.instant = false
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"")
	var id := _theft(10, true)
	assert_eq(_watch.errands_of(&"cook").size(), 1, "the cook sets out to report, but nobody holds the role")
	assert_eq(_watch.prune(1000), [] as Array[Dictionary], "its record stays while the errand waits")
	_agent(&"warden", &"bakery", 0.0)
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")
	_society.get_agent(&"cook").area = &"bakery"
	assert_eq(_watch.deliver(&"cook", 50)["state"], &"delivered")
	assert_eq(_watch.prune(1000).map(func(r: Dictionary) -> int: return r["id"]), [id], "then it can go")


func test_ids_are_never_reused_and_a_pruned_watch_saves_and_loads() -> void:
	_theft(10, true)
	_theft(20, false)
	_theft(30, true)
	assert_eq(_watch.prune(25).map(func(r: Dictionary) -> int: return r["id"]), [1])
	assert_eq(_theft(40, true), 4, "the next id follows on")
	var copy := BustleCrimeWatch.new(BustleCrime.new(_society))
	assert_true(copy.import_state(_watch.export_state()), "a gap in the ids loads")
	assert_eq(copy.export_state(), _watch.export_state())


func test_import_refuses_bad_ids_and_found_minutes_and_changes_nothing() -> void:
	_theft(10, true)
	_theft(20, false)
	var good := _watch.export_state()
	var cases := {
		"next_id 0": func(s: Dictionary) -> void: s["next_id"] = 0,
		"next_id below 0": func(s: Dictionary) -> void: s["next_id"] = -3,
		"found_at below -1": func(s: Dictionary) -> void: s["records"][1]["found_at"] = -2,
		"found_at on a witnessed theft": func(s: Dictionary) -> void: s["records"][0]["found_at"] = 15,
	}
	for label: String in cases:
		var saved: Dictionary = good.duplicate(true)
		cases[label].call(saved)
		assert_false(_watch.import_state(saved), label)
		assert_eq(_watch.export_state(), good, label + ": nothing changes")
	var found := good.duplicate(true)
	found["records"][1]["found_at"] = 30
	assert_true(_watch.import_state(found), "a found deed's minute still loads")


func _agent(id: StringName, area: StringName, hunger: float) -> void:
	_society.add_agent(id, &"villager").area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
