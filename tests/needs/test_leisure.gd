# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Leisure kinds and tolerance: relief shrinks with each use of a kind, stops at the boredom
## threshold so the real scorer turns to another kind, and recovers with time.

var _leisure: BustleLeisure


func before_each() -> void:
	_leisure = BustleLeisure.new()
	_leisure.kinds = [&"music", &"walk"]


func test_each_use_builds_tolerance_until_the_kind_bores() -> void:
	assert_eq(_leisure.use(&"music"), 1.0, "a fresh kind gives full relief")
	assert_eq(_leisure.use(&"music"), 0.75)
	assert_eq(_leisure.use(&"music"), 0.5, "the third use is still worth something")
	assert_true(_leisure.is_bored(&"music"))
	assert_eq(_leisure.use(&"music"), 0.0, "past the boredom threshold: nothing")
	assert_eq(_leisure.relief_factor(&"walk"), 1.0, "another kind is untouched")
	assert_eq(_leisure.relief_factor(&"chores"), 1.0, "not a leisure kind at all")


func test_the_scorer_stops_repeating_a_kind_past_the_boredom_threshold() -> void:
	var goal := BustleGoalDef.new()
	goal.id = &"unwind"
	goal.band = BustleBands.PERSONAL
	goal.uses_advertisements = true
	var library := BustleGoalLibrary.new()
	library.goals.append(goal)
	var ads: Array[BustleAdvertisement] = [
		BustleAdvertisement.new(&"fiddle", {&"leisure": 1.0}, {}, [&"music"]),
		BustleAdvertisement.new(&"lane", {&"leisure": 0.6}, {}, [&"walk"]),
	]
	var picks: Array[StringName] = []
	for i in 6:
		var best := _best(library, ads)
		picks.append(best)
		_leisure.use(_leisure.kind_of(_ad(ads, best)))
	assert_eq(picks.slice(0, 2), [&"fiddle", &"fiddle"] as Array[StringName], "the better option first")
	assert_true(picks.has(&"lane"), "then the other kind")
	var run := 0
	var longest := 0
	for i in picks.size():
		run = run + 1 if i > 0 and picks[i] == picks[i - 1] else 1
		longest = maxi(longest, run)
	assert_lte(longest, 3, "never more than three of a kind in a row: %s" % [picks])


func test_tolerance_falls_with_time_and_saves() -> void:
	for i in 3:
		_leisure.use(&"walk")
	assert_true(_leisure.is_bored(&"walk"))
	_leisure.advance(720.0)
	assert_almost_eq(_leisure.tolerance(&"walk"), 0.5, 1e-6, "half a day at 0.5 a day")
	assert_false(_leisure.is_bored(&"walk"))
	var saved := _leisure.export_state()
	var other := BustleLeisure.new()
	other.kinds = _leisure.kinds
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_almost_eq(other.tolerance(&"walk"), 0.5, 1e-6)
	assert_false(other.import_state({"tolerance": {"walk": NAN}}))
	assert_false(other.import_state({"tolerance": {"walk": 0.1, 3: 0.2}}), "a key that isn't a string")
	assert_almost_eq(other.tolerance(&"walk"), 0.5, 1e-6, "a refused import changes nothing")
	assert_false(other.import_state("nope"))
	_leisure.advance(2880.0)
	assert_eq(_leisure.tolerance(&"walk"), 0.0, "fully recovered")
	assert_eq(_leisure.export_state(), {"tolerance": {}})


func test_adjust_leaves_other_needs_and_the_original_alone() -> void:
	var ad := BustleAdvertisement.new(&"fiddle", {&"leisure": 1.0, &"company": 0.4}, {}, [&"social", &"music"])
	for i in 3:
		_leisure.use(&"music")
	var adjusted := _leisure.adjust(ad)
	assert_eq(adjusted.relief[&"leisure"], 0.0)
	assert_eq(adjusted.relief[&"company"], 0.4, "only leisure is scaled")
	assert_eq(ad.relief[&"leisure"], 1.0, "the original is a copy")
	assert_eq(_leisure.kind_of(ad), &"music")


func test_spaced_uses_decay_between_and_steps_are_equivalent() -> void:
	for i in 4:
		_leisure.use(&"walk")
		_leisure.advance(720.0)
	assert_false(_leisure.is_bored(&"walk"), "spaced half a day apart, a fourth use isn't blocked")
	var one := BustleLeisure.new()
	var many := BustleLeisure.new()
	for l: BustleLeisure in [one, many]:
		l.kinds = [&"walk"]
		l.use(&"walk")
		l.use(&"walk")
	one.advance(600.0)
	for i in 600:
		many.advance(1.0)
	assert_almost_eq(many.tolerance(&"walk"), one.tolerance(&"walk"), 1e-6)


func test_tuning_that_isnt_finite_is_safe() -> void:
	_leisure.tolerance_per_use = NAN
	_leisure.tolerance_decay_per_day = INF
	_leisure.boredom_threshold = NAN
	assert_eq(_leisure.use(&"walk"), 1.0)
	assert_eq(_leisure.tolerance(&"walk"), 0.0, "NAN per use adds nothing")
	_leisure.tolerance_per_use = 0.6
	_leisure.use(&"walk")
	_leisure.advance(1.0)
	assert_eq(_leisure.tolerance(&"walk"), 0.6, "an infinite decay is ignored")
	assert_false(_leisure.is_bored(&"walk"), "a NAN threshold counts as 1")
	_leisure.boredom_threshold = -5.0
	assert_true(_leisure.is_bored(&"walk"), "a threshold below 0 counts as 0")


func _best(library: BustleGoalLibrary, ads: Array[BustleAdvertisement]) -> StringName:
	var context := BustleScoreContext.new()
	context.inputs = {&"need.leisure": 0.6}
	for ad: BustleAdvertisement in ads:
		context.advertisements.append(_leisure.adjust(ad))
	var candidates := BustleUtilityScorer.new().evaluate(library, context, BustleScoringConfig.new())
	BustleUtilityScorer.sort(candidates)
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and not candidate.fallback:
			return candidate.option_id
	return &""


func _ad(ads: Array[BustleAdvertisement], id: StringName) -> BustleAdvertisement:
	for ad: BustleAdvertisement in ads:
		if ad.option_id == id:
			return ad
	return BustleAdvertisement.new()
