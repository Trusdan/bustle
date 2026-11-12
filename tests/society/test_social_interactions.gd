# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Interactions and greeting: one pure outcome function, every interaction recorded as a deed
## with opinion entries naming it, greeting cooldowns, moods and thoughts, the inspector listing
## deeds and reasons, and repeated kind interactions forming a friend.

## A social port that isn't the built-in store: it only keeps what it's told.
class _RecordingPort:
	extends BustleSocialPort
	var deeds: Array[Dictionary] = []

	func record_deed(actor: StringName, verb: StringName, target: StringName, place: StringName,
			witnesses: Array[Dictionary], magnitude: float = 1.0, return_magnitude: float = 0.0) -> StringName:
		deeds.append({"actor": actor, "verb": verb, "target": target, "place": place,
			"witnesses": witnesses.size(), "magnitude": magnitude, "return_magnitude": return_magnitude})
		return StringName("rec_%d" % deeds.size())


var _social: BustleSocialInteractions
var _moods: Dictionary[StringName, BustleMood] = {}


func before_each() -> void:
	_social = BustleSocialInteractions.new(BustleSocialStore.new(), 7)
	_social.greeting = _def(&"greet", 2.0, 1.0, 0.0)
	_moods = {}


func test_the_outcome_is_the_same_for_the_same_inputs_and_records_nothing() -> void:
	var chat := _def(&"chitchat", 6.0, 4.0, 2.0)
	var first := BustleSocialInteractions.outcome(chat, &"baker", &"smith", 600, 7, 0.3, 60.0, 40.0)
	assert_eq(BustleSocialInteractions.outcome(chat, &"baker", &"smith", 600, 7, 0.3, 60.0, 40.0), first, "the same every time")
	assert_ne(BustleSocialInteractions.outcome(chat, &"baker", &"smith", 601, 7, 0.3, 60.0, 40.0)["to_recipient"], first["to_recipient"], "another minute, another roll")
	assert_between(first["to_recipient"], 0.0, 20.0)
	assert_eq(_social.store.deeds_of(&"baker"), [] as Array[Dictionary], "outcome alone records nothing")
	var plain := _def(&"chitchat", 10.0, 0.0, 0.0)
	assert_almost_eq(BustleSocialInteractions.outcome(plain, &"a", &"b", 0, 1, 0.0, -1.0, 100.0)["to_recipient"], 13.0, 1e-6, "a good mood lifts gains")
	assert_almost_eq(BustleSocialInteractions.outcome(plain, &"a", &"b", 0, 1, 0.0, -1.0, 0.0)["to_recipient"], 7.0, 1e-6, "a low mood damps them")
	var insult := _def(&"insult", -10.0, 0.0, 0.0)
	assert_almost_eq(BustleSocialInteractions.outcome(insult, &"a", &"b", 0, 1, 0.0, -1.0, 0.0)["to_recipient"], -13.0, 1e-6, "and makes harm hurt more")


func test_each_interaction_records_a_deed_and_opinion_entries_that_name_it() -> void:
	var kind := _def(&"kind_words", 8.0, 3.0, 0.0)
	var result := _social.interact(kind, &"baker", &"smith", 600, &"square", [{"id": &"miller"}])
	assert_true(result["ok"])
	var deed: StringName = result["deed"]
	assert_eq(_social.store.deeds_of(&"smith"), [{"deed": deed, "actor": &"baker", "verb": &"kind_words", "target": &"smith", "place": &"square"}] as Array[Dictionary])
	assert_true(_social.store.knows(&"miller", deed), "the witness saw it")
	var why := _social.store.reasons(&"smith", &"baker")
	assert_eq(why[0]["reason"], {"deed": String(deed), "interaction": "kind_words", "by": "baker"})
	assert_almost_eq(float(why[0]["value"]), result["to_recipient"], 1e-6, "exactly the outcome's value")
	assert_eq(_social.store.reasons(&"baker", &"smith")[0]["reason"]["with"], "smith", "the initiator's side too")
	assert_eq(_social.interact(kind, &"baker", &"baker", 600)["reason"], &"no_pair")
	assert_eq(_social.interact(BustleInteractionDef.new(), &"baker", &"smith", 600)["reason"], &"invalid")


