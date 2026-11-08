# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The needs engine: rises per condition, recovery, profile rates, the social pair for a loner and
## an extrovert, relief on use, the scorer's inputs and curves, and saving.

var _loner := BustleModifierSet.new()
var _extrovert := BustleModifierSet.new()


func before_each() -> void:
	_loner = BustleModifierSet.new()
	_loner.set_source(&"loner", &"need.company.rate", 0.0, 0.4)
	_loner.set_source(&"loner", &"need.solitude.rate", 0.0, 1.5)
	_loner.set_source(&"loner", &"social.crowd_tolerance", -4.0)
	_extrovert = BustleModifierSet.new()
	_extrovert.set_source(&"extrovert", &"need.company.rate", 0.0, 1.6)
	_extrovert.set_source(&"extrovert", &"need.solitude.rate", 0.0, 0.3)
	_extrovert.set_source(&"extrovert", &"social.crowd_tolerance", 6.0)


func test_a_need_rises_only_under_its_conditions_and_falls_under_others() -> void:
	var needs := BustleNeedSet.new()
	needs.add_need(_need(&"rest", 0.1, [&"awake"], {&"asleep": -0.2}))
	needs.advance(120.0, [&"awake"])
	assert_almost_eq(needs.pressure(&"rest"), 0.2, 1e-6, "two waking hours")
	needs.advance(60.0, [&"asleep"])
	assert_almost_eq(needs.pressure(&"rest"), 0.0, 1e-6, "an hour asleep, clamped at 0")
	needs.advance(60.0, [])
	assert_eq(needs.pressure(&"rest"), 0.0, "no condition, no rise")
	needs.advance(6000.0, [&"awake"])
	assert_eq(needs.pressure(&"rest"), 1.0, "clamped at 1")


func test_a_need_with_no_conditions_always_rises_and_long_steps_equal_short_ones() -> void:
	var one := BustleNeedSet.new()
	var many := BustleNeedSet.new()
	for set: BustleNeedSet in [one, many]:
		set.add_need(_need(&"hunger", 0.07))
	one.advance(300.0, [])
	for i in 300:
		many.advance(1.0, [])
	assert_almost_eq(one.pressure(&"hunger"), 0.35, 1e-6)
	assert_almost_eq(many.pressure(&"hunger"), one.pressure(&"hunger"), 1e-6)


func test_the_rate_modifier_scales_the_rise_but_not_recovery() -> void:
	var needs := BustleNeedSet.new()
	needs.add_need(_need(&"company", 0.1, [&"alone"], {&"in_company": -0.3}))
	var fast := BustleModifierSet.new()
	fast.set_source(&"t", &"need.company.rate", 0.0, 2.0)
	needs.advance(60.0, [&"alone"], fast)
	assert_almost_eq(needs.pressure(&"company"), 0.2, 1e-6)
	needs.advance(30.0, [&"in_company"], fast)
	assert_almost_eq(needs.pressure(&"company"), 0.05, 1e-6, "recovery at its own rate")


func test_a_loners_solitude_rises_in_a_crowd_above_its_tolerance_only() -> void:
	var tolerance := BustleNeedSet.crowd_tolerance(_loner)
	assert_eq(tolerance, 2.0)
	var needs := _social()
	needs.advance(60.0, BustleNeedSet.social_conditions(2, tolerance), _loner)
	assert_eq(needs.pressure(&"solitude"), 0.0, "two people is within its tolerance")
	needs.advance(60.0, BustleNeedSet.social_conditions(5, tolerance), _loner)
	assert_almost_eq(needs.pressure(&"solitude"), 0.15, 1e-6, "five is a crowd: 0.1 × 1.5")
	var extrovert := _social()
	extrovert.advance(60.0, BustleNeedSet.social_conditions(5, BustleNeedSet.crowd_tolerance(_extrovert)), _extrovert)
	assert_eq(extrovert.pressure(&"solitude"), 0.0, "five isn't a crowd to an extrovert")


