# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Locks: a host pins an agent's place, goal or both; the agent holds there until the last lock is
## released, only danger (and self-care that keeps to the place) gets in the way, other orders wait,
## crime and mental states read the same lock, protection follows it, and it all saves.

var _society: BustleSociety


func before_each() -> void:
	_society = BustleSociety.new(5)
	var library := BustleGoalLibrary.new()
	library.goals = [_goal(&"work", BustleBands.DUTY, "work"), _goal(&"tend", BustleBands.PERSONAL, "tend"),
		_goal(&"flee", BustleBands.CRITICAL, "flee", "fact.danger"), _goal(&"errand", BustleBands.GUARDED, "errand", "fact.errand"),
		_goal(&"eat", BustleBands.URGENT, "eat", "", true)] as Array[BustleGoalDef]
	_society.register_archetype(&"agent", library)
	_society.ports.world.set_place(&"spot", Vector3(10, 0, 0))
	_society.ports.world.set_place(&"other", Vector3(-10, 0, 0))
	for id: StringName in [&"a", &"b"]:
		_society.add_agent(id, &"agent").area = &"field"


func test_pin_a_place_a_goal_or_both() -> void:
	assert_eq(_tick(&"a", 0).goal_id, &"work", "unlocked, it works")
	assert_true(_society.lock(&"a", BustleLock.make(&"x", &"spot")))
	var intent := _tick(&"a", 1)
	assert_eq([intent.order_id, intent.band, intent.has_move_to, intent.move_to, intent.action],
		[&"lock/a", BustleBands.ORDERED, true, Vector3(10, 0, 0), &"hold"], "a place: it goes there and holds, not forced")
	assert_eq(_tick(&"a", 600).order_id, &"lock/a", "and keeps holding, hours later")
	assert_true(_society.lock(&"b", BustleLock.make(&"x", &"", &"tend")))
	intent = _tick(&"b", 1)
	assert_eq([intent.order_id, intent.animation, intent.has_move_to], [&"lock/b", &"tend", false], "a goal: it runs that goal")
	_tick(&"b", 40)
	assert_eq(_tick(&"b", 41).action, &"hold", "and holds once it's done")
	_society.lock(&"b", BustleLock.make(&"y", &"spot", &"tend"))
	intent = _tick(&"b", 42)
	assert_eq([intent.animation, intent.move_to], [&"tend", Vector3(10, 0, 0)], "both: the goal, at the place")
	assert_eq(_society.lock(&"zz", BustleLock.make(&"x", &"spot")), false, "nobody to lock")
	assert_false(_society.lock(&"a", BustleLock.make(&"empty")), "a lock that pins nothing")


func test_locks_stack_unlock_one_at_a_time_and_replace_by_id() -> void:
	_society.lock(&"a", BustleLock.make(&"place", &"spot"))
	_society.lock(&"a", BustleLock.make(&"task", &"", &"tend"))
	assert_eq(_society.lock_ids(&"a"), [&"place", &"task"] as Array[StringName])
	var intent := _tick(&"a", 0)
	assert_eq([intent.animation, intent.move_to], [&"tend", Vector3(10, 0, 0)], "two locks: both pins")
	assert_true(_society.unlock(&"a", &"place"))
	intent = _tick(&"a", 1)
	assert_eq([_society.is_locked(&"a"), intent.order_id, intent.has_move_to], [true, &"lock/a", false], "one left: still locked, goal only")
	_society.lock(&"a", BustleLock.make(&"task", &"other"))
	assert_eq(_society.lock_ids(&"a"), [&"task"] as Array[StringName], "the same id replaces that pin")
	intent = _tick(&"a", 2)
	assert_eq([intent.move_to, intent.animation], [Vector3(-10, 0, 0), &""], "now the place, no goal")
	assert_false(_society.unlock(&"a", &"place"), "already released")
	assert_true(_society.unlock(&"a", &"task"))
	assert_eq([_society.is_locked(&"a"), _society.get_agent(&"a").brain.orders.ids(), _tick(&"a", 3).goal_id],
		[false, [] as Array[StringName], &"work"], "the last one released: the order goes, back to work")


