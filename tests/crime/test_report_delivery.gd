# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## A report counts only when the witness reaches the authority face to face. Until then the errand
## waits for someone to hold the role, can be forgotten or dropped under intimidation (the memory
## stays), and others can hear of it second-hand. Instant reports are a developer option, off by
## default.

var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _people: Dictionary[StringName, BustlePersonality] = {}
var _memories: Dictionary[StringName, BustleMemory] = {}
var _events: Array = []


func before_each() -> void:
	_society = BustleSociety.new(4)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_crime = BustleCrime.new(_society)
	var hunger := BustleNeedSet.new()
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = 1.0
	hunger.add_need(food)
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return hunger if id == &"drifter" else null
	_crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	_watch = BustleCrimeWatch.new(_crime)
	_people = {}
	_memories = {}
	_watch.judge.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_watch.memory_of = func(id: StringName) -> BustleMemory: return _memories.get(id)
	_events = []
	for name: String in ["crime_reported", "victim_told", "gossiped", "errand_dropped", "decided"]:
		_watch.connect(name, _on_event.bind(name))
	for row: Array in [[&"drifter", &"market"], [&"witness", &"market"], [&"warden", &"hall"], [&"baker", &"bakery"]]:
		_society.add_agent(row[0], &"villager").area = row[1]
		_memories[row[0]] = BustleMemory.new()
	_society.ports.world.set_place(&"hall", Vector3(40, 0, 0))
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")
	_honest(&"witness")
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})


func after_each() -> void:
	ProjectSettings.set_setting(BustleCrimeWatch.INSTANT_SETTING, null)


func test_a_report_counts_only_on_arrival() -> void:
	_steal(10)
	assert_eq(_names(), ["decided"], "it decides to report, but nothing is reported yet")
	var errand := _watch.errands_of(&"witness")[0]
	assert_eq([errand["kind"], errand["target"], errand["source"], errand["knows_thief"], errand["since"]], ["report", "warden", "eyewitness", true, 10])
	assert_eq(_inputs(&"witness", 11), {BustleCrimeWatch.INPUT: 1.0})
	assert_eq(_watch.deliver(&"witness", 11), {"state": &"travelling", "target": &"warden"})
	assert_eq(_names(), ["decided"])
	_society.get_agent(&"witness").area = &"hall"
	assert_eq(_watch.deliver(&"witness", 40), {"state": &"delivered", "target": &"warden"})
	assert_eq(_names(), ["decided", "crime_reported"])
	var report: Dictionary = _events[-1][2]
	assert_eq([report["thief"], report["authority"], report["source"], report["reported_at"]], ["drifter", "warden", "eyewitness", 40])
	assert_eq([_watch.errands_of(&"witness"), _inputs(&"witness", 41)], [[], {}])
	assert_eq(_watch.deliver(&"witness", 42)["state"], &"none")


func test_face_to_face_counts_at_once_and_a_vacant_role_waits() -> void:
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"")
	_steal(10)
	assert_eq(_watch.deliver(&"witness", 11)["state"], &"waiting", "nobody holds the role")
	assert_eq([_inputs(&"witness", 11), _watch.errands_of(&"witness").size()], [{}, 1], "so it doesn't set out, but keeps the errand")
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"drifter")
	assert_eq(_watch.deliver(&"witness", 20), {"state": &"delivered", "target": &"drifter"}, "already face to face with the holder")
	assert_eq(_events[-1][2]["authority"], "drifter")


