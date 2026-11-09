# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The built-in social store: opinions with reasons that expire, friend and rival kinds formed by
## repeated deeds (with hysteresis, never touching a host's kinds), deterministic compatibility,
## the port's deed behaviour, and saving.

const DAY := 1440

var _store: BustleSocialStore


func before_each() -> void:
	_store = BustleSocialStore.new()


func test_opinions_add_up_clamp_and_expire_with_their_reasons() -> void:
	assert_eq(_store.opinion(&"baker", &"smith"), 50, "neutral to start")
	assert_true(_store.add_opinion(&"baker", &"smith", 10.0, {"why": "chat"}, 2.0))
	assert_true(_store.add_opinion(&"baker", &"smith", -4.0, {"why": "late"}, 1.0))
	assert_eq(_store.opinion(&"baker", &"smith"), 56)
	assert_eq(_store.opinion(&"smith", &"baker"), 50, "opinions are one-way")
	var why := _store.reasons(&"baker", &"smith")
	assert_eq(why.map(func(r: Dictionary) -> String: return r["reason"]["why"]), ["chat", "late"], "strongest first")
	assert_eq(why[0]["until"], 2 * DAY)
	assert_eq(_store.reasons(&"baker", &"smith", 1).size(), 1)
	_store.set_time(DAY)
	assert_eq(_store.opinion(&"baker", &"smith"), 60, "the one-day entry ended")
	_store.set_time(2 * DAY)
	assert_eq(_store.opinion(&"baker", &"smith"), 50, "and the two-day one")
	assert_eq(_store.reasons(&"baker", &"smith"), [] as Array[Dictionary])
	_store.add_opinion(&"baker", &"smith", 500.0, {}, 1.0)
	assert_eq(_store.opinion(&"baker", &"smith"), 100, "clamped")
	assert_false(_store.add_opinion(&"baker", &"baker", 5.0, {}, 1.0), "not of oneself")
	assert_false(_store.add_opinion(&"baker", &"smith", NAN, {}, 1.0))
	assert_false(_store.add_opinion(&"baker", &"smith", 5.0, {}, 0.0))
	assert_false(_store.add_opinion(&"baker", &"smith", 5.0, {"bad": Vector2.ONE}, 1.0), "reasons are plain data")


func test_repeated_kind_deeds_form_a_friend_and_harm_forms_a_rival() -> void:
	watch_signals(_store)
	for i in 3:
		_store.add_opinion(&"baker", &"smith", 9.0, {"deed": "deed_%d" % i}, 30.0)
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["friend"]), "three kind deeds, opinion 77")
	assert_signal_emitted_with_parameters(_store, "kind_changed", [&"baker", &"smith", &"friend", true])
	assert_eq(_store.kinds_between(&"smith", &"baker"), PackedStringArray(), "one-way")
	for i in 3:
		_store.add_opinion(&"miller", &"smith", -9.0, {"deed": "deed_x%d" % i}, 30.0)
	assert_eq(_store.kinds_between(&"miller", &"smith"), PackedStringArray(["rival"]))
	var talk := BustleSocialStore.new()
	talk.add_opinion(&"a", &"b", 30.0, {"why": "warm feelings"}, 30.0)
	assert_eq(talk.kinds_between(&"a", &"b"), PackedStringArray(), "a high opinion without repeated deeds isn't friendship")
	var slow := BustleSocialStore.new()
	for i in 3:
		slow.add_opinion(&"a", &"b", 9.0, {"deed": "d%d" % i}, 60.0)
		slow.set_time(slow.now_minutes + 10 * DAY)
	assert_eq(slow.kinds_between(&"a", &"b"), PackedStringArray(), "deeds spread past the window don't count together")


func test_a_kind_lapses_only_past_its_release_level() -> void:
	for i in 3:
		_store.add_opinion(&"baker", &"smith", 9.0, {"deed": "deed_%d" % i}, 30.0)
	_store.add_opinion(&"baker", &"smith", -10.0, {"deed": "deed_slight"}, 30.0)
	assert_eq(_store.opinion(&"baker", &"smith"), 67)
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["friend"]), "no flicker below the forming level")
	_store.add_opinion(&"baker", &"smith", -13.0, {"deed": "deed_insult"}, 30.0)
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(), "below 55 it lapses")
	_store.set_time(31 * DAY)
	assert_eq(_store.opinion(&"baker", &"smith"), 50, "everything has run out")