func test_only_danger_or_self_care_at_the_place_interrupts_a_lock() -> void:
	_society.lock(&"a", BustleLock.make(&"x", &"spot"))
	assert_eq(_tick(&"a", 0, {&"fact.errand": 1.0}).order_id, &"lock/a", "a guarded goal doesn't displace the pin")
	assert_eq(_tick(&"a", 1, {&"fact.danger": 1.0}).goal_id, &"flee", "danger does")
	assert_eq(_tick(&"a", 2).order_id, &"lock/a", "and the pin resumes once it's gone")
	assert_eq(_tick(&"a", 3, {&"need.food": 1.0}, 50.0).order_id, &"lock/a", "food 50 m away would break the place pin")
	var intent := _tick(&"a", 4, {&"need.food": 1.0}, 2.0)
	assert_eq([intent.goal_id, intent.option_id], [&"eat", &"meal"], "food right there doesn't")
	_society.unlock(&"a", &"x")
	_society.lock(&"a", BustleLock.make(&"x", &"", &"tend"))
	assert_eq(_tick(&"a", 5, {&"need.food": 1.0}, 50.0).goal_id, &"eat", "with no place pinned, self-care may go")
	assert_eq(_tick(&"a", 6).order_id, &"lock/a")


func test_an_order_given_while_locked_waits_and_then_runs() -> void:
	_society.lock(&"a", BustleLock.make(&"x", &"spot"))
	var sequence := BustleActionSequence.new()
	var step := BustleActionStep.new()
	step.action = &"idle"
	step.params = {"style": "fetch", "minutes": 10}
	sequence.steps.append(step)
	assert_eq(_society.order(&"a", BustleOrder.new(&"fetch", sequence)), &"")
	assert_eq(_tick(&"a", 0).order_id, &"lock/a", "the lock stays in front")
	assert_eq(_society.get_agent(&"a").brain.orders.ids(), [&"lock/a", &"fetch"] as Array[StringName])
	_society.unlock(&"a", &"x")
	assert_eq(_society.get_agent(&"a").brain.orders.ids(), [&"fetch"] as Array[StringName], "still there after unlock")
	var intent := _tick(&"a", 1)
	assert_eq([intent.order_id, intent.animation], [&"fetch", &"fetch"], "and then it runs")
	_society.order(&"b", BustleOrder.new(&"fetch", sequence))
	_tick(&"b", 0)
	_society.lock(&"b", BustleLock.make(&"x", &"spot"))
	assert_eq(_society.get_agent(&"b").brain.orders.ids(), [&"lock/b", &"fetch"] as Array[StringName], "a lock goes ahead of a running order")


func test_crime_mental_states_and_ambitions_read_the_lock() -> void:
	var crime := BustleCrime.new(_society)
	var needs := BustleNeedSet.new()
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = 1.0
	needs.add_need(food)
	crime.needs_of = func(_id: StringName) -> BustleNeedSet: return needs
	crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	_society.ports.property.register(&"loaf", &"b", &"field", {&"food": 0.5})
	_society.lock(&"a", BustleLock.make(&"x", &"spot"))
	assert_eq(crime.consider(&"a", 0), {}, "locked: no theft")
	var mental := BustleMentalBehaviour.new(_society)
	var mood := BustleMood.new(null, BustleModifierSet.new())
	mood.start(0)
	mood.mood = 10.0
	assert_eq(mental.update(&"a", 0, mood), {}, "locked: no mental state starts")
	var ambitions := BustleAmbitions.new(&"a", null, _society)
	var greedy := BustlePersonality.new()
	greedy.set_slider(&"greed", 90.0)
	ambitions.update(0, greedy, {"wallet": 0.0})
	assert_eq(ambitions.boost(&"work"), 1.0, "locked: no ambition boost")
	_society.unlock(&"a", &"x")
	assert_eq(crime.consider(&"a", 1)["item"], &"loaf", "released: the same guards pass")
	assert_eq(mental.update(&"a", 1, mood)["id"], "withdraw", "and a state can start")
	assert_eq(ambitions.boost(&"work"), 1.5)


