# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Mood and thoughts: the target, stacking and tag modifiers, approach at the configured rates,
## sleep, closed-form steps, expiry, the dominant emotion, reasons, need thoughts, the scorer's
## mood input and saving.

var _mood: BustleMood


func before_each() -> void:
	_mood = BustleMood.new()


func test_the_target_is_the_baseline_plus_thoughts_with_stacking_and_tag_modifiers() -> void:
	assert_eq(_mood.target(), 50.0)
	var praised := _thought(&"praised", 8.0, 24.0, &"cheerful", 3, 0.5)
	for i in 4:
		assert_true(_mood.add_thought(praised))
	assert_eq(_mood.count(&"praised"), 3, "a fourth replaces the oldest")
	assert_almost_eq(_mood.target(), 50.0 + 8.0 + 4.0 + 2.0, 1e-6, "each repeat counts half the one before")
	var modifiers := BustleModifierSet.new()
	modifiers.set_source(&"warm", &"thought.tag.social_pos", 0.0, 1.5)
	modifiers.set_source(&"warm", &"mood.baseline", 5.0)
	_mood.modifiers = modifiers
	assert_almost_eq(_mood.target(), 55.0 + 14.0 * 1.5, 1e-6, "tags and baseline from modifiers")
	_mood.add_thought(_thought(&"ruined", -200.0, 1.0, &"low"))
	assert_eq(_mood.target(), 0.0, "clamped to the range")


func test_mood_rises_and_falls_at_the_configured_rates_and_volatility() -> void:
	_mood.add_thought(_thought(&"good_meal", 30.0, 100.0))
	_mood.advance_to(60)
	assert_almost_eq(_mood.mood, 62.0, 1e-6, "12 an hour up")
	_mood.advance_to(300)
	assert_almost_eq(_mood.mood, 80.0, 1e-6, "and stops at the target")
	_mood.remove_thought(&"good_meal")
	_mood.advance_to(420)
	assert_almost_eq(_mood.mood, 64.0, 1e-6, "8 an hour down")
	var slow := BustleModifierSet.new()
	slow.set_source(&"heavy", &"mood.rise.mult", 0.0, 0.5)
	slow.set_source(&"heavy", &"mood.volatility", 0.0, 2.0)
	var other := BustleMood.new(null, slow)
	other.add_thought(_thought(&"good_meal", 30.0, 100.0))
	other.advance_to(60)
	assert_almost_eq(other.mood, 62.0, 1e-6, "12 × 0.5 × 2")


func test_mood_freezes_in_sleep_while_thoughts_still_expire() -> void:
	_mood.add_thought(_thought(&"insulted", -20.0, 2.0, &"angry"))
	_mood.advance_to(480, true)
	assert_eq(_mood.mood, 50.0, "frozen asleep")
	assert_eq(_mood.count(), 0, "the thought ran out in the night")
	assert_eq(_mood.emotion, &"")


func test_one_long_step_equals_many_short_ones_across_expiries() -> void:
	var other := BustleMood.new()
	for m: BustleMood in [_mood, other]:
		m.add_thought(_thought(&"lost_wages", -24.0, 3.0, &"tense"))
		m.add_thought(_thought(&"kind_word", 6.0, 1.5, &"cheerful"))
	_mood.advance_to(600)
	for minute in range(1, 601):
		other.advance_to(minute)
	assert_almost_eq(other.mood, _mood.mood, 1e-6)
	assert_eq(_mood.now_minutes, 600)
	# By hand: 0–90 min target 32, fall 8/h → 38; 90–180 target 26 → 26 (reached at 180);
	# then back toward 50 at 12/h for 7 h → 50.
	assert_almost_eq(_mood.mood, 50.0, 1e-6)
	var mid := BustleMood.new()
	mid.add_thought(_thought(&"lost_wages", -24.0, 3.0))
	mid.add_thought(_thought(&"kind_word", 6.0, 1.5))
	mid.advance_to(90)
	assert_almost_eq(mid.mood, 38.0, 1e-6, "the target changes at the expiry")
	assert_eq(mid.count(), 1)


