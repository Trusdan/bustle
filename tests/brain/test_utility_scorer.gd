# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The utility scorer: goal scores, the advertisement formula, eligibility, bands, the pick window
## and seeded picks. Every fixture is synthetic and fully specified.

var _scorer := BustleUtilityScorer.new()
var _config: BustleScoringConfig


func before_each() -> void:
	_config = BustleScoringConfig.new()


## A straight line from (x0, y0) to (x1, y1) over the domain x0..x1.
func _line(x0: float, y0: float, x1: float, y1: float) -> Curve:
	var curve := Curve.new()
	curve.min_domain = x0
	curve.max_domain = x1
	curve.min_value = minf(minf(y0, y1), 0.0)
	curve.max_value = maxf(maxf(y0, y1), 1.0)
	curve.add_point(Vector2(x0, y0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(x1, y1), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


func _goal(id: StringName, band: int, inputs: Array = [], base: float = 1.0) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.base_weight = base
	for key: StringName in inputs:
		var consideration := BustleConsideration.new()
		consideration.input = key
		consideration.curve = _line(0, 0, 1, 1)
		goal.considerations.append(consideration)
	return goal


func _library(goals: Array) -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	for goal: BustleGoalDef in goals:
		library.goals.append(goal)
	return library


func _context(inputs: Dictionary = {}) -> BustleScoreContext:
	var context := BustleScoreContext.new()
	for key: Variant in inputs:
		context.inputs[StringName(str(key))] = float(inputs[key])
	return context


func _find(candidates: Array[BustleCandidate], goal_id: StringName, option_id: StringName = &"") -> BustleCandidate:
	for candidate: BustleCandidate in candidates:
		if candidate.goal_id == goal_id and candidate.option_id == option_id:
			return candidate
	return null


func _kinds(candidate: BustleCandidate) -> Array:
	return candidate.reasons.map(func(r: Dictionary) -> StringName: return r["kind"])


func test_a_goal_scores_its_base_weight_times_its_considerations() -> void:
	var goal := _goal(&"rest", BustleBands.PERSONAL, [&"need.sleep", &"time.evening"], 0.8)
	var found := _scorer.evaluate(_library([goal]), _context({"need.sleep": 0.5, "time.evening": 0.25}), _config)
	assert_almost_eq(found[0].raw_score, 0.8 * 0.5 * 0.25, 1e-6)
	assert_true(found[0].eligible)
	assert_eq(_kinds(found[0]).count(&"consideration"), 2, "each factor is explained")


func test_curve_inputs_are_clamped_to_the_domain_and_outputs_are_not() -> void:
	var span := Curve.new()
	span.add_point(Vector2(0.2, 0.3))
	span.add_point(Vector2(0.6, 0.7))
	assert_almost_eq(span.sample(0.0), 0.3, 1e-5, "before the first point: its value")
	assert_almost_eq(span.sample(1.0), 0.7, 1e-5, "after the last point: its value")
	assert_almost_eq(_line(0, 0, 1, 1).sample(5.0), 1.0, 1e-5, "beyond the domain: clamped")
	var overshoot := Curve.new()
	overshoot.add_point(Vector2(0, 0), 0, 20)
	overshoot.add_point(Vector2(1, 0), -20, 0)
	var goal := _goal(&"g", BustleBands.PERSONAL)
	var consideration := BustleConsideration.new()
	consideration.input = &"need.food"
	consideration.curve = overshoot
	goal.considerations.append(consideration)
	var found := _scorer.evaluate(_library([goal]), _context({"need.food": 0.5}), _config)
	assert_gt(found[0].raw_score, overshoot.max_value, "a tangent overshoot is kept, not clamped")


func test_a_missing_input_is_not_sampled_even_when_the_curve_starts_above_zero() -> void:
	var goal := _goal(&"g", BustleBands.PERSONAL)
	var consideration := BustleConsideration.new()
	consideration.input = &"need.food"
	consideration.curve = _line(0, 1, 1, 1)
	goal.considerations.append(consideration)
	var found := _scorer.evaluate(_library([goal]), _context(), _config)
	assert_false(found[0].eligible)
	assert_eq(found[0].raw_score, 0.0)
	assert_has(_kinds(found[0]), &"missing_input")


func test_malformed_and_non_finite_inputs_are_refused_with_reasons() -> void:
	var bad_name := _goal(&"a", BustleBands.PERSONAL, [&"hunger"])
	var bad_value := _goal(&"b", BustleBands.PERSONAL, [&"need.food"])
	var found := _scorer.evaluate(_library([bad_name, bad_value]), _context({"hunger": 1.0, "need.food": INF}), _config)
	assert_has(_kinds(_find(found, &"a")), &"invalid_input")
	assert_has(_kinds(_find(found, &"b")), &"not_finite")
	assert_false(_find(found, &"a").eligible or _find(found, &"b").eligible)
	assert_true(BustleInputs.is_valid_input(&"fact.door_open"))
	assert_true(BustleInputs.is_valid_input(&"health"))
	assert_false(BustleInputs.is_valid_input(&"health.left"))
	assert_false(BustleInputs.is_valid_input(&"need."))
	assert_false(BustleInputs.is_valid_input(&"need.Food"))


func test_preconditions_gate_a_goal() -> void:
	var by_input := _goal(&"a", BustleBands.PERSONAL)
	by_input.preconditions = [{"kind": &"input", "input": &"memory.food_known"}]
	var by_host := _goal(&"b", BustleBands.PERSONAL)
	by_host.preconditions = [{"kind": &"knows_place", "tag": &"food"}]
	var context := _context({"memory.food_known": 0.0})
	var found := _scorer.evaluate(_library([by_input, by_host]), context, _config)
	assert_false(_find(found, &"a").eligible, "an input precondition at zero fails")
	assert_false(_find(found, &"b").eligible, "another kind fails with no check to ask")
	context.inputs[&"memory.food_known"] = 1.0
	context.precondition_check = func(_id: StringName, pre: Dictionary) -> bool: return pre["tag"] == &"food"
	found = _scorer.evaluate(_library([by_input, by_host]), context, _config)
	assert_true(_find(found, &"a").eligible and _find(found, &"b").eligible)


## company: relief 0.8; solitude: side effect 0.5, weight 2; tag social ×1.5.
func _social_ad() -> BustleAdvertisement:
	return BustleAdvertisement.new(&"common_room", {&"company": 0.8}, {&"solitude": 0.5}, [&"social"], 5.0)


func _ad_context() -> BustleScoreContext:
	var context := _context({"need.company": 0.5, "need.solitude": 0.6})
	context.need_weights[&"solitude"] = 2.0
	context.tag_mults[&"social"] = 1.5
	return context


func test_the_advertisement_formula_is_signed_and_matches_hand_values() -> void:
	# 0.8 × 0.5 × 1 − 0.5 × (0.6 + 0.2) × 2 = 0.4 − 0.8 = −0.4; × 1.5 = −0.6.
	assert_almost_eq(_scorer.advertisement_score(_social_ad(), _ad_context(), _config), -0.6, 1e-6)
	var relief_only := BustleAdvertisement.new(&"porch", {&"company": 0.8}, {}, [&"social"])
	assert_almost_eq(_scorer.advertisement_score(relief_only, _ad_context(), _config), 0.4 * 1.5, 1e-6)
	var unknown_need := BustleAdvertisement.new(&"chapel", {&"devotion": 1.0})
	var reasons: Array[Dictionary] = []
	assert_eq(_scorer.advertisement_score(unknown_need, _ad_context(), _config, reasons), 0.0, "a need the agent lacks adds nothing")
	assert_eq(reasons[0]["kind"], &"no_need")


func test_need_curves_distance_mood_and_preview_multiply_in_and_default_to_one() -> void:
	var ad := BustleAdvertisement.new(&"porch", {&"company": 1.0}, {}, [&"social"], 5.0)
	var context := _context({"need.company": 0.5})
	assert_almost_eq(_scorer.advertisement_score(ad, context, _config), 0.5, 1e-6, "everything unset is neutral")
	_config.need_curves[&"company"] = _line(0, 0, 1, 2)
	_config.distance_curve = _line(0, 1, 10, 0)
	assert_almost_eq(_scorer.advertisement_score(ad, context, _config), 1.0 * 0.5, 1e-6, "curve ×2 at 0.5, half the distance")
	_config.mood_curves[&"social"] = _line(0, 0.5, 100, 1.5)
	assert_almost_eq(_scorer.advertisement_score(ad, context, _config), 0.5, 1e-6, "no mood input: mood is 1.0")
	context.inputs[BustleInputs.MOOD] = 0.0
	assert_almost_eq(_scorer.advertisement_score(ad, context, _config), 0.25, 1e-6, "low mood halves social")
	_config.expected_thought_gain = func(_ad: BustleAdvertisement, _c: BustleScoreContext) -> float: return 2.0
	assert_almost_eq(_scorer.advertisement_score(ad, context, _config), 0.5, 1e-6)
	_config.expected_thought_gain = func(_ad: BustleAdvertisement, _c: BustleScoreContext) -> float: return INF
	assert_true(is_nan(_scorer.advertisement_score(ad, context, _config)), "a non-finite factor is refused")


func test_a_goal_using_advertisements_scores_each_option_and_skips_repeats() -> void:
	var goal := _goal(&"use", BustleBands.PERSONAL)
	goal.uses_advertisements = true
	var context := _ad_context()
	context.advertisements = [_social_ad(), BustleAdvertisement.new(&"walk", {&"solitude": 1.0}, {}, [&"solitary"]),
		BustleAdvertisement.new(&"walk", {&"company": 9.0})]
	var found := _scorer.evaluate(_library([goal]), context, _config)
	assert_eq(found.size(), 2, "a repeated option id is used once")
	assert_almost_eq(_find(found, &"use", &"walk").raw_score, 1.0 * 0.6 * 2.0, 1e-6, "neutral goal: the raw advertisement score")
	assert_almost_eq(_find(found, &"use", &"common_room").raw_score, -0.6, 1e-6, "kept signed for diagnostics")
	assert_false(_find(found, &"use", &"common_room").eligible)
	assert_has(_kinds(_find(found, &"use", &"common_room")), &"not_positive")


func test_the_highest_eligible_band_wins_however_lower_bands_score() -> void:
	var rng := RandomNumberGenerator.new()
	var library := _library([_goal(&"flee", BustleBands.CRITICAL, [&"threat.near"], 0.1),
		_goal(&"chat", BustleBands.PERSONAL, [], 0.9)])
	var picked := _scorer.choose(_scorer.evaluate(library, _context({"threat.near": 1.0}), _config), _config, rng)
	assert_eq(picked.goal_id, &"flee")
	picked = _scorer.choose(_scorer.evaluate(library, _context({}), _config), _config, rng)
	assert_eq(picked.goal_id, &"chat", "an empty band is skipped")


func test_min_score_makes_a_weak_goal_ineligible_so_a_lower_band_can_win() -> void:
	var duty := _goal(&"shift", BustleBands.DUTY, [], 0.3)
	duty.min_score = 0.5
	var found := _scorer.evaluate(_library([duty, _goal(&"visit", BustleBands.PERSONAL, [], 0.2)]), _context(), _config)
	assert_has(_kinds(_find(found, &"shift")), &"below_minimum")
	assert_eq(_scorer.choose(found, _config, RandomNumberGenerator.new()).goal_id, &"visit")


func test_with_nothing_eligible_the_choice_is_the_idle_fallback() -> void:
	var found := _scorer.evaluate(_library([_goal(&"a", BustleBands.PERSONAL, [], 0.0),
		_goal(&"b", BustleBands.PERSONAL, [], -1.0)]), _context(), _config)
	var picked := _scorer.choose(found, _config, RandomNumberGenerator.new())
	assert_true(picked.fallback)
	assert_eq(picked.band, BustleBands.IDLE)


func test_the_window_is_inclusive_at_ninety_percent_and_ties_order_by_id() -> void:
	var found := _scorer.evaluate(_library([_goal(&"b", BustleBands.PERSONAL, [], 1.0),
		_goal(&"a", BustleBands.PERSONAL, [], 1.0), _goal(&"edge", BustleBands.PERSONAL, [], 0.9),
		_goal(&"out", BustleBands.PERSONAL, [], 0.8999)]), _context(), _config)
	var ids := found.map(func(c: BustleCandidate) -> StringName: return c.goal_id)
	assert_eq(ids, [&"a", &"b", &"edge", &"out"], "score first, then id")
	var window := BustleUtilityScorer.pick_window(BustleUtilityScorer.top_band(found), 0.10)
	assert_eq(window.map(func(c: BustleCandidate) -> StringName: return c.goal_id), [&"a", &"b", &"edge"])


func test_a_fixed_seed_repeats_its_picks_and_a_window_of_one_draws_nothing() -> void:
	var library := _library([_goal(&"a", BustleBands.PERSONAL), _goal(&"b", BustleBands.PERSONAL),
		_goal(&"c", BustleBands.PERSONAL), _goal(&"d", BustleBands.PERSONAL)])
	var found := _scorer.evaluate(library, _context(), _config)
	var runs: Array = []
	for run in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var picks: Array[StringName] = []
		for i in 1000:
			picks.append(_scorer.choose(found, _config, rng).goal_id)
		runs.append(picks)
	assert_eq(runs[0], runs[1], "the same seed gives the same 1,000 picks")
	for id: StringName in [&"a", &"b", &"c", &"d"]:
		assert_has(runs[0], id, "uniform: every option in the window comes up")
	var single := _scorer.evaluate(_library([_goal(&"only", BustleBands.PERSONAL)]), _context(), _config)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state := rng.state
	assert_eq(_scorer.choose(single, _config, rng).goal_id, &"only")
	assert_eq(rng.state, state, "no draw for a window of one")


func test_the_library_reports_repeated_ids_and_the_scorer_uses_the_first() -> void:
	var library := _library([_goal(&"a", BustleBands.PERSONAL, [], 0.5), _goal(&"a", BustleBands.CRITICAL, [], 1.0)])
	assert_eq(library.problems(), PackedStringArray(["goal a is listed twice"]))
	var found := _scorer.evaluate(library, _context(), _config)
	assert_eq(found.size(), 1)
	assert_eq(found[0].band, BustleBands.PERSONAL)


func test_an_input_precondition_must_be_finite_and_above_zero() -> void:
	var goal := _goal(&"eat", BustleBands.PERSONAL)
	goal.preconditions = [{"kind": &"input", "input": &"memory.food_known"}]
	for value: float in [INF, -INF, NAN]:
		var found := _scorer.evaluate(_library([goal]), _context({"memory.food_known": value}), _config)
		assert_false(found[0].eligible, "%s can't enable a goal" % value)
		assert_has(_kinds(found[0]), &"not_finite")
	assert_true(_scorer.evaluate(_library([goal]), _context({"memory.food_known": 1.0}), _config)[0].eligible)
	assert_false(_scorer.evaluate(_library([goal]), _context({"memory.food_known": 0.0}), _config)[0].eligible)
	goal.preconditions = [{"kind": &"input", "input": &"Memory.food"}]
	var bad := _scorer.evaluate(_library([goal]), _context({"Memory.food": 1.0}), _config)
	assert_false(bad[0].eligible)
	assert_has(_kinds(bad[0]), &"invalid_input")


func test_advertisement_inputs_are_checked_before_clamping_or_sampling() -> void:
	var goal := _goal(&"use", BustleBands.PERSONAL)
	goal.uses_advertisements = true
	var context := _context({"need.food": INF})
	context.advertisements = [BustleAdvertisement.new(&"table", {&"food": 1.0})]
	var found := _scorer.evaluate(_library([goal]), context, _config)
	assert_false(found[0].eligible, "INF pressure isn't clamped into a score of 1")
	assert_has(_kinds(found[0]), &"not_finite")
	context = _context({"need.Food": 1.0})
	context.advertisements = [BustleAdvertisement.new(&"table", {&"Food": 1.0})]
	found = _scorer.evaluate(_library([goal]), context, _config)
	assert_false(found[0].eligible, "a malformed need isn't scored")
	assert_has(_kinds(found[0]), &"invalid_input")
	context = _context({"need.food": 0.5})
	context.advertisements = [BustleAdvertisement.new(&"table", {&"food": 1.0}, {&"rest": 1.0})]
	found = _scorer.evaluate(_library([goal]), context, _config)
	assert_true(found[0].eligible, "an absent need, relief or side effect, still adds nothing")
	assert_eq(_kinds(found[0]).count(&"no_need"), 1)


func test_non_finite_distance_and_mood_are_refused_with_curves_set() -> void:
	_config.distance_curve = _line(0, 1, 10, 0)
	_config.mood_curves[&"social"] = _line(0, 0.5, 100, 1.5)
	var far := BustleAdvertisement.new(&"porch", {&"company": 1.0}, {}, [&"social"], INF)
	var reasons: Array[Dictionary] = []
	assert_true(is_nan(_scorer.advertisement_score(far, _context({"need.company": 0.5}), _config, reasons)))
	assert_eq(reasons.back()["what"], &"distance")
	var near := BustleAdvertisement.new(&"porch", {&"company": 1.0}, {}, [&"social"], 5.0)
	reasons.clear()
	assert_true(is_nan(_scorer.advertisement_score(near, _context({"need.company": 0.5, "mood": NAN}), _config, reasons)))
	assert_eq(reasons.back()["what"], BustleInputs.MOOD)


func test_the_score_doesnt_depend_on_the_order_needs_and_tags_were_given() -> void:
	var context := _context({"need.a": 0.3, "need.b": 0.7, "need.c": 0.9})
	context.tag_mults = {&"x": 1.1, &"y": 0.7, &"z": 1.3}
	var one := BustleAdvertisement.new(&"o", {&"a": 0.1, &"b": 0.2, &"c": 0.3}, {&"c": 0.4}, [&"x", &"y", &"z"])
	var two := BustleAdvertisement.new(&"o", {&"c": 0.3, &"a": 0.1, &"b": 0.2}, {&"c": 0.4}, [&"z", &"x", &"y"])
	assert_eq(_scorer.advertisement_score(one, context, _config), _scorer.advertisement_score(two, context, _config),
		"exactly equal, not just close")


func test_a_score_equal_to_min_score_is_eligible() -> void:
	var goal := _goal(&"shift", BustleBands.DUTY, [], 0.5)
	goal.min_score = 0.5
	assert_true(_scorer.evaluate(_library([goal]), _context(), _config)[0].eligible)


func test_a_repeated_option_is_recorded_on_the_first() -> void:
	var goal := _goal(&"use", BustleBands.PERSONAL)
	goal.uses_advertisements = true
	var context := _context({"need.company": 0.5})
	context.advertisements = [BustleAdvertisement.new(&"porch", {&"company": 1.0}), BustleAdvertisement.new(&"porch", {&"company": 9.0})]
	var found := _scorer.evaluate(_library([goal]), context, _config)
	assert_eq(found.size(), 1)
	assert_almost_eq(found[0].raw_score, 0.5, 1e-6, "the first one is used")
	assert_has(_kinds(found[0]), &"duplicate_option")
