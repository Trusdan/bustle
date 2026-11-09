# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Conversations: the same results visible (one turn per tick) or abstract (all at once), weights
## from sliders, traits, opinion and mood, a low mood lowering the chance to start, openers, the
## converse action's failures, the neutral demo set, and the comfort hook.

const DEMO := "res://demo/social/%s.tres"
const MENU: Array[StringName] = [&"chitchat", &"deep_talk", &"kind_words", &"slight", &"insult", &"comfort"]


class FakeMood:
	extends RefCounted
	var mood: float = 50.0
	var thoughts: Array[Dictionary] = []

	func _init(p_mood: float) -> void:
		mood = p_mood

	func add_thought(def: Resource, reason: Dictionary) -> void:
		thoughts.append({"def": def, "reason": reason})


var _moods: Dictionary[StringName, FakeMood] = {}
var _people: Dictionary[StringName, BustlePersonality] = {}


func before_each() -> void:
	_moods = {}
	_people = {}


func test_visible_and_abstract_conversations_give_the_same_results() -> void:
	for setup: Array in [[3, &"baker", &"smith", 600], [11, &"smith", &"miller", 1000], [42, &"miller", &"baker", 75]]:
		_moods = {&"baker": FakeMood.new(20.0), &"smith": FakeMood.new(70.0), &"miller": FakeMood.new(45.0)}
		_person(&"baker", {&"temper": 90.0})
		_person(&"smith", {&"curiosity": 80.0, &"sociability": 30.0})
		var abstract := _conversation(setup[0])
		abstract.turns = 6
		abstract.turn_minutes = 2
		abstract.start_mood_scale = 0.0
		var ran := abstract.run(setup[1], setup[2], setup[3])
		assert_true(ran["ok"])
		assert_eq((ran["turns"] as Array).size(), 6)
		var visible := _conversation(setup[0])
		visible.turns = 6
		visible.turn_minutes = 2
		visible.start_mood_scale = 0.0
		var seen := _visible(visible, setup[1], setup[2], setup[3], 3)
		assert_eq(seen, ran["turns"], "the same turns, interactions and values")
		assert_eq(visible.social.store.export_state(), abstract.social.store.export_state(), "the same opinions, kinds and deeds")
		for turn: Dictionary in ran["turns"]:
			assert_true(MENU.has(turn["interaction"]) and turn["interaction"] != &"comfort", "picked from the menu by weight")


func test_a_conversation_saved_part_way_ends_the_same() -> void:
	var whole := _conversation(5)
	var expected := _visible(whole, &"baker", &"smith", 300, 1)
	var first := _conversation(5)
	var runner := _runner(first, &"baker", &"smith", 300)
	var turns: Array = []
	for minute in [300, 301]:
		runner.tick(0.1, minute)
		turns.append(runner.context.output["turn"])
	var saved: Variant = JSON.parse_string(JSON.stringify(runner.export_state()))
	var store_saved: Variant = JSON.parse_string(JSON.stringify(first.social.store.export_state()))
	var second := _conversation(5)
	assert_true(second.social.store.import_state(store_saved))
	var resumed := BustleSequenceRunner.new()
	resumed.register(&"converse", BustleConverseAction.new(second))
	assert_true(resumed.import_state(_sequence({"with": "smith"}), saved))
	for minute in range(302, 310):
		resumed.context.output.erase("turn")
		resumed.tick(0.1, minute)
		if resumed.context.output.has("turn"):
			turns.append(resumed.context.output["turn"])
	assert_eq(resumed.state, BustleSequenceRunner.State.SUCCEEDED)
	assert_eq(JSON.stringify(turns), JSON.stringify(expected), "the rest of the turns as if never saved")