func test_the_dominant_emotion_is_the_largest_total_and_ties_keep_the_current_one() -> void:
	_mood.add_thought(_thought(&"chat", 5.0, 5.0, &"cheerful"))
	_mood.add_thought(_thought(&"rain", -3.0, 5.0, &"low"))
	assert_eq(_mood.emotion, &"cheerful")
	_mood.add_thought(_thought(&"scolded", -2.0, 5.0, &"low"))
	assert_eq(_mood.emotion, &"cheerful", "a tie (5 against 3 + 2) keeps the current one")
	_mood.add_thought(_thought(&"stubbed_toe", -1.0, 5.0, &"low"))
	assert_eq(_mood.emotion, &"low", "absolute values: 6 beats 5")
	var fresh := BustleMood.new()
	fresh.add_thought(_thought(&"b", 4.0, 5.0, &"tense"))
	fresh.add_thought(_thought(&"a", 4.0, 5.0, &"content"))
	assert_eq(fresh.emotion, &"tense", "the first stays on a tie")


func test_every_thought_lists_its_reason_strongest_first() -> void:
	var deed := _thought(&"helped", 10.0, 48.0, &"hopeful")
	deed.reason_kind = &"deed"
	_mood.add_thought(deed, {"deed": "d7", "by": "neighbour"})
	_mood.add_thought(_thought(&"drafty_room", -4.0, 2.0, &"tense"), {"place": "loft"})
	var reasons := _mood.reasons()
	assert_eq(reasons.size(), 2)
	assert_eq(reasons[0], {"thought": &"helped", "value": 10.0, "emotion": &"hopeful",
		"reason": {"kind": "deed", "deed": "d7", "by": "neighbour"}, "expires": 2880})
	assert_eq(reasons[1]["reason"], {"kind": "event", "place": "loft"})


func test_need_thoughts_hold_while_the_need_is_pressing() -> void:
	var needs := BustleNeedSet.new()
	var company := BustleNeedDef.new()
	company.id = &"company"
	company.rate_per_hour = 0.2
	needs.add_need(company)
	var lonely := _thought(&"lonely", -6.0, 0.0, &"lonely")
	lonely.reason_kind = &"need"
	lonely.need = &"company"
	lonely.need_at_least = 0.5
	var defs: Array[BustleThoughtDef] = [lonely]
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 0)
	needs.advance(180.0, [])
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 1)
	assert_eq(_mood.reasons()[0]["reason"]["kind"], &"need")
	assert_almost_eq(float(_mood.reasons()[0]["reason"]["pressure"]), 0.6, 1e-6)
	assert_eq(_mood.reasons()[0]["expires"], -1, "held, not timed")
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 1, "holding it again doesn't stack")
	needs.relieve(&"company", 0.5)
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 0, "relieved, it goes")
	assert_false(_mood.add_thought(lonely), "a held thought isn't added as a timed one")
	assert_false(_mood.set_held(_thought(&"x", 1.0, 2.0), true), "nor a timed one held")


func test_mood_reaches_the_scorer_through_its_curves() -> void:
	var low := Curve.new()
	low.max_domain = 100.0
	low.add_point(Vector2(0, 1))
	low.add_point(Vector2(100, 0))
	var config := BustleScoringConfig.new()
	config.mood_curves = {&"social": low}
	var hall := BustleAdvertisement.new(&"hall", {&"company": 1.0}, {}, [&"social"])
	var scorer := BustleUtilityScorer.new()
	var scores: Array[float] = []
	for value: float in [80.0, 20.0]:
		var mood := BustleMood.new()
		mood.mood = value
		var context := BustleScoreContext.new()
		context.inputs = {&"need.company": 0.5}
		mood.fill_inputs(context.inputs)
		assert_eq(context.inputs[BustleInputs.MOOD], value)
		scores.append(scorer.advertisement_score(hall, context, config))
	assert_lt(scores[0], scores[1], "a curve that favours low mood scores the hall higher at 20")


func test_export_and_import_round_trip_and_bad_data_changes_nothing() -> void:
	var tense := _thought(&"tense_day", -12.0, 6.0, &"tense")
	var lonely := _thought(&"lonely", -6.0, 0.0, &"lonely")
	_mood.add_thought(tense, {"why": "late"})
	_mood.set_held(lonely, true)
	_mood.advance_to(90)
	var saved := _mood.export_state()
	var defs: Array[BustleThoughtDef] = [tense, lonely]
	var other := BustleMood.new()
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved)), defs))
	assert_eq(other.export_state(), saved)
	assert_almost_eq(other.target(), _mood.target(), 1e-6)
	other.advance_to(400)
	_mood.advance_to(400)
	assert_almost_eq(other.mood, _mood.mood, 1e-6, "and carries on the same")
	var before := other.export_state()
	var unknown: Dictionary = saved.duplicate(true)
	unknown["thoughts"][0]["id"] = "never_defined"
	assert_false(other.import_state(unknown, defs))
	assert_false(other.import_state({"mood": NAN, "now": 0, "emotion": "", "thoughts": []}, defs))
	assert_false(other.import_state({"mood": 50, "now": 1.5, "emotion": "", "thoughts": []}, defs))
	assert_false(other.import_state("nope", defs))
	assert_eq(other.export_state(), before, "a refused import changes nothing")