func test_a_waiting_report_never_holds_up_the_next_errand() -> void:
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"")
	_steal(10)
	_watch.judge.standing_of = func(_w: StringName) -> float: return 0.0
	_society.ports.property.register(&"bun", &"baker", &"market", {&"food": 0.3})
	_steal(20)
	assert_eq(_watch.errands_of(&"witness").map(func(e: Dictionary) -> Array: return [e["kind"], e["record"], e["target"]]),
		[["report", 1, ""], ["tell_victim", 2, "baker"]], "a report waiting on the empty role, then word for the victim")
	var brain := _brain()
	var intent := _tick(brain, 21)
	assert_eq([intent.goal_id, intent.talk_to], [&"deliver", &"baker"], "it sets out with the errand it can do")
	_society.get_agent(&"witness").area = &"bakery"
	_tick(brain, 40)
	assert_eq(_names().count("victim_told"), 1, "and delivers it")
	assert_eq(_watch.errands_of(&"witness").map(func(e: Dictionary) -> String: return e["kind"]), ["report"])
	assert_eq(_watch.deliver(&"witness", 41), {"state": &"waiting", "target": &""})
	assert_eq([_inputs(&"witness", 42), _tick(brain, 42).goal_id], [{}, &"work"], "with only the waiting report left, it goes back to work")
	assert_eq(_names().count("crime_reported"), 0)
	var later := 10 + 15 * 1440
	_watch.judge.standing_of = Callable()
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")
	_society.ports.property.register(&"cake", &"baker", &"market", {&"food": 0.2})
	_society.get_agent(&"witness").area = &"market"
	_steal(later)
	_society.get_agent(&"witness").area = &"hall"
	assert_eq(_watch.deliver(&"witness", later)["state"], &"forgot", "the old report, faded while it waited, is dropped first")
	assert_eq(_watch.deliver(&"witness", later), {"state": &"delivered", "target": &"warden"}, "then the fresh one is delivered")
	assert_eq([_names().count("crime_reported"), _events[-1][2]["item"]], [1, "cake"])
	assert_eq(_watch.errands_of(&"witness"), [] as Array[Dictionary])


func test_a_forgotten_errand_reports_nothing() -> void:
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"")
	_steal(10)
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")
	_society.get_agent(&"witness").area = &"hall"
	assert_eq(_watch.deliver(&"witness", 10 + 15 * 1440)["state"], &"forgot", "two weeks waiting, and it has forgotten")
	assert_eq(_names(), ["decided", "errand_dropped"])
	assert_eq(_events[-1][2], &"forgot")
	assert_eq(_watch.errands_of(&"witness"), [] as Array[Dictionary])


func test_intimidation_drops_the_errand_but_not_the_memory() -> void:
	_steal(10)
	assert_eq(_watch.intimidate(&"cooper", &"witness", 11), 0, "only the thief's own thefts")
	assert_eq(_watch.intimidate(&"drifter", &"witness", 11), 1)
	assert_eq([_names(), _events[-1][2]], [["decided", "errand_dropped"], &"intimidated"])
	assert_eq([_watch.errands_of(&"witness"), _watch.deliver(&"witness", 12)["state"]], [[], &"none"], "no report on its way")
	assert_false(_memories[&"witness"].recall(BustleMemory.ITEM, &"loaf", 12).is_empty(), "it still remembers")
	assert_eq(_watch.question(&"witness", 12)[0]["thief"], "drifter")
	_watch.judge.fear_of = func(_w: StringName, _t: StringName) -> float: return 100.0
	assert_eq(_watch.reconsider(&"witness", 1, 20), &"silent", "afraid now, it keeps quiet")
	_watch.judge.fear_of = Callable()
	assert_eq(_watch.reconsider(&"witness", 1, 30), &"report", "with the fear gone, it sets out again")
	assert_eq(_watch.reconsider(&"witness", 1, 31), &"", "not while that errand is on")
	assert_eq(_watch.reconsider(&"warden", 1, 31), &"", "nor about what it doesn't know")
	assert_eq(_watch.errands_of(&"witness").size(), 1)