func test_weights_follow_sliders_traits_opinion_and_a_low_mood() -> void:
	var talk := _conversation(1)
	var plain := talk.weights(&"baker", &"smith")
	assert_eq(plain, {&"chitchat": 4.0, &"deep_talk": 1.0, &"kind_words": 1.0, &"slight": 0.5, &"insult": 0.2, &"comfort": 0.0} as Dictionary[StringName, float])
	_person(&"baker", {&"temper": 100.0, &"sociability": 0.0})
	var hot := talk.weights(&"baker", &"smith")
	assert_almost_eq(hot[&"insult"], 0.4, 1e-6, "temper 100 doubles an insult")
	assert_almost_eq(hot[&"chitchat"], 2.0, 1e-6, "sociability 0 halves chitchat")
	var traits := BustleModifierSet.new()
	traits.set_source(&"trait_gentle", &"conversation.insult.weight", 0.0, 0.0)
	talk.modifiers_of = func(_id: StringName) -> BustleModifierSet: return traits
	assert_eq(talk.weights(&"baker", &"smith")[&"insult"], 0.0, "a trait can rule an interaction out")
	talk.modifiers_of = Callable()
	_people.clear()
	talk.social.store.add_opinion(&"baker", &"smith", 50.0, {}, 1.0)
	var fond := talk.weights(&"baker", &"smith")
	assert_almost_eq(fond[&"kind_words"], 2.0, 1e-6, "a high opinion makes kindness likelier")
	assert_eq(fond[&"slight"], 0.0, "and slights rarer")
	talk.social.store.add_opinion(&"baker", &"smith", -50.0, {}, 1.0)
	_moods[&"baker"] = FakeMood.new(0.0)
	var low := talk.weights(&"baker", &"smith")
	assert_almost_eq(low[&"slight"], 1.0, 1e-6, "mood 0 doubles curt interactions")
	assert_almost_eq(low[&"insult"], 0.4, 1e-6)
	assert_eq(low[&"chitchat"], 4.0, "and leaves the others")
	_moods[&"baker"] = FakeMood.new(80.0)
	assert_almost_eq(talk.weights(&"baker", &"smith")[&"slight"], 0.5, 1e-6, "a good mood doesn't")


func test_a_low_mood_lowers_the_chance_to_start() -> void:
	var talk := _conversation(9)
	assert_eq(talk.chance_to_start(&"baker"), 1.0, "no mood: always")
	_moods[&"baker"] = FakeMood.new(60.0)
	assert_eq(talk.chance_to_start(&"baker"), 1.0)
	_moods[&"baker"] = FakeMood.new(0.0)
	assert_almost_eq(talk.chance_to_start(&"baker"), 0.5, 1e-6)
	_moods[&"baker"] = FakeMood.new(25.0)
	assert_almost_eq(talk.chance_to_start(&"baker"), 0.75, 1e-6)
	var started := 0
	for minute in 400:
		if talk.wants_to_start(&"baker", &"smith", minute):
			started += 1
	assert_between(started, 250, 350, "about three times in four")
	assert_eq(talk.wants_to_start(&"baker", &"smith", 17), talk.wants_to_start(&"baker", &"smith", 17), "the same roll every time")
	_moods[&"baker"] = FakeMood.new(0.0)
	talk.start_chance = 0.0
	assert_eq(talk.run(&"baker", &"smith", 10)["reason"], &"declined")
	assert_eq(talk.social.store.deeds_of(&"baker"), [] as Array[Dictionary], "a declined conversation records nothing")


func test_openers_and_what_stops_a_conversation() -> void:
	var talk := _conversation(2)
	var ran := talk.run(&"baker", &"smith", 100, &"comfort")
	assert_eq(ran["turns"][0]["interaction"], &"comfort", "the opener first, though its weight is 0")
	for turn: Dictionary in (ran["turns"] as Array).slice(1):
		assert_ne(turn["interaction"], &"comfort", "and never again")
	assert_eq(talk.run(&"baker", &"baker", 100)["reason"], &"no_pair")
	var mute := BustleConversation.new(talk.social, [_load(&"comfort")] as Array[BustleInteractionDef])
	assert_eq(mute.run(&"baker", &"smith", 200)["turns"], [], "nothing to say: no turns")
	var runner := _runner(mute, &"baker", &"smith", 200)
	assert_eq(runner.tick(0.1, 200), BustleSequenceRunner.State.FAILED)
	assert_eq(runner.failure.get("reason"), &"nothing_to_say")
	var alone := _runner(talk, &"", &"baker", 200)
	assert_eq(alone.tick(0.1, 200), BustleSequenceRunner.State.FAILED)
	assert_eq(alone.failure.get("reason"), &"no_partner")
	talk.start_chance = 0.0
	var shy := _runner(talk, &"smith", &"baker", 200)
	assert_eq(shy.tick(0.1, 200), BustleSequenceRunner.State.FAILED)
	assert_eq(shy.failure.get("reason"), &"declined")


func test_the_demo_interaction_set_is_valid() -> void:
	for id: StringName in MENU:
		var def := _load(id)
		assert_true(def.is_valid(), String(id))
		assert_eq(def.id, id)
	assert_eq(_load(&"comfort").weight, 0.0, "comfort only as an opener")
	assert_true(_load(&"slight").tags.has(&"curt") and _load(&"insult").tags.has(&"curt"))
	var bad := BustleInteractionDef.new()
	bad.id = &"x"
	bad.slider_weights = {&"kindness": 1.0}
	assert_false(bad.is_valid(), "only known sliders")
	bad.slider_weights = {}
	bad.weight = -1.0
	assert_false(bad.is_valid(), "no negative weight")