func test_the_dominant_emotion_is_the_same_whatever_the_step_size_awake_or_asleep() -> void:
	for asleep: bool in [false, true]:
		var long := _two_emotions()
		var short := _two_emotions()
		assert_eq(long.emotion, &"cheerful", "30 against 20 at the start")
		long.advance_to(60, asleep)
		short.advance_to(30, asleep)
		assert_eq(short.emotion, &"tense", "at 30: 10 against 20")
		short.advance_to(60, asleep)
		assert_eq(long.emotion, &"tense", "the tie at 60 keeps what it had at 30 (asleep: %s)" % asleep)
		assert_eq(long.export_state(), short.export_state(), "the same state either way")


func test_import_refuses_impossible_thoughts_and_changes_nothing() -> void:
	var timed := _thought(&"tense_day", -12.0, 6.0, &"tense", 2)
	var held := _thought(&"lonely", -6.0, 0.0, &"lonely")
	var defs: Array[BustleThoughtDef] = [timed, held]
	_mood.add_thought(timed)
	_mood.set_held(held, true)
	_mood.advance_to(30)
	var good := _mood.export_state()
	var other := BustleMood.new()
	assert_true(other.import_state(good, defs))
	var before := other.export_state()
	var cases := {
		"a timed thought made immortal": func(d: Dictionary) -> void: d["thoughts"][0]["expires"] = -1,
		"another negative end": func(d: Dictionary) -> void: d["thoughts"][0]["expires"] = -2,
		"a held thought with an end": func(d: Dictionary) -> void: d["thoughts"][1]["expires"] = 500,
		"a start after the save's minute": func(d: Dictionary) -> void: d["thoughts"][0]["started"] = 31,
		"an end before the start": func(d: Dictionary) -> void:
			d["thoughts"][0]["started"] = 20
			d["thoughts"][0]["expires"] = 10,
		"more than the stack limit": func(d: Dictionary) -> void:
			for i in 2:
				d["thoughts"].append(d["thoughts"][0].duplicate(true)),
		"two of a held thought": func(d: Dictionary) -> void: d["thoughts"].append(d["thoughts"][1].duplicate(true)),
		"a bad entry after good ones": func(d: Dictionary) -> void: d["thoughts"].append({"id": "lonely"}),
		"a reason that isn't plain data": func(d: Dictionary) -> void: d["thoughts"][0]["reason"]["why"] = Vector2.ONE,
	}
	for label: String in cases:
		var data: Dictionary = good.duplicate(true)
		(cases[label] as Callable).call(data)
		assert_false(other.import_state(data, defs), label)
		assert_eq(other.export_state(), before, "%s: nothing changed" % label)
	var ended: Dictionary = good.duplicate(true)
	ended["now"] = 400
	assert_true(other.import_state(ended, defs), "a thought that already ran out is fine")
	assert_eq(other.count(&"tense_day"), 0, "and dropped")
	assert_eq(other.count(&"lonely"), 1)


func test_mood_always_starts_inside_its_range_and_bad_config_is_safe() -> void:
	var high := BustleMoodConfig.new()
	high.baseline = 150.0
	var mood := BustleMood.new(high)
	assert_eq(mood.mood, 100.0, "a baseline above the range starts at the top")
	var lifted := BustleModifierSet.new()
	lifted.set_source(&"t", &"mood.baseline", 100.0)
	mood = BustleMood.new(null, lifted)
	assert_eq(mood.mood, 100.0, "a modifier can't push it past the range either")
	mood.start(10)
	assert_eq(mood.mood, 100.0, "nor on a reset")
	mood.advance_to(600, true)
	var inputs: Dictionary[StringName, float] = {}
	mood.fill_inputs(inputs)
	assert_eq(inputs[BustleInputs.MOOD], 100.0, "and the scorer sees the clamped value")
	var low := BustleMoodConfig.new()
	low.baseline = -20.0
	assert_eq(BustleMood.new(low).mood, 0.0)
	var broken := BustleMoodConfig.new()
	broken.baseline = NAN
	broken.min_mood = INF
	broken.max_mood = NAN
	broken.rise_per_hour = NAN
	broken.volatility = INF
	mood = BustleMood.new(broken)
	assert_eq(mood.mood_range(), Vector2(0, 100), "bounds that aren't finite become 0 and 100")
	assert_eq(mood.mood, 50.0, "a NAN baseline is the middle")
	mood.add_thought(_thought(&"good", 20.0, 5.0))
	mood.advance_to(120)
	assert_eq(mood.mood, 50.0, "a NAN rate doesn't move it")
	var reversed := BustleMoodConfig.new()
	reversed.min_mood = 80.0
	reversed.max_mood = 20.0
	assert_eq(BustleMood.new(reversed).mood_range(), Vector2(20, 80), "reversed bounds are swapped")


