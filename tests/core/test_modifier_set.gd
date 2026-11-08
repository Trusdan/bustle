# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The modifier set: add then multiply, order independence, replacing and removing a source, key
## validation, and filling a score context.


func test_adds_then_multiplies() -> void:
	var set := BustleModifierSet.new()
	assert_eq(set.value(&"need.company.rate", 1.0), 1.0, "no sources: the base")
	set.set_source(&"loner", &"need.company.rate", 0.0, 0.4)
	set.set_source(&"tired", &"need.company.rate", 0.5)
	assert_almost_eq(set.value(&"need.company.rate", 1.0), (1.0 + 0.5) * 0.4, 1e-9)
	assert_true(set.has(&"need.company.rate"))


func test_the_result_doesnt_depend_on_the_order_sources_were_set() -> void:
	var one := BustleModifierSet.new()
	var two := BustleModifierSet.new()
	var parts := [[&"a", 0.1, 1.3], [&"b", 0.7, 0.9], [&"c", 0.3, 1.7]]
	for part: Array in parts:
		one.set_source(part[0], &"work.speed", part[1], part[2])
	parts.reverse()
	for part: Array in parts:
		two.set_source(part[0], &"work.speed", part[1], part[2])
	assert_eq(one.value(&"work.speed", 1.0), two.value(&"work.speed", 1.0), "exactly equal")


func test_a_source_is_replaced_then_removed() -> void:
	var set := BustleModifierSet.new()
	set.set_source(&"trait", &"tag.social.mult", 0.0, 2.0)
	set.set_source(&"trait", &"tag.social.mult", 0.0, 3.0)
	assert_eq(set.value(&"tag.social.mult", 1.0), 3.0, "the later setting replaces the earlier")
	set.set_source(&"trait", &"need.food.weight", 1.0)
	set.remove_source(&"trait")
	assert_false(set.has(&"tag.social.mult") or set.has(&"need.food.weight"))
	assert_eq(set.value(&"tag.social.mult", 1.0), 1.0)


func test_malformed_keys_and_non_finite_numbers_are_refused() -> void:
	var set := BustleModifierSet.new()
	assert_false(set.set_source(&"t", &"speed", 1.0))
	assert_false(set.set_source(&"t", &"Work.speed", 1.0))
	assert_false(set.set_source(&"t", &"work..speed", 1.0))
	assert_false(set.set_source(&"t", &"work.speed", INF))
	assert_false(set.set_source(&"t", &"work.speed", 0.0, NAN))
	assert_false(set.set_source(&"", &"work.speed", 1.0))
	assert_false(set.has(&"work.speed"))
	assert_push_error_count(6)


func test_it_fills_a_score_contexts_weights_and_multipliers() -> void:
	var set := BustleModifierSet.new()
	set.set_source(&"trait", &"need.company.weight", 0.0, 1.5)
	set.set_source(&"trait", &"tag.quiet.mult", 0.0, 1.6)
	var context := BustleScoreContext.new()
	set.fill_context(context, [&"company", &"food"], [&"quiet", &"social"])
	assert_eq(context.need_weights, {&"company": 1.5, &"food": 1.0})
	assert_almost_eq(context.tag_mults[&"quiet"], 1.6, 1e-9)
	assert_eq(context.tag_mults[&"social"], 1.0)