func test_greeting_respects_pair_and_agent_cooldowns() -> void:
	assert_true(_social.greet(&"baker", &"smith", 600)["ok"])
	assert_eq(_social.greet(&"smith", &"baker", 650)["reason"], &"cooling_down", "the pair, either way round")
	assert_eq(_social.greet(&"baker", &"miller", 605)["reason"], &"cooling_down", "the greeter, for a few minutes")
	assert_true(_social.greet(&"baker", &"miller", 610)["ok"], "then someone else")
	assert_true(_social.greet(&"smith", &"miller", 611)["ok"], "others aren't held up")
	assert_true(_social.greet(&"smith", &"baker", 720)["ok"], "the pair again after two hours")
	var greets: Array = _social.store.deeds_of(&"baker", 10).filter(func(d: Dictionary) -> bool: return d["verb"] == &"greet")
	assert_eq(greets.size(), 3, "every greeting is a deed")
	var saved := _social.export_state()
	var other := BustleSocialInteractions.new(_social.store, 7)
	other.greeting = _social.greeting
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.greet(&"baker", &"smith", 730)["reason"], &"cooling_down", "cooldowns survive a save")
	assert_false(other.import_state({"pairs": {"a|b": 1.5}, "agents": {}}))


func test_moods_bend_the_outcome_and_thoughts_name_the_deed() -> void:
	var low := BustleMood.new()
	low.mood = 10.0
	_moods[&"smith"] = low
	_social.mood_of = func(id: StringName) -> Object: return _moods.get(id)
	var praised := BustleThoughtDef.new()
	praised.id = &"praised"
	praised.value = 4.0
	praised.duration_hours = 24.0
	var kind := _def(&"kind_words", 10.0, 0.0, 0.0)
	kind.recipient_thought = praised
	var result := _social.interact(kind, &"baker", &"smith", 600)
	var expected := BustleSocialInteractions.outcome(kind, &"baker", &"smith", 600, 7,
		BustleCompatibility.of(&"baker", &"smith", 7), -1.0, 10.0)
	assert_almost_eq(result["to_recipient"], expected["to_recipient"], 1e-9, "interact uses the same outcome")
	assert_eq(low.count(&"praised"), 1)
	assert_eq(low.reasons()[0]["reason"], {"kind": "event", "deed": String(result["deed"]), "by": "baker"})


func test_repeated_kind_interactions_form_a_friend() -> void:
	var kind := _def(&"kind_words", 10.0, 0.0, 0.0)
	kind.compatibility_scale = 0.0
	kind.days = 10.0
	for i in 3:
		_social.interact(kind, &"baker", &"smith", 600 + i * 60)
	assert_eq(_social.store.opinion(&"smith", &"baker"), 80)
	assert_eq(_social.store.kinds_between(&"smith", &"baker"), PackedStringArray(["friend"]), "from three deeds")


func test_the_inspector_lists_deeds_and_opinion_reasons() -> void:
	var society := BustleSociety.new(7)
	var library := BustleGoalLibrary.new()
	var idle := BustleGoalDef.new()
	idle.id = &"idle"
	library.goals.append(idle)
	society.register_archetype(&"folk", library)
	society.add_agent(&"smith", &"folk")
	var inspector := BustleInspector.new()
	assert_eq(inspector.snapshot(society, &"smith")["social"], {"available": false, "module": "social"}, "no store, marked unavailable")
	society.set_port(&"social", _social.store)
	var result := _social.interact(_def(&"kind_words", 8.0, 0.0, 0.0), &"baker", &"smith", 600)
	var social: Dictionary = inspector.snapshot(society, &"smith")["social"]
	assert_true(social["available"])
	assert_eq(social["deeds"][0]["deed"], result["deed"])
	assert_eq(social["deeds"][0]["verb"], &"kind_words")
	assert_eq(social["opinions"][0]["other"], &"baker")
	assert_eq(social["opinions"][0]["reasons"][0]["reason"]["deed"], String(result["deed"]))


func test_compatibility_bends_kindness_and_harm_like_mood() -> void:
	var kind := _def(&"kind_words", 10.0, 4.0, 0.0)
	var harm := _def(&"insult", -10.0, -4.0, 0.0)
	var cases := [
		[kind, 1.0, 15.0, 6.0, "a compatible pair gains more"],
		[kind, -1.0, 5.0, 2.0, "an incompatible pair gains less"],
		[harm, 1.0, -5.0, -2.0, "a compatible pair loses less"],
		[harm, -1.0, -15.0, -6.0, "an incompatible pair loses more"],
		[kind, 0.0, 10.0, 4.0, "a neutral pair: as written"],
		[harm, 0.0, -10.0, -4.0, "a neutral pair: as written"],
	]
	for case: Array in cases:
		var result := BustleSocialInteractions.outcome(case[0], &"a", &"b", 0, 1, case[1])
		assert_almost_eq(result["to_recipient"], case[2], 1e-6, case[4])
		assert_almost_eq(result["to_initiator"], case[3], 1e-6, "%s (both sides)" % case[4])
	var both := BustleSocialInteractions.outcome(harm, &"a", &"b", 0, 1, 1.0, -1.0, 100.0)
	assert_almost_eq(both["to_recipient"], -10.0 * 0.5 * 0.7, 1e-6, "compatibility and a good mood both soften harm")
	var strong := _def(&"insult", -10.0, 0.0, 0.0)
	strong.compatibility_scale = 3.0
	assert_eq(BustleSocialInteractions.outcome(strong, &"a", &"b", 0, 1, 1.0)["to_recipient"], 0.0, "a loss never turns into a gain")