func test_friends_who_notice_a_low_mood_are_offered_comfort() -> void:
	var store := BustleSocialStore.new()
	store.set_kind(&"baker", &"smith", &"friend")
	store.set_kind(&"baker", &"miller", &"friend")
	_moods = {&"smith": FakeMood.new(6.0), &"miller": FakeMood.new(60.0), &"weaver": FakeMood.new(0.0)}
	var hook := BustleComfort.new()
	assert_almost_eq(hook.urgency(6.0), 0.8, 1e-6)
	assert_eq(hook.urgency(30.0), 0.0)
	var senses := BustleSenses.new()
	var noticed: Array[StringName] = [&"smith", &"miller", &"weaver"]
	assert_eq(hook.advertise(&"baker", noticed, store, _mood_of, senses), 1, "only the friend in a low mood")
	assert_eq(senses.advertisements[0].option_id, &"smith")
	assert_almost_eq(senses.advertisements[0].relief[&"comfort"], 0.8, 1e-6)
	assert_eq(senses.inputs[&"need.comfort"], 1.0)
	assert_eq(hook.advertise(&"smith", [&"baker"] as Array[StringName], store, _mood_of, BustleSenses.new()), 0, "friendship is one-way")
	var library := BustleGoalLibrary.new()
	library.goals = [load(DEMO % "comfort_goal")] as Array[BustleGoalDef]
	var plain := _score(library, senses, BustleModifierSet.new())
	var kind := BustleModifierSet.new()
	var caring := BustleTraitDef.new()
	caring.id = &"caring"
	caring.mults = {&"need.comfort.weight": 2.0}
	var personality := BustlePersonality.new()
	assert_eq(personality.add_trait(caring), BustlePersonality.OK)
	personality.apply(kind)
	assert_almost_eq(_score(library, senses, kind), plain * 2.0, 1e-6, "a trait weights comfort")
	var talk := BustleConversation.new(BustleSocialInteractions.new(store, 4), _menu())
	var goal := library.find(&"comfort")
	var runner := BustleSequenceRunner.new()
	runner.register(&"converse", BustleConverseAction.new(talk))
	runner.start(goal.sequence, &"baker", 500, senses.advertisements[0].option_id)
	assert_eq(runner.tick(0.1, 500), BustleSequenceRunner.State.RUNNING)
	assert_eq(runner.context.output["talk_to"], &"smith")
	assert_eq(runner.context.output["turn"]["interaction"], &"comfort", "the comfort goal opens with comfort")
	assert_gt(store.opinion(&"smith", &"baker"), 50, "and the friend thinks better of them")


func _conversation(seed: int) -> BustleConversation:
	var social := BustleSocialInteractions.new(BustleSocialStore.new(), seed)
	social.mood_of = _mood_of
	var talk := BustleConversation.new(social, _menu())
	talk.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	return talk


func _menu() -> Array[BustleInteractionDef]:
	var out: Array[BustleInteractionDef] = []
	for id: StringName in MENU:
		out.append(_load(id))
	return out


func _load(id: StringName) -> BustleInteractionDef:
	return load(DEMO % id)


func _mood_of(id: StringName) -> Object:
	return _moods.get(id)


func _person(id: StringName, sliders: Dictionary) -> void:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	_people[id] = p


func _sequence(params: Dictionary) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = &"converse"
	step.params = params
	var sequence := BustleActionSequence.new()
	sequence.steps = [step] as Array[BustleActionStep]
	return sequence


func _runner(talk: BustleConversation, agent: StringName, partner: StringName, now: int) -> BustleSequenceRunner:
	var runner := BustleSequenceRunner.new()
	runner.register(&"converse", BustleConverseAction.new(talk))
	runner.start(_sequence({"with": String(partner)}), agent, now)
	return runner


# Ticks a converse step every [param every] minutes from [param now] until it ends; the turns.
func _visible(talk: BustleConversation, a: StringName, b: StringName, now: int, every: int) -> Array:
	var runner := BustleSequenceRunner.new()
	runner.register(&"converse", BustleConverseAction.new(talk))
	runner.start(_sequence({"with": String(b)}), a, now)
	var turns: Array = []
	var minute := now
	while minute < now + 200:
		runner.context.output.erase("turn")
		var state := runner.tick(0.1, minute)
		if runner.context.output.has("turn"):
			turns.append(runner.context.output["turn"])
		if state != BustleSequenceRunner.State.RUNNING:
			break
		minute += every
	return turns


func _score(library: BustleGoalLibrary, senses: BustleSenses, modifiers: BustleModifierSet) -> float:
	var context := BustleScoreContext.new()
	context.inputs = senses.inputs
	context.advertisements = senses.advertisements
	modifiers.fill_context(context, [&"comfort"] as Array[StringName], [&"social", &"comfort"] as Array[StringName])
	var candidates := BustleUtilityScorer.new().evaluate(library, context, BustleScoringConfig.new())
	return candidates[0].raw_score
