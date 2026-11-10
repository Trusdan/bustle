# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## What agents do in a mental state: its modifiers, its goals in the guarded band, lashing out at
## the most disliked person nearby (once each, words only, any fight through the usual rules),
## locks holding it all off, and friends still coming to comfort someone in a low state.

var _society: BustleSociety
var _store: BustleSocialStore
var _behaviour: BustleMentalBehaviour
var _people: Dictionary[StringName, BustlePersonality] = {}
var _moods: Dictionary[StringName, BustleMood] = {}
var _places: Dictionary[StringName, Vector3] = {}
var _locked: Dictionary[StringName, bool] = {}
var _insults: Array = []


func before_each() -> void:
	_society = BustleSociety.new(6)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_store = BustleSocialStore.new()
	_society.set_port(&"social", _store)
	_behaviour = BustleMentalBehaviour.new(_society)
	_behaviour.is_locked = func(id: StringName) -> bool: return _locked.get(id, false)
	_behaviour.position_of = func(id: StringName) -> Variant: return _places.get(id)
	_behaviour.insulted.connect(func(a: StringName, t: StringName, p: float) -> void: _insults.append([a, t, p]))
	_people = {}
	_moods = {}
	_places = {}
	_locked = {}
	_insults = []
	for row: Array in [[&"agent", &"market", Vector3.ZERO], [&"foe", &"market", Vector3(5, 0, 0)],
			[&"rival", &"market", Vector3(10, 0, 0)], [&"distant", &"market", Vector3(80, 0, 0)],
			[&"elsewhere", &"farm", Vector3(3, 0, 0)], [&"friend", &"market", Vector3(1, 0, 0)]]:
		_society.add_agent(row[0], &"villager").area = row[1]
		_places[row[0]] = row[2]
		_moods[row[0]] = _mood(50.0)
	for other: StringName in [&"foe", &"distant", &"elsewhere"]:
		_store.add_opinion(&"agent", other, -40.0, {}, 30.0)
	_store.add_opinion(&"agent", &"rival", 10.0, {}, 30.0)
	_store.set_kind(&"agent", &"rival", &"rival")
	_store.set_kind(&"agent", &"friend", &"friend")
	_store.set_kind(&"friend", &"agent", &"friend")


func test_each_state_sets_its_modifiers_while_it_lasts() -> void:
	var mods := _moods[&"agent"].modifiers
	for other: StringName in [&"foe", &"rival"]:
		_places[other] = Vector3(500, 0, 0)
	for row: Array in [[{&"sociability": 10.0}, 20.0, &"withdraw", &"tag.social.mult", 0.2],
			[{&"temper": 70.0, &"sociability": 40.0}, 20.0, &"sulk", &"work.speed", 0.75],
			[{&"diligence": 80.0}, 95.0, &"inspired", &"work.speed", 1.25],
			[{}, 85.0, &"high_spirits", &"social.generosity", 1.0]]:
		_people[&"agent"] = _person(row[0])
		_moods[&"agent"].mood = row[1]
		assert_eq(_update(&"agent", 0)["id"], String(row[2]))
		assert_almost_eq(mods.value(row[3], 0.0 if row[3] == &"social.generosity" else 1.0), row[4], 0.001, "%s sets %s" % [row[2], row[3]])
		_update(&"agent", 2000)
		assert_false(mods.has(row[3]), "and takes it off when it ends")


func test_lash_out_picks_the_most_disliked_person_nearby_once_each() -> void:
	_people[&"agent"] = _person({&"temper": 100.0})
	_moods[&"agent"].mood = 20.0
	assert_eq(_behaviour.lash_target(&"agent"), &"rival", "a rival first, though not disliked")
	assert_eq(_update(&"agent", 0)["id"], "lash_out")
	assert_true(_behaviour.insult(&"agent", &"rival", 1))
	assert_false(_behaviour.insult(&"agent", &"rival", 2), "once per person an episode")
	assert_eq(_behaviour.lash_target(&"agent"), &"foe", "then the most disliked one within a short walk")
	_behaviour.insult(&"agent", &"foe", 3)
	assert_eq(_behaviour.lash_target(&"agent"), &"", "not the one 80 m off, not the one in another area, not a friend")
	assert_eq(_inputs(&"agent"), {}, "nobody left to lash out at")
	assert_eq(_insults.map(func(i: Array) -> StringName: return i[1]), [&"rival", &"foe"])
	_update(&"agent", 12 * 60)
	_update(&"agent", 12 * 60 + 1)
	assert_eq(_behaviour.lash_target(&"agent"), &"rival", "a new episode starts afresh")
	_places[&"rival"] = Vector3(100, 0, 0)
	_places[&"foe"] = Vector3(100, 0, 0)
	_update(&"agent", 24 * 60 + 2)
	_update(&"agent", 24 * 60 + 3)
	assert_eq(_behaviour.state_of(&"agent").active()["id"], "sulk", "nobody near: lash out isn't eligible, and sulking is next")