func test_word_passed_on_is_second_hand() -> void:
	_watch.judge.standing_of = func(w: StringName) -> float: return 0.0 if w == &"witness" else 50.0
	_honest(&"baker")
	_steal(10)
	assert_eq(_watch.errands_of(&"witness")[0]["target"], "baker", "it distrusts the authority, so it goes to the victim")
	_society.get_agent(&"witness").area = &"bakery"
	assert_eq(_watch.deliver(&"witness", 30)["state"], &"delivered")
	assert_eq(_events[-2].slice(0, 2) + [_events[-2][3]], [&"witness", &"baker", "victim_told"])
	var errand := _watch.errands_of(&"baker")[0]
	assert_eq([errand["kind"], errand["source"], errand["knows_thief"]], ["report", "secondhand", true], "the victim heard who, and reports it")
	_society.get_agent(&"baker").area = &"hall"
	_watch.deliver(&"baker", 60)
	assert_eq([_events[-1][0], _events[-1][2]["source"], _events[-1][2]["thief"]], [&"baker", "secondhand", "drifter"])
	assert_eq(_watch.record(1)["known_by"], ["witness", "baker"])
	_watch.gossip_to = func(_a: StringName, _r: Dictionary) -> StringName: return &"warden"
	_people[&"witness"].set_slider(&"sociability", 100.0)
	_society.get_agent(&"witness").area = &"market"
	_society.ports.property.register(&"bun", &"baker", &"market", {&"food": 0.3})
	_society.ports.property.remove(&"loaf")
	_steal(100)
	assert_eq(_watch.errands_of(&"witness")[0]["kind"], "gossip")
	_society.get_agent(&"witness").area = &"hall"
	_watch.deliver(&"witness", 120)
	assert_eq(_watch.record(2)["known_by"], ["witness", "warden"], "the authority heard it as gossip")
	assert_eq(_watch.record(2)["decisions"]["warden"], "silent", "and decided by its own lights (neutral: silent)")


func test_instant_reports_are_a_developer_option_off_by_default() -> void:
	assert_false(BustleCrimeWatch.new(BustleCrime.new()).instant)
	ProjectSettings.set_setting(BustleCrimeWatch.INSTANT_SETTING, true)
	assert_true(BustleCrimeWatch.new(BustleCrime.new()).instant)
	_watch.instant = true
	_steal(10)
	assert_eq(_names(), ["decided", "crime_reported"], "delivered the moment it's decided")
	assert_eq(_watch.errands_of(&"witness"), [] as Array[Dictionary])


func test_a_brain_delivers_in_the_guarded_band() -> void:
	var brain := _brain()
	_steal(10)
	var night := [true]
	_watch.can_travel = func(_a: StringName, _now: int) -> bool: return not night[0]
	assert_eq(_tick(brain, 11).goal_id, &"work", "at night it waits")
	night[0] = false
	var intent := _tick(brain, 12)
	assert_eq([intent.goal_id, intent.band, intent.move_to, intent.talk_to, intent.gear], [&"deliver", BustleBands.GUARDED, Vector3(40, 0, 0), &"warden", &"hurry"],
		"by day it hurries to the authority, ahead of its work")
	assert_true(_names().count("crime_reported") == 0)
	_society.get_agent(&"witness").area = &"hall"
	_tick(brain, 40)
	assert_eq(_names().count("crime_reported"), 1)
	assert_eq(_tick(brain, 41).goal_id, &"work", "word delivered, back to work")


func _brain() -> BustleBrain:
	var library := BustleGoalLibrary.new()
	var work := BustleGoalDef.new()
	work.id = &"work"
	work.band = BustleBands.DUTY
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 60}
	work.sequence = BustleActionSequence.new()
	work.sequence.steps.append(step)
	library.goals = [work] as Array[BustleGoalDef]
	library.goals.append_array(BustleCrimeWatch.goal_defs())
	var brain := BustleBrain.new(&"witness", library, BustleScoringConfig.new(), 3)
	var runner := BustleSequenceRunner.new()
	runner.register(&"deliver", BustleDeliverAction.new(_watch))
	brain.runner.share_handlers_with(runner)
	return brain


func _tick(brain: BustleBrain, now: int) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	_watch.fill_inputs(&"witness", senses.inputs, now)
	return brain.tick(0.1, senses)


func _steal(now: int) -> void:
	for row: Dictionary in _society.ports.property.items_of(&"drifter"):
		_society.ports.property.remove(StringName(row["id"]))
	_crime.consider(&"drifter", now)
	assert_true(_crime.steal(&"drifter", now)["ok"])


func _honest(id: StringName) -> void:
	_people[id] = BustlePersonality.new()
	_people[id].set_slider(&"honesty", 100.0)


func _inputs(agent: StringName, now: int) -> Dictionary[StringName, float]:
	var inputs: Dictionary[StringName, float] = {}
	_watch.fill_inputs(agent, inputs, now)
	return inputs


func _names() -> Array:
	return _events.map(func(e: Array) -> String: return e[-1])


func _on_event(a: Variant, b: Variant, c: Variant, name: String = "") -> void:
	_events.append([a, b, c, name])
