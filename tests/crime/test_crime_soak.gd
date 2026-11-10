# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Thirty days of a small village, every half hour: bread is baked and eaten, hunger rises, and
## whoever is driven to it steals. Every theft is witnessed and remembered, or it leaves a deed;
## each who knows of it decides what to do (a witness grows afraid of a thief it keeps seeing, so
## not every witness reports, but a silent one still remembers); nobody witnesses what they didn't
## perceive; theft never makes or destroys goods; and the same village runs the same way twice.
## A report counts only when its bearer reaches the warden face to face: nobody sets out at night,
## everyone waits while the warden is away (days 8 to 19), an errand left waiting too long is
## forgotten, and the thief can face down a witness it meets on the way.

const DAYS := 30
const STEP := 30
const HUNGRY_PER_STEP := 0.025
## The onlooker is easy to miss: thieves don't notice it, but it sees them.
const HIDDEN := &"onlooker"
const AWAY := [8, 20]


class Village:
	extends RefCounted
	var society := BustleSociety.new(11)
	var crime: BustleCrime
	var watch: BustleCrimeWatch
	var needs: Dictionary[StringName, BustleNeedSet] = {}
	var memories: Dictionary[StringName, BustleMemory] = {}
	var people: Dictionary[StringName, BustlePersonality] = {}
	var events: Array = []
	var problems: Array[String] = []
	var baked: int = 0
	var _routes: Dictionary[StringName, Array] = {}
	var _heading: Dictionary[StringName, StringName] = {}
	var _dropped: Dictionary[String, String] = {}

	func _init() -> void:
		society.register_archetype(&"villager", BustleGoalLibrary.new())
		crime = BustleCrime.new(society)
		crime.personality_of = _personality_of
		crime.needs_of = _needs_of
		crime.is_observed = _thief_sees_someone
		watch = BustleCrimeWatch.new(crime)
		watch.witnessed.connect(_on_witnessed)
		watch.crime_reported.connect(_on_reported)
		watch.deed_found.connect(_on_found)
		watch.decided.connect(_on_decided)
		watch.judge.personality_of = _personality_of
		watch.judge.fear_of = _fear_of
		watch.memory_of = _memory_of
		watch.can_travel = _by_day
		watch.errand_dropped.connect(_on_dropped)
		society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")
		_add(&"baker", {"honesty": 80.0, "boldness": 70.0, "diligence": 70.0}, _hours({6: "market", 12: "well", 14: "market", 18: "home_baker"}))
		_add(&"cook", {"honesty": 70.0}, _hours({7: "mill", 12: "market", 14: "mill", 20: "home_cook"}))
		_add(&"warden", {"honesty": 90.0}, _hours({8: "market", 10: "well", 12: "mill", 14: "market", 16: "well", 18: "home_warden"}))
		# A 25-hour round, so it is somewhere else at each hour from one day to the next.
		_add(HIDDEN, {"honesty": 80.0, "piety": 70.0, "diligence": 70.0}, _hours({0: "home_onlooker", 10: "mill", 13: "home_onlooker", 17: "market", 20: "home_onlooker"}) + ["home_onlooker"])
		_add(&"drifter", {"honesty": 20.0, "greed": 70.0, "boldness": 60.0}, ["market", "well", "mill"])
		_add(&"rover", {"honesty": 30.0, "greed": 60.0, "boldness": 50.0}, ["mill", "market", "well", "camp"])
		_add(&"pauper", {}, ["well", "mill", "market", "camp", "camp"])

	func run() -> void:
		for minute in range(0, DAYS * 1440, STEP):
			var hour := floori((minute % 1440) / 60.0)
			if minute % 1440 == 6 * 60:
				_bake(&"baker", &"market", 3, 0.5, minute)
			if minute % 1440 == 7 * 60:
				_bake(&"cook", &"mill", 1, 0.8, minute)
			if minute % 1440 == 22 * 60:
				for row: Dictionary in society.ports.property.items_of(&"baker") + society.ports.property.items_of(&"cook"):
					society.ports.property.remove(StringName(row["id"]))
			var day := floori(minute / 1440.0)
			society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"" if day >= AWAY[0] and day < AWAY[1] else &"warden")
			for id: StringName in society.agent_ids():
				var route: Array = _routes[id]
				society.get_agent(id).area = StringName(route[floori(minute / 60.0) % route.size()] if route.size() != 24 else route[hour])
				if _heading.has(id):
					society.get_agent(id).area = _heading[id]
					_heading.erase(id)
			for id: StringName in society.agent_ids():
				needs[id].raise(&"food", HUNGRY_PER_STEP)
				_eat(id)
				watch.notice_losses(id, society.get_agent(id).area, minute)
				if crime.consider(id, minute).is_empty():
					continue
				var before: int = society.ports.property.export_state()["items"].size()
				var took := crime.steal(id, minute)
				if society.ports.property.export_state()["items"].size() != before:
					problems.append("a theft changed how many goods there are at %d" % minute)
				events.append(["theft", id, took.get("item", ""), minute])
			for id: StringName in society.agent_ids():
				_run_errand(id, minute)

	# The host's side of an errand: the brain would run [code]deliver[/code]; this moves the body,
	# one step to the target's place, and lets the thief face down a witness it meets.
	func _run_errand(id: StringName, minute: int) -> void:
		for errand: Dictionary in watch.errands_of(id):
			var thief := StringName(watch.record(int(errand["record"]))["thief"])
			if errand["knows_thief"] and society.get_agent(thief).area == society.get_agent(id).area:
				watch.intimidate(thief, id, minute)
		var inputs: Dictionary[StringName, float] = {}
		watch.fill_inputs(id, inputs, minute)
		if not inputs.has(BustleCrimeWatch.INPUT):
			return
		var result := watch.deliver(id, minute)
		if result["state"] == &"travelling":
			_heading[id] = society.get_agent(result["target"]).area
		events.append(["errand", id, result["state"], minute])

	func _by_day(_agent: StringName, minute: int) -> bool:
		var hour := floori((minute % 1440) / 60.0)
		return hour >= 6 and hour < 22

	func _on_dropped(agent: StringName, errand: Dictionary, reason: StringName) -> void:
		_dropped["%s/%d" % [agent, errand["record"]]] = String(reason)
		events.append(["dropped", agent, errand["record"], reason])

	func _eat(id: StringName) -> void:
		if needs[id].pressure(&"food") < 0.5:
			return
		for row: Dictionary in society.ports.property.items_of(id):
			needs[id].relieve(&"food", float(row["relieves"].get("food", 0.0)) * 2.0)
			society.ports.property.remove(StringName(row["id"]))
			return

	func _bake(owner_id: StringName, place: StringName, count: int, relief: float, minute: int) -> void:
		for i in count:
			society.ports.property.register(StringName("%s_%d_%d" % [owner_id, minute, i]), owner_id, place, {&"food": relief})
			baked += 1

	func _personality_of(id: StringName) -> BustlePersonality:
		return people.get(id)

	func _needs_of(id: StringName) -> BustleNeedSet:
		return needs.get(id)

	func _memory_of(id: StringName) -> BustleMemory:
		return memories.get(id)

	# A witness grows more afraid of a thief each time it has seen it steal before.
	func _fear_of(witness: StringName, thief: StringName) -> float:
		var seen := -1
		for row: Dictionary in watch.records():
			if row["thief"] == String(thief) and (row["witnesses"] as Array).has(String(witness)):
				seen += 1
		return 50.0 + 20.0 * seen

	func _on_decided(agent: StringName, outcome: StringName, row: Dictionary) -> void:
		events.append(["decided", agent, outcome, row["id"]])
		var expected := {"id": row["id"], "item": row["item"], "owner_id": row["owner_id"], "place": row["place"],
			"at": row["at"], "thief": "" if row["deed"] else row["thief"], "outcome": String(outcome)}
		if not watch.question(agent, int(row["found_at"]) if row["deed"] else int(row["at"])).has(expected):
			problems.append("%s can't be questioned about record %d" % [agent, row["id"]])

	func _thief_sees_someone(thief: StringName, place: StringName) -> bool:
		for other: StringName in society.agent_ids():
			if other != thief and other != HIDDEN and society.get_agent(other).area == place:
				return true
		return false

	func _on_witnessed(witness: StringName, thief: StringName, item: StringName, row: Dictionary) -> void:
		if society.get_agent(witness).area != StringName(row["place"]) or witness == thief:
			problems.append("%s witnessed %s without perceiving it" % [witness, item])
		events.append(["witnessed", witness, thief, item])

	func _on_reported(reporter: StringName, role: StringName, report: Dictionary) -> void:
		var authority := StringName(report["authority"])
		if authority != society.ports.roles.holder_of(role) or society.get_agent(reporter).area != society.get_agent(authority).area:
			problems.append("%s reported record %d without reaching the warden" % [reporter, report["id"]])
		if _dropped.has("%s/%d" % [reporter, report["id"]]):
			problems.append("%s reported record %d after giving it up" % [reporter, report["id"]])
		events.append(["reported", reporter, role, report["thief"], report["authority"], report["source"], report["reported_at"]])

	func _on_found(finder: StringName, item: StringName, _row: Dictionary) -> void:
		events.append(["found", finder, item])

	func _add(id: StringName, sliders: Dictionary, route: Array) -> void:
		society.add_agent(id, &"villager")
		var food := BustleNeedDef.new()
		food.id = &"food"
		var need_set := BustleNeedSet.new()
		need_set.add_need(food)
		needs[id] = need_set
		memories[id] = BustleMemory.new()
		var p := BustlePersonality.new()
		for slider: String in sliders:
			p.set_slider(StringName(slider), sliders[slider])
		people[id] = p
		_routes[id] = route

	# Hour of day → place, from {start hour: place}; before the first start, the last place.
	func _hours(starts: Dictionary) -> Array:
		var out := []
		var keys: Array = starts.keys()
		keys.sort()
		var current: String = starts[keys[-1]]
		for hour in 24:
			if starts.has(hour):
				current = starts[hour]
			out.append(current)
		return out


