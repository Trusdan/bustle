# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## After a theft: only those who perceived it are witnesses; each witness remembers it and reports
## it to the authority role; a theft nobody perceived is a deed its owner finds later, and the
## stolen goods point to it.


class Health:
	extends BustleHealthPort
	var down: Array[StringName] = []

	func is_incapacitated(id: StringName) -> bool:
		return down.has(id)


var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _health: Health
var _needs: Dictionary[StringName, BustleNeedSet] = {}
var _events: Array = []


func before_each() -> void:
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_health = Health.new()
	_society.set_port(&"health", _health)
	_crime = BustleCrime.new(_society)
	_needs = {}
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_watch = BustleCrimeWatch.new(_crime)
	_events = []
	_watch.witnessed.connect(func(w: StringName, t: StringName, i: StringName, _r: Dictionary) -> void: _events.append([&"witnessed", w, t, i]))
	_watch.crime_reported.connect(func(r: StringName, role: StringName, report: Dictionary) -> void: _events.append([&"reported", r, role, report]))
	_watch.deed_found.connect(func(f: StringName, i: StringName, _r: Dictionary) -> void: _events.append([&"found", f, i]))
	_agent(&"drifter", &"market", 1.0)
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


func test_a_theft_nobody_perceived_is_a_deed_its_owner_finds() -> void:
	_agent(&"sleeper", &"market", 0.0)
	_health.down = [&"sleeper"]
	assert_false(_crime.consider(&"drifter", 10).is_empty(), "one who can't perceive doesn't stop a thief")
	assert_true(_crime.steal(&"drifter", 10)["ok"])
	var deed := _watch.record(1)
	assert_eq([deed["witnesses"], deed["deed"], deed["reporters"], deed["found_at"]], [[], true, [], -1], "nobody saw, so nobody knows")
	assert_eq(_events, [], "no witness and no report out of thin air")
	assert_eq(_watch.open_deeds(), [deed])
	assert_eq(_watch.stolen_goods_of(&"drifter"), [deed], "the stolen loaf points to the deed")
	assert_eq(_watch.notice_losses(&"baker", &"well", 20), [] as Array[int], "it's found only where it was taken")
	assert_eq(_watch.notice_losses(&"cook", &"market", 20), [] as Array[int], "and only by its owner")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	var report := {"id": 1, "thief": "", "owner_id": "baker", "item": "loaf", "place": "market", "at": 10,
		"witnesses": [], "deed": true, "found_at": 30, "reporter": "baker", "role": "authority",
		"authority": "warden", "reported_at": 30}
	assert_eq(_events, [[&"found", &"baker", &"loaf"], [&"reported", &"baker", &"authority", report]],
		"the owner reports its loss, not knowing who took it")
	assert_eq([_watch.open_deeds(), _watch.known_by(&"baker"), _watch.known_by(&"warden")], [[], [1], []])
	assert_eq(_watch.notice_losses(&"baker", &"market", 40), [] as Array[int], "a deed is found once")
	_society.ports.property.remove(&"loaf")
	assert_eq(_watch.stolen_goods_of(&"drifter"), [] as Array[Dictionary], "eaten, the evidence is gone; the record stays")
	assert_eq(_watch.records().size(), 1)


func test_only_those_who_perceived_it_are_witnesses() -> void:
	_agent(&"onlooker", &"market", 0.0)
	_agent(&"fallen", &"market", 0.0)
	_agent(&"far", &"well", 0.0)
	_health.down = [&"fallen"]
	var memories: Dictionary[StringName, BustleMemory] = {&"onlooker": BustleMemory.new(), &"far": BustleMemory.new()}
	_watch.memory_of = func(id: StringName) -> BustleMemory: return memories.get(id)
	assert_eq(_crime.consider(&"drifter", 0), {}, "by default, a thief doesn't steal in front of someone")
	_crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	_watch.authority_role = &"watch"
	_crime.consider(&"drifter", 50)
	assert_true(_crime.steal(&"drifter", 50)["ok"], "a thief who didn't notice the onlooker")
	var row := _watch.record(1)
	assert_eq([row["witnesses"], row["known_by"], row["reporters"], row["deed"]], [["onlooker"], ["onlooker"], ["onlooker"], false],
		"the one who perceived it, not the fallen one, not the one elsewhere")
	assert_eq(_events.size(), 2)
	assert_eq(_events[0], [&"witnessed", &"onlooker", &"drifter", &"loaf"])
	assert_eq([_events[1][1], _events[1][2], _events[1][3]["thief"], _events[1][3]["authority"]], [&"onlooker", &"watch", "drifter", ""],
		"reported to the role, whoever holds it (nobody yet)")
	assert_eq(memories[&"onlooker"].recall(BustleMemory.PERSON, &"drifter", 50)["source"], BustleMemory.SAW, "the witness remembers the thief")
	assert_eq(memories[&"onlooker"].recall(BustleMemory.ITEM, &"loaf", 50)["area"], &"market")
	assert_eq(memories[&"far"].size(), 0)
	assert_eq(_watch.open_deeds(), [] as Array[Dictionary])
	assert_eq(_watch.notice_losses(&"baker", &"market", 60), [] as Array[int], "a witnessed theft isn't a deed")
	_watch.perceives = func(a: StringName, _t: StringName, _p: StringName) -> bool: return a == &"far"
	_agent(&"second", &"market", 1.0)
	_society.ports.property.register(&"bun", &"baker", &"market", {&"food": 0.3})
	_crime.consider(&"second", 70)
	_crime.steal(&"second", 70)
	assert_eq(_watch.record(2)["witnesses"], ["far"], "the host decides who perceived it")


func test_property_can_be_used_up_only_by_the_host() -> void:
	var property := _society.ports.property
	assert_true(property.remove(&"loaf"))
	assert_false(property.remove(&"loaf"))
	assert_eq(property.item(&"loaf"), {})
	assert_eq(_crime.consider(&"drifter", 0), {}, "nothing left to take")
	assert_false(FileAccess.get_file_as_string("res://addons/bustle/core/crime/crime.gd").contains(".remove("), "theft never destroys goods")


func test_records_save_and_refuse_bad_data() -> void:
	_crime.consider(&"drifter", 5)
	_crime.steal(&"drifter", 5)
	_watch.notice_losses(&"baker", &"market", 6)
	var saved := _watch.export_state()
	var copy := BustleCrimeWatch.new(BustleCrime.new(_society))
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), saved)
	var bad: Array = [null, {}, {"next_id": 1, "records": saved["records"]},
		{"next_id": 2, "records": saved["records"] + saved["records"]}]
	for change: Callable in [
			func(r: Dictionary) -> void: r["witnesses"] = ["someone"],
			func(r: Dictionary) -> void: r["known_by"] = [3],
			func(r: Dictionary) -> void: r["thief"] = null,
			func(r: Dictionary) -> void: r["id"] = 0]:
		var broken: Dictionary = saved.duplicate(true)
		change.call(broken["records"][0])
		bad.append(broken)
	for entry: Variant in bad:
		assert_false(copy.import_state(entry), "refuses %s" % [entry])
	assert_eq(copy.export_state(), saved, "a refused import changes nothing")


func _agent(id: StringName, area: StringName, hunger: float) -> void:
	_society.add_agent(id, &"villager").area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