func test_an_extroverts_company_rises_alone_faster_than_a_loners() -> void:
	var extrovert := _social()
	var loner := _social()
	var alone := BustleNeedSet.social_conditions(0, 6.0)
	assert_eq(alone, [BustleNeedSet.ALONE] as Array[StringName])
	extrovert.advance(180.0, alone, _extrovert)
	loner.advance(180.0, alone, _loner)
	assert_almost_eq(extrovert.pressure(&"company"), 0.48, 1e-6, "0.1 × 1.6 × 3 h")
	assert_almost_eq(loner.pressure(&"company"), 0.12, 1e-6, "0.1 × 0.4 × 3 h")
	assert_eq(extrovert.pressure(&"solitude"), 0.0, "solitude falls or stays put alone")


func test_use_relieves_and_side_effects_raise_and_bad_numbers_are_ignored() -> void:
	var needs := BustleNeedSet.new()
	needs.add_need(_need(&"hunger", 0.0, [], {}, 0.8))
	needs.relieve(&"hunger", 0.5)
	assert_almost_eq(needs.pressure(&"hunger"), 0.3, 1e-6)
	needs.raise(&"hunger", 0.1)
	assert_almost_eq(needs.pressure(&"hunger"), 0.4, 1e-6)
	needs.relieve(&"hunger", NAN)
	needs.relieve(&"hunger", -1.0)
	needs.raise(&"nothing", 1.0)
	needs.advance(INF, [])
	assert_almost_eq(needs.pressure(&"hunger"), 0.4, 1e-6)
	assert_false(needs.set_pressure(&"hunger", INF))
	assert_false(needs.add_need(_need(&"hunger", 1.0)), "no second need with the same id")


func test_inputs_and_curves_feed_the_scorer() -> void:
	var needs := _social()
	var steep := Curve.new()
	steep.add_point(Vector2(0, 0))
	steep.add_point(Vector2(1, 1))
	var def := _need(&"hunger", 0.0, [], {}, 0.5)
	def.curve = steep
	needs.add_need(def)
	var inputs: Dictionary[StringName, float] = {}
	needs.fill_inputs(inputs)
	assert_eq(inputs.keys(), [&"need.company", &"need.hunger", &"need.solitude"])
	assert_eq(inputs[&"need.hunger"], 0.5)
	var config := BustleScoringConfig.new()
	needs.apply_curves(config)
	assert_same(config.need_curves[&"hunger"], steep)
	assert_false(config.need_curves.has(&"company"), "no curve, nothing copied")


func test_export_and_import_round_trip_and_bad_data_changes_nothing() -> void:
	var needs := _social()
	needs.set_pressure(&"company", 0.25)
	var saved := needs.export_state()
	var json: Variant = JSON.parse_string(JSON.stringify(saved))
	var other := _social()
	assert_true(other.import_state(json))
	assert_eq(other.export_state(), saved)
	assert_false(other.import_state({"pressures": {"company": "high"}}))
	assert_false(other.import_state([]))
	assert_eq(other.pressure(&"company"), 0.25, "unchanged")
	other.remove_need(&"company")
	assert_false(other.has_need(&"company"))
	assert_true(other.import_state(saved), "a need the set no longer has is skipped")


func _social() -> BustleNeedSet:
	var needs := BustleNeedSet.new()
	needs.add_need(_need(&"company", 0.1, [BustleNeedSet.ALONE], {BustleNeedSet.IN_COMPANY: -0.3}))
	needs.add_need(_need(&"solitude", 0.1, [BustleNeedSet.CROWDED], {BustleNeedSet.ALONE: -0.3}))
	return needs


func _need(id: StringName, rate: float, rises: Array[StringName] = [], conditions: Dictionary[StringName, float] = {}, start: float = 0.0) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = rises
	def.condition_rates = conditions
	def.start = start
	return def