func test_expired_cooldowns_are_dropped_and_long_durations_refused() -> void:
	_social.greet(&"baker", &"smith", 600)
	_social.greet(&"miller", &"weaver", 600)
	_social.store.set_time(700)
	assert_eq(_social.export_state()["agents"].keys(), [], "the greeters' cooldowns ended at 610")
	assert_eq(_social.export_state()["pairs"].size(), 2, "the pairs' are still running")
	_social.store.set_time(800)
	assert_eq(_social.export_state(), {"pairs": {}, "agents": {}}, "nothing ended is kept")
	var forever := _def(&"vow", 5.0, 0.0, 0.0)
	forever.days = 2.0e6
	assert_false(forever.is_valid(), "longer than the store keeps an entry")
	assert_eq(_social.interact(forever, &"baker", &"smith", 900)["reason"], &"invalid", "so no deed without its opinion")
	var odd := BustleSocialInteractions.new(BustleSocialStore.new(), 1)
	odd.greeting = _social.greeting
	assert_true(odd.greet(&"a|b", &"c", 0)["ok"])
	assert_true(odd.greet(&"a", &"b|c", 0)["ok"], "ids with separators in them don't collide")


func _def(id: StringName, to_recipient: float, to_initiator: float, spread: float) -> BustleInteractionDef:
	var def := BustleInteractionDef.new()
	def.id = id
	def.recipient_value = to_recipient
	def.initiator_value = to_initiator
	def.spread = spread
	return def


func test_interactions_record_through_any_social_port_with_both_outcomes() -> void:
	var port := _RecordingPort.new()
	var social := BustleSocialInteractions.new(port, 7)
	social.greeting = _def(&"greet", 2.0, 1.0, 0.0)
	var kind := _def(&"kind_words", 8.0, 3.0, 2.0)
	var result := social.interact(kind, &"baker", &"smith", 600, &"square", [{"id": &"miller"}])
	assert_true(result["ok"])
	assert_eq(result["deed"], &"rec_1", "the port's key")
	assert_eq(port.deeds, [{"actor": &"baker", "verb": &"kind_words", "target": &"smith", "place": &"square",
		"witnesses": 1, "magnitude": result["to_recipient"], "return_magnitude": result["to_initiator"]}] as Array[Dictionary],
		"one deed, carrying both outcomes")
	assert_false(port.has_method(&"add_opinion"), "no opinion entries: the port weighs deeds itself")
	assert_eq(port.opinion(&"smith", &"baker"), BustleSocialPort.NEUTRAL_OPINION)
	assert_eq(BustleSocialInteractions.outcome(kind, &"baker", &"smith", 600, 7, BustleCompatibility.of(&"baker", &"smith", 7)),
		BustleSocialInteractions.outcome(kind, &"baker", &"smith", 600, 7, BustleCompatibility.of(&"baker", &"smith", 7)),
		"the outcome is unchanged")
	# Greetings, and their cooldowns, on the same port.
	assert_true(social.greet(&"baker", &"smith", 700)["ok"])
	assert_eq(social.greet(&"smith", &"baker", 750)["reason"], &"cooling_down")
	assert_eq(social.greet(&"baker", &"miller", 705)["reason"], &"cooling_down")
	assert_true(social.greet(&"baker", &"miller", 710)["ok"])
	assert_eq(port.deeds.size(), 3, "each greeting is a deed through the port")
	var saved := social.export_state()
	assert_eq(saved["agents"], {"baker": 720}, "pruned at the latest minute recorded")
	var other := BustleSocialInteractions.new(port, 7)
	other.greeting = social.greeting
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.greet(&"smith", &"baker", 800)["reason"], &"cooling_down", "cooldowns survive a save")


func test_a_conversation_records_through_the_port() -> void:
	var port := _RecordingPort.new()
	var talk := BustleConversation.new(BustleSocialInteractions.new(port, 3),
		[load("res://demo/social/chitchat.tres"), load("res://demo/social/kind_words.tres")] as Array[BustleInteractionDef])
	talk.start_mood_scale = 0.0
	var ran := talk.run(&"baker", &"smith", 600)
	assert_true(ran["ok"])
	assert_eq(port.deeds.size(), (ran["turns"] as Array).size(), "every turn is a deed through the port")
	for i: int in port.deeds.size():
		var turn: Dictionary = ran["turns"][i]
		assert_eq(port.deeds[i]["magnitude"], turn["to_recipient"], "turn %d's outcome for the listener" % i)
		assert_eq(port.deeds[i]["return_magnitude"], turn["to_initiator"])

