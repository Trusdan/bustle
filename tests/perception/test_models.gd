# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The visibility and noise models.

const P := BustleStealthRules.Posture
const M := BustleStealthRules.Movement

var _rules: BustleStealthRules
var _seen: BustleVisibilityModel
var _noise: BustleNoiseModel


func before_each() -> void:
	_rules = BustleStealthRules.new()
	_seen = BustleVisibilityModel.new(_rules)
	_noise = BustleNoiseModel.new(_rules)


func test_standing_walking_in_full_light_is_1() -> void:
	assert_almost_eq(_seen.compute(1.0, P.STANDING, M.WALKING), 1.0, 0.001)


func test_darker_is_less_visible() -> void:
	var dark := _seen.compute(0.0, P.STANDING, M.WALKING)
	var dim := _seen.compute(0.5, P.STANDING, M.WALKING)
	var lit := _seen.compute(1.0, P.STANDING, M.WALKING)
	assert_lt(dark, dim)
	assert_lt(dim, lit)
	assert_almost_eq(dark, 0.1, 0.001, "the default curve starts at 0.1")
	assert_almost_eq(dim, 0.55, 0.001, "and is linear")


func test_crouched_and_still_is_less_visible_than_standing_and_running() -> void:
	var low := _seen.compute(1.0, P.CROUCHED, M.STILL)
	var high := _seen.compute(1.0, P.STANDING, M.RUNNING)
	assert_lt(low, high)
	assert_almost_eq(low, 0.55 * 0.6, 0.001)
	assert_almost_eq(high, 1.4, 0.001)


func test_wear_factor_scales_visibility() -> void:
	var neutral := _seen.compute(0.5, P.STANDING, M.WALKING, 1.0)
	assert_lt(_seen.compute(0.5, P.STANDING, M.WALKING, 0.8), neutral)
	assert_gt(_seen.compute(0.5, P.STANDING, M.WALKING, 1.2), neutral)


func test_skill_lowers_visibility_but_never_below_the_floor() -> void:
	var none := _seen.compute(1.0, P.STANDING, M.WALKING, 1.0, 0.0)
	var some := _seen.compute(1.0, P.STANDING, M.WALKING, 1.0, 40.0)
	var lots := _seen.compute(1.0, P.STANDING, M.WALKING, 1.0, 100.0)
	var absurd := _seen.compute(1.0, P.STANDING, M.WALKING, 1.0, 1000.0)
	assert_almost_eq(some, 0.8, 0.001)
	assert_almost_eq(lots, 0.5, 0.001, "100 points reach the 0.5 floor")
	assert_eq(absurd, lots, "never below the floor")
	assert_lt(some, none)
	assert_eq(_seen.compute(1.0, P.STANDING, M.WALKING, 1.0, -50.0), none, "negative skill adds nothing")


func test_visibility_stays_within_min_and_max() -> void:
	assert_eq(_seen.compute(0.0, P.CROUCHED, M.STILL, 0.1, 100.0), _rules.min_visibility)
	assert_eq(_seen.compute(1.0, P.STANDING, M.RUNNING, 3.0), _rules.max_visibility)
	for light in [0.0, 0.25, 0.5, 1.0, 2.0, -1.0]:
		var value := _seen.compute(light, P.STANDING, M.WALKING, 1.0)
		assert_between(value, _rules.min_visibility, _rules.max_visibility)


func test_a_null_curve_uses_the_light_level_itself() -> void:
	_rules.light_curve = null
	assert_almost_eq(_seen.compute(0.4, P.STANDING, M.WALKING), 0.4, 0.001)


func test_noise_multiplies_surface_and_gear() -> void:
	assert_almost_eq(_noise.compute(7.0), 7.0, 0.001)
	assert_almost_eq(_noise.compute(7.0, 1.5), 10.5, 0.001)
	assert_almost_eq(_noise.compute(7.0, 1.5, 0.5), 5.25, 0.001)
	assert_eq(_noise.compute(-3.0), 0.0, "never negative")


func test_skill_lowers_noise_but_never_below_the_floor() -> void:
	assert_almost_eq(_noise.compute(10.0, 1.0, 1.0, 50.0), 7.0, 0.001)
	assert_almost_eq(_noise.compute(10.0, 1.0, 1.0, 100.0), 4.0, 0.001, "100 points reach the 0.4 floor")
	assert_almost_eq(_noise.compute(10.0, 1.0, 1.0, 500.0), 4.0, 0.001)


func test_event_noise_is_a_plain_event_untouched_by_skill() -> void:
	var event := BustleNoiseModel.event_noise(10.0, Vector3(1, 0, 2), &"thrown")
	assert_eq(event.radius, 10.0)
	assert_eq(event.position, Vector3(1, 0, 2))
	assert_eq(event.source_id, &"thrown")
	assert_true(event.reaches(Vector3(1, 0, 11)))
	assert_false(event.reaches(Vector3(1, 0, 13)))
	assert_true(event.reaches(Vector3(1, 0, 13), 1.5), "a sharper ear")


func test_rules_round_trip_through_a_resource_file() -> void:
	_rules.crouched = 0.4
	var path := "user://test_bustle_stealth_rules.tres"
	assert_eq(ResourceSaver.save(_rules, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BustleStealthRules
	assert_not_null(loaded)
	assert_eq(loaded.crouched, 0.4)
	assert_almost_eq(loaded.light_factor(0.5), 0.55, 0.001)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
