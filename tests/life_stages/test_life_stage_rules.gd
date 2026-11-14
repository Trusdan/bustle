# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Life-stage rules: a bad set is rejected with a clear reason, and the year length is the host's.


static func stage(id: StringName, min_days: float, goals: Array[StringName] = [], affordances: Array[StringName] = []) -> BustleLifeStageDef:
	var def := BustleLifeStageDef.new()
	def.id = id
	def.min_days = min_days
	def.blocked_goal_tags = goals
	def.blocked_affordance_tags = affordances
	return def


static func rules(stages: Array[BustleLifeStageDef], days_per_year: float = 100.0) -> BustleLifeStageRules:
	var out := BustleLifeStageRules.new()
	out.days_per_year = days_per_year
	out.stages = stages
	return out


static func three() -> BustleLifeStageRules:
	return rules([stage(&"young", 0.0, [&"labour"], [&"sharp"]), stage(&"grown", 1600.0), stage(&"old", 6000.0)])


func test_a_good_set_is_valid() -> void:
	assert_eq(three().validate(), "")
	assert_true(three().is_valid())


func test_a_bad_set_is_rejected_with_a_clear_reason() -> void:
	var cases: Array = [
		[rules([]), "there are no stages"],
		[rules([stage(&"a", 0.0), stage(&"a", 10.0)]), "stage id 'a' is used twice"],
		[rules([stage(&"a", 10.0), stage(&"b", 5.0)]), "stage 'b': min_days must be above the previous stage's ('a')"],
		[rules([stage(&"a", 10.0), stage(&"b", 10.0)]), "stage 'b': min_days must be above the previous stage's ('a')"],
		[rules([stage(&"a", -1.0)]), "stage 'a': min_days must be finite and not negative"],
		[rules([stage(&"a", NAN)]), "stage 'a': min_days must be finite and not negative"],
		[rules([stage(&"", 0.0)]), "stage 0 has no id"],
		[rules([stage(&"a", 0.0), null]), "stage 1 is missing"],
		[rules([stage(&"a", 0.0, [&""])]), "stage 'a': a blocked tag is empty"],
		[rules([stage(&"a", 0.0)], 0.0), "days_per_year must be a finite number above 0"],
		[rules([stage(&"a", 0.0)], INF), "days_per_year must be a finite number above 0"],
	]
	for row: Array in cases:
		assert_eq((row[0] as BustleLifeStageRules).validate(), row[1])
		assert_false((row[0] as BustleLifeStageRules).is_valid())


func test_the_module_refuses_bad_rules_and_stays_ageless() -> void:
	var module := BustleLifeStages.new(rules([stage(&"a", 0.0), stage(&"a", 9.0)]))
	assert_eq(module.error(), "stage id 'a' is used twice")
	assert_false(module.set_age(&"x", 5.0))
	assert_false(module.has_age(&"x"))
	assert_eq(module.stage_of(&"x"), &"")
	assert_true(module.allows_goal(&"x", [&"a"]))
	assert_eq(BustleLifeStages.new().error(), "no rules")


func test_the_year_length_is_configurable() -> void:
	var short := three()
	assert_eq(short.days_of(16.0), 1600.0)
	assert_eq(short.years_of(250.0), 2.5)
	var long := three()
	long.days_per_year = 400.0
	assert_eq(long.days_of(16.0), 6400.0)
	var module := BustleLifeStages.new(long)
	module.set_age(&"x", 800.0)
	assert_eq(module.age_years(&"x"), 2.0)
	assert_eq(module.age_days(&"x"), 800.0)


func test_stage_lookup_follows_the_minimums() -> void:
	var table := three()
	assert_eq(table.stage_for(0.0).id, &"young")
	assert_eq(table.stage_for(1599.9).id, &"young")
	assert_eq(table.stage_for(1600.0).id, &"grown")
	assert_eq(table.stage_for(99999.0).id, &"old")
	var late := rules([stage(&"grown", 100.0)])
	assert_null(late.stage_for(50.0), "younger than the first stage: none")
	assert_eq(table.find(&"old").min_days, 6000.0)
	assert_null(table.find(&"nobody"))