func test_host_kinds_stay_whatever_the_rules_do() -> void:
	_store.set_kind(&"baker", &"smith", &"kin")
	_store.set_kind(&"baker", &"smith", &"friend")
	for i in 3:
		_store.add_opinion(&"baker", &"smith", -15.0, {"deed": "deed_%d" % i}, 30.0)
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["friend", "kin", "rival"]),
		"the rules add a rival but never remove the host's friend")
	_store.clear_kind(&"baker", &"smith", &"rival")
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["friend", "kin", "rival"]), "a rule kind isn't the host's to clear")
	_store.clear_kind(&"baker", &"smith", &"kin")
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["friend", "rival"]))


func test_compatibility_is_fixed_per_pair_and_seed() -> void:
	var ab := BustleCompatibility.of(&"baker", &"smith", 7)
	assert_eq(BustleCompatibility.of(&"baker", &"smith", 7), ab, "the same every time")
	assert_eq(BustleCompatibility.of(&"smith", &"baker", 7), ab, "the same both ways round")
	assert_between(ab, -1.0, 1.0)
	assert_ne(BustleCompatibility.of(&"baker", &"smith", 8), ab, "another world, another value")
	assert_ne(BustleCompatibility.of(&"baker", &"miller", 7), ab, "another pair, another value")
	assert_eq(BustleCompatibility.of(&"baker", &"baker", 7), 0.0)
	var values: Array[float] = []
	for i in 200:
		values.append(BustleCompatibility.of(StringName("a%d" % i), &"b", 1))
	assert_lt(values.min(), -0.5, "spread over the whole range")
	assert_gt(values.max(), 0.5)
	var same := BustlePersonality.new()
	var other := BustlePersonality.new()
	assert_eq(BustleCompatibility.of(&"baker", &"smith", 7, same, other, 1.0), 1.0, "equal sliders, fully weighted: 1")
	for slider: StringName in BustlePersonality.SLIDERS:
		same.set_slider(slider, 0.0)
		other.set_slider(slider, 100.0)
	assert_eq(BustleCompatibility.of(&"baker", &"smith", 7, same, other, 1.0), -1.0, "opposite sliders: -1")
	assert_eq(BustleCompatibility.of(&"baker", &"smith", 7, same, other, 0.0), ab, "weight 0: the hash alone")


func test_deeds_still_work_as_the_port_default() -> void:
	var key := _store.record_deed(&"baker", &"helped", &"smith", &"square", [{"id": &"miller"}])
	assert_true(_store.knows(&"miller", key))
	assert_false(_store.knows(&"weaver", key))
	assert_eq(_store.share_news(&"miller", &"weaver", &"square"), 1)
	assert_true(_store.knows(&"weaver", key))
	assert_eq(_store.share_news(&"weaver", &"tanner", &"square"), 0, "second-hand news doesn't travel on")


func test_the_store_saves_and_bad_data_changes_nothing() -> void:
	_store.set_kind(&"baker", &"smith", &"kin")
	for i in 3:
		_store.add_opinion(&"baker", &"smith", 9.0, {"deed": "deed_%d" % i}, 30.0)
	var key := _store.record_deed(&"baker", &"helped", &"smith", &"square", [{"id": &"miller"}])
	_store.set_time(DAY)
	var saved := _store.export_state()
	var other := BustleSocialStore.new()
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.export_state(), saved)
	assert_eq(other.opinion(&"baker", &"smith"), 77)
	assert_eq(other.kinds_between(&"baker", &"smith"), PackedStringArray(["friend", "kin"]))
	assert_true(other.knows(&"miller", key))
	assert_ne(other.record_deed(&"a", &"b", &"c", &"d", []), key, "deed keys carry on, never reused")
	var before := other.export_state()
	var bad: Dictionary = saved.duplicate(true)
	bad["entries"]["baker>smith"][0]["until"] = -5
	assert_false(other.import_state(bad), "an entry ending before it starts")
	bad = saved.duplicate(true)
	bad["rule_kinds"] = {"nopair": ["friend"]}
	assert_false(other.import_state(bad))
	assert_false(other.import_state("nope"))
	assert_eq(other.export_state(), before, "refused imports change nothing")