func test_protection_follows_its_level() -> void:
	assert_false(_society.is_protected(&"a"), "NONE by default")
	_society.lock(&"a", BustleLock.make(&"x", &"spot"))
	assert_false(_society.is_protected(&"a"), "NONE, even locked")
	_society.set_protection(&"b", BustleLock.Protection.ESSENTIAL)
	assert_true(_society.is_protected(&"b"), "ESSENTIAL, always")
	assert_true(_society.set_protection(&"a", BustleLock.Protection.QUEST_LOCKED))
	assert_true(_society.is_protected(&"a"), "QUEST_LOCKED while a lock is held")
	_society.unlock(&"a", &"x")
	assert_false(_society.is_protected(&"a"), "and not after")
	assert_false(_society.set_protection(&"a", 7))


func test_locks_save_and_load() -> void:
	var sequence := BustleActionSequence.new()
	var step := BustleActionStep.new()
	step.action = &"idle"
	step.params = {"style": "sweep", "minutes": 5}
	sequence.steps.append(step)
	_society.lock(&"a", BustleLock.make(&"x", &"spot"))
	_society.lock(&"a", BustleLock.make(&"y", &"", &"", sequence))
	_society.set_protection(&"a", BustleLock.Protection.QUEST_LOCKED)
	var saved := _society.export_state()
	var copy := BustleSociety.new(5)
	copy.register_archetype(&"agent", _society._archetypes[&"agent"][0])
	copy.ports.world.set_place(&"spot", Vector3(10, 0, 0))
	assert_true(copy.import_state(JSON.parse_string(JSON.stringify(saved))).ok)
	assert_eq([copy.lock_ids(&"a"), copy.is_locked(&"b"), copy.is_protected(&"a")], [[&"x", &"y"] as Array[StringName], false, true])
	assert_eq(copy.state_hash(), _society.state_hash(), "the same state")
	var intent := copy.get_agent(&"a").brain.tick(0.1, _senses(0))
	assert_eq([intent.order_id, intent.animation, intent.move_to], [&"lock/a", &"sweep", Vector3(10, 0, 0)], "and the pins hold again")
	for bad: Variant in [{"b": []}, {"nobody": [{"lock_id": "x", "place": "spot", "goal": "", "steps": null}]},
			{"a": [{"lock_id": "x", "place": "", "goal": "", "steps": null}]}, {"a": [{"lock_id": "x", "place": "spot", "goal": "", "steps": 3}]}]:
		var broken: Dictionary = saved.duplicate(true)
		broken["locks"] = bad
		assert_false(copy.import_state(broken).ok, "refuses %s" % [bad])
	assert_eq(copy.state_hash(), _society.state_hash(), "a refused load changes nothing")


func _tick(id: StringName, now: int, inputs: Dictionary = {}, food_at: float = -1.0) -> BustleIntent:
	var senses := _senses(now)
	for key: StringName in inputs:
		senses.inputs[key] = inputs[key]
	if food_at >= 0.0:
		var ad := BustleAdvertisement.new(&"meal", {&"food": 1.0} as Dictionary[StringName, float])
		ad.distance = food_at
		senses.advertisements.append(ad)
	return _society.get_agent(id).brain.tick(0.1, senses)


func _senses(now: int) -> BustleSenses:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	return senses


func _goal(id: StringName, band: int, style: String, needs_input: String = "", ads: bool = false) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.uses_advertisements = ads
	if needs_input != "":
		goal.preconditions = [{"kind": "input", "input": needs_input}] as Array[Dictionary]
	var step := BustleActionStep.new()
	step.action = &"idle"
	step.params = {"style": style, "minutes": 30}
	goal.sequence = BustleActionSequence.new()
	goal.sequence.steps.append(step)
	return goal