func test_thirty_days_of_theft_all_accounted_for() -> void:
	var village := Village.new()
	village.run()
	var records := village.watch.records()
	var thefts := village.events.filter(func(e: Array) -> bool: return e[0] == "theft")
	var witnessed := records.filter(func(r: Dictionary) -> bool: return not r["deed"])
	var deeds := records.filter(func(r: Dictionary) -> bool: return r["deed"])
	gut.p("30 days: %d baked, %d thefts, %d witnessed, %d deeds" % [village.baked, thefts.size(), witnessed.size(), deeds.size()])
	assert_eq(village.problems, [] as Array[String])
	assert_gt(witnessed.size(), 0, "some thefts were seen")
	assert_gt(deeds.size(), 0, "and some weren't")
	assert_eq(records.size(), thefts.size(), "every theft has a record")
	assert_true(thefts.all(func(e: Array) -> bool: return not String(e[2]).is_empty()), "every attempt that passed the guards took something")
	var pending := {}
	for errand: Dictionary in village.watch.export_state()["errands"]:
		pending["%s/%d" % [errand["agent"], errand["record"]]] = true
	var reports := village.events.filter(func(e: Array) -> bool: return e[0] == "reported")
	var reasons := village._dropped.values()
	gut.p("%d reports delivered, %d forgotten, %d intimidated, %d still on their way" % [reports.size(), reasons.count("forgot"), reasons.count("intimidated"), pending.size()])
	assert_gt(reports.size(), 0, "reports arrive")
	assert_gt(reasons.count("forgot"), 0, "some are forgotten while the warden is away")
	assert_true(reports.all(func(e: Array) -> bool: return e[6] < AWAY[0] * 1440 or e[6] >= AWAY[1] * 1440), "none while the role is vacant")
	assert_true(reports.all(func(e: Array) -> bool: var h: int = (int(e[6]) % 1440) / 60; return h >= 6 and h < 22), "nobody delivers at night")
	for row: Dictionary in records:
		if row["deed"]:
			assert_eq(row["witnesses"], [], "a deed has no witnesses")
			if int(row["found_at"]) >= 0:
				assert_eq([row["known_by"], row["decisions"]], [[row["owner_id"]], {row["owner_id"]: "report"}], "its owner found it and, honest and bold, set out to report it")
			else:
				assert_gt(int(row["at"]), (DAYS - 1) * 1440, "only a deed of the last day is still unfound: %s" % [row])
		else:
			assert_eq(row["witnesses"], [String(HIDDEN)], "only the one the thief missed could see it")
			assert_eq([row["known_by"], (row["decisions"] as Dictionary).keys()], [row["witnesses"], row["witnesses"]], "each witness knows and decides")
		for agent: String in row["decisions"]:
			var key := "%s/%d" % [agent, row["id"]]
			var fates := [(row["reporters"] as Array).has(agent), village._dropped.has(key), pending.has(key)].count(true)
			assert_eq(fates, 1 if row["decisions"][agent] == "report" else 0, "%s on record %d: reported, given up or still on its way, once" % [agent, row["id"]])
	var choices: Array = witnessed.map(func(r: Dictionary) -> String: return r["decisions"][String(HIDDEN)])
	assert_eq(choices[0], "report", "the first time, the witness reports")
	assert_true(choices.slice(1).all(func(c: String) -> bool: return c == "silent"), "afraid of the thief after that, it keeps quiet: %s" % [choices])
	assert_true(reports.all(func(e: Array) -> bool: return e[2] == BustleCrimeWatch.AUTHORITY and e[4] == "warden"), "reports go to the authority role")
	assert_true(reports.filter(func(e: Array) -> bool: return e[1] == HIDDEN).all(func(e: Array) -> bool: return not String(e[3]).is_empty()), "a witness names the thief")
	assert_true(reports.filter(func(e: Array) -> bool: return e[1] != HIDDEN).all(func(e: Array) -> bool: return String(e[3]).is_empty()), "an owner can't")
	assert_false(thefts.any(func(e: Array) -> bool: return e[1] in [&"baker", &"cook", &"warden"]), "the honest never steal")
	var copy := BustleCrimeWatch.new(BustleCrime.new())
	assert_true(copy.import_state(village.watch.export_state()))
	assert_eq(copy.export_state(), village.watch.export_state(), "thirty days of records save and load")
	var again := Village.new()
	again.run()
	assert_eq(again.events, village.events, "the same village runs the same way twice")
	assert_eq(again.watch.export_state(), village.watch.export_state())