func test_an_insult_goes_through_the_fight_rules_and_never_means_to_kill() -> void:
	var conflict := BustleConflict.new(BustleDispositionPort.new(), BustleCombatPort.new(), BustleConflictConfig.new())
	conflict.social = _store
	conflict.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_behaviour.conflict = conflict
	_people[&"agent"] = _person({&"temper": 100.0})
	_people[&"rival"] = _person({&"temper": 100.0})
	_moods[&"agent"].mood = 3.0
	assert_eq(_update(&"agent", 0)["tier"], "extreme")
	_behaviour.insult(&"agent", &"rival", 1)
	assert_eq(_insults[0], [&"agent", &"rival", 0.6], "an extreme episode provokes hardest")
	assert_eq(conflict.threat_of(&"rival"), &"agent", "a hot-tempered target comes to blows through the quarrel rules")
	for id: StringName in [&"agent", &"rival"]:
		assert_ne(conflict.intent_of(id), BustleConflict.KILL, "%s never means to kill" % id)
	_people[&"foe"] = _person({&"temper": 0.0})
	_behaviour.insult(&"agent", &"foe", 2)
	assert_eq(conflict.threat_of(&"foe"), &"", "a calm one shrugs it off")


func test_a_brain_acts_states_out_in_the_guarded_band_unless_locked() -> void:
	var library := BustleGoalLibrary.new()
	var work := BustleGoalDef.new()
	work.id = &"work"
	work.band = BustleBands.ORDERED
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 60}
	work.sequence = BustleActionSequence.new()
	work.sequence.steps.append(step)
	library.goals = [work] as Array[BustleGoalDef]
	library.goals.append_array(BustleMentalBehaviour.goal_defs())
	var brain := BustleBrain.new(&"agent", library, BustleScoringConfig.new(), 1)
	var runner := BustleSequenceRunner.new()
	runner.register(&"mental", BustleMentalAction.new(_behaviour))
	brain.runner.share_handlers_with(runner)
	_behaviour.home_of = func(_id: StringName) -> Vector3: return Vector3(0, 0, 50)
	_behaviour.indulgence_of = func(_id: StringName) -> StringName: return &"bench"
	_people[&"agent"] = _person({&"sociability": 0.0})
	_moods[&"agent"].mood = 20.0
	_update(&"agent", 0)
	var intent := _tick(brain, 1)
	assert_eq([intent.goal_id, intent.band, intent.move_to], [&"mental_withdraw", BustleBands.GUARDED, Vector3(0, 0, 50)], "withdraw goes home, ahead of orders")
	_locked[&"agent"] = true
	_update(&"agent", 2)
	assert_eq([_tick(brain, 2).goal_id, _moods[&"agent"].modifiers.has(&"tag.social.mult")], [&"work", false], "locked: the task wins and the modifiers are off")
	_moods[&"agent"].mood = 50.0
	_update(&"agent", 9 * 60)
	_moods[&"agent"].mood = 20.0
	_people[&"agent"] = _person({&"greed": 100.0})
	assert_eq(_update(&"agent", 9 * 60 + 1), {}, "and no new state starts while locked")
	_locked[&"agent"] = false
	assert_eq(_update(&"agent", 9 * 60 + 2)["id"], "binge", "when the lock ends, it's evaluated again")
	intent = _tick(brain, 9 * 60 + 3)
	assert_eq([intent.goal_id, intent.use_affordance], [&"mental_binge", &"bench"], "binge goes to the indulgence it knows")


func test_a_friend_in_a_low_state_still_gets_comforted() -> void:
	var comfort := BustleComfort.new()
	var mood_of := func(id: StringName) -> Object: return _moods.get(id)
	_people[&"agent"] = _person({&"sociability": 0.0})
	_moods[&"agent"].mood = 20.0
	_update(&"agent", 0)
	_moods[&"agent"].mood = 35.0
	var senses := BustleSenses.new()
	assert_eq(comfort.advertise(&"friend", [&"agent"] as Array[StringName], _store, mood_of, senses), 0, "mood alone: 35 isn't low")
	comfort.low_state_of = _behaviour.in_low_state
	assert_eq(comfort.advertise(&"friend", [&"agent"] as Array[StringName], _store, mood_of, senses), 1, "but it's still in its low state")
	assert_eq(senses.advertisements[0].relief, {&"comfort": 0.5} as Dictionary[StringName, float])
	assert_eq(comfort.advertise(&"foe", [&"agent"] as Array[StringName], _store, mood_of, BustleSenses.new()), 0, "only friends come")


func test_states_and_insults_save_and_load() -> void:
	_people[&"agent"] = _person({&"temper": 100.0})
	_moods[&"agent"].mood = 20.0
	_update(&"agent", 0)
	_behaviour.insult(&"agent", &"rival", 1)
	var saved := _behaviour.export_state()
	var copy := BustleMentalBehaviour.new(_society)
	copy.position_of = _behaviour.position_of
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), saved)
	assert_eq(copy.lash_target(&"agent"), &"foe", "the insult is remembered")
	for bad: Variant in [null, {"states": {}}, {"states": {"agent": {"active": {"id": "brood"}}}, "insulted": {}},
			{"states": {}, "insulted": {"agent": {"rival": 0}}}]:
		assert_false(copy.import_state(bad), "refuses %s" % [bad])
	assert_eq(copy.export_state(), saved)


func _update(id: StringName, now: int) -> Dictionary:
	return _behaviour.update(id, now, _moods[id], _people.get(id))


func _inputs(id: StringName) -> Dictionary[StringName, float]:
	var inputs: Dictionary[StringName, float] = {}
	_behaviour.fill_inputs(id, inputs)
	return inputs


func _tick(brain: BustleBrain, now: int) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	_behaviour.fill_inputs(&"agent", senses.inputs)
	return brain.tick(0.1, senses)


func _mood(value: float) -> BustleMood:
	var mood := BustleMood.new(null, BustleModifierSet.new())
	mood.start(0)
	mood.mood = value
	return mood


func _person(sliders: Dictionary) -> BustlePersonality:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	return p