func test_a_full_stack_restarts_only_the_replacements_timer() -> void:
	var praised := _thought(&"praised", 8.0, 10.0, &"cheerful", 2)
	_mood.add_thought(praised)
	_mood.advance_to(60)
	_mood.add_thought(praised)
	_mood.advance_to(120)
	_mood.add_thought(praised)
	var ends: Array = []
	for thought: Dictionary in _mood.export_state()["thoughts"]:
		ends.append(thought["expires"])
	assert_eq(ends, [660, 720], "the oldest (ending at 600) went; the second keeps its own end")


func test_durations_round_to_whole_minutes_and_definitions_are_checked() -> void:
	for pair: Array in [[0.001, 1], [0.5 / 60.0, 1], [1.49 / 60.0, 1], [1.5 / 60.0, 2], [2.0, 120]]:
		assert_eq(_thought(&"t", 1.0, pair[0]).duration_minutes(), pair[1], "%s hours" % pair[0])
	assert_eq(_thought(&"held", 1.0, 0.0).duration_minutes(), 0)
	var bad: Array[BustleThoughtDef] = []
	for i in 6:
		bad.append(_thought(&"bad", 1.0, 1.0))
	bad[0].duration_hours = 1.0e300
	bad[1].stack_mult = 1.5
	bad[2].stack_mult = -0.1
	bad[3].need_at_least = NAN
	bad[4].reason_kind = &"whim"
	bad[5].stack_limit = 0
	for def: BustleThoughtDef in bad:
		assert_false(def.is_valid())
		assert_false(_mood.add_thought(def))
	assert_true(_thought(&"ok", 1.0, 1.0).is_valid())
	assert_false(_mood.add_thought(_thought(&"ok", 1.0, 1.0), {"bad": Callable()}), "details must be plain data")


func test_need_thoughts_at_the_threshold_and_for_missing_needs() -> void:
	var needs := BustleNeedSet.new()
	var company := BustleNeedDef.new()
	company.id = &"company"
	company.start = 0.5
	needs.add_need(company)
	var lonely := _thought(&"lonely", -6.0, 0.0, &"lonely")
	lonely.need = &"company"
	lonely.need_at_least = 0.5
	var stray := _thought(&"thirsty", -3.0, 0.0)
	stray.need = &"water"
	stray.need_at_least = 0.0
	var defs: Array[BustleThoughtDef] = [lonely, stray]
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 1, "exactly at the threshold holds")
	assert_eq(_mood.count(&"thirsty"), 0, "a need the agent doesn't have never holds")
	needs.remove_need(&"company")
	_mood.sync_need_thoughts(needs, defs)
	assert_eq(_mood.count(&"lonely"), 0, "a removed need drops its thought")


func _two_emotions() -> BustleMood:
	var mood := BustleMood.new()
	mood.set_held(_thought(&"a_held", 10.0, 0.0, &"cheerful"), true)
	mood.add_thought(_thought(&"a_timed", 20.0, 0.5, &"cheerful"))
	mood.set_held(_thought(&"b_held", 10.0, 0.0, &"tense"), true)
	mood.add_thought(_thought(&"b_timed", 10.0, 1.0, &"tense"))
	return mood


func _thought(id: StringName, value: float, hours: float, emotion: StringName = &"", limit: int = 1, mult: float = 0.5) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.duration_hours = hours
	def.emotion = emotion
	def.stack_limit = limit
	def.stack_mult = mult
	if value > 0.0:
		def.tags = [&"social_pos"]
	return def
