# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Personality: five agents with the same day and the same options choose differently from trait
## data alone; excluded traits can't combine; trait needs, goals and thoughts belong only to their
## agents; sliders reach the scorer; no trait has code; saving.

const TRAITS := "res://demo/traits/"
const TRAIT_FILES: Array[String] = ["loner", "outgoing", "low_spirited", "greedy", "pious"]

# The evening's options: id, relief, tags, head count (0 = alone).
const OPTIONS: Array = [
	[&"common_room", {&"company": 0.6}, [&"social"], 8],
	[&"porch", {&"company": 0.4, &"leisure": 0.2}, [&"social", &"quiet"], 2],
	[&"walk_alone", {&"solitude": 0.5, &"leisure": 0.4}, [&"solitary"], 0],
	[&"sit_at_home", {&"solitude": 0.4, &"leisure": 0.2}, [&"solitary"], 0],
	[&"evening_prayer", {&"devotion": 1.0, &"leisure": 0.1}, [&"devotional"], 5],
	[&"odd_job", {&"money": 0.6}, [&"work"], 0],
	[&"tavern", {&"company": 0.4, &"leisure": 0.3}, [&"social", &"indulgent"], 6],
]


func test_trait_data_alone_reproduces_five_agents_top_choices() -> void:
	var expected := {
		&"loner": &"walk_alone",
		&"outgoing": &"common_room",
		&"low_spirited": &"porch",
		&"greedy": &"odd_job",
		&"pious": &"evening_prayer",
	}
	for trait_id: StringName in expected:
		var scores := _evening(trait_id)
		var best := &""
		for option: StringName in scores:
			if best == &"" or scores[option] > scores[best]:
				best = option
		assert_eq(best, expected[trait_id], "%s: %s" % [trait_id, scores])
	assert_lt(_evening(&"loner")[&"common_room"], 0.0, "the crowded room scores below zero for the loner")


func test_a_permanent_thought_sets_the_low_spirited_agents_mood_target() -> void:
	var personality := BustlePersonality.new()
	personality.add_trait(_trait("low_spirited"))
	var modifiers := BustleModifierSet.new()
	var mood := BustleMood.new(null, modifiers)
	personality.apply(modifiers, null, null, mood)
	assert_eq(mood.target(), 38.0, "baseline 50 with a permanent −12")
	assert_eq(mood.reasons()[0]["reason"], {"kind": "trait", "trait": "low_spirited"})
	personality.remove_trait(&"low_spirited")
	personality.apply(modifiers, null, null, mood)
	assert_eq(mood.target(), 50.0, "the thought goes with the trait")
	assert_false(modifiers.has(&"tag.social.mult"), "and so do its modifiers")


func test_excluded_traits_cannot_be_combined() -> void:
	var personality := BustlePersonality.new()
	assert_eq(personality.add_trait(_trait("loner")), BustlePersonality.OK)
	assert_eq(personality.add_trait(_trait("outgoing")), BustlePersonality.EXCLUDED)
	var one_way := BustleTraitDef.new()
	one_way.id = &"shy"
	one_way.excludes = [&"loner"]
	assert_eq(personality.add_trait(one_way), BustlePersonality.EXCLUDED, "an exclusion works either way round")
	assert_eq(personality.add_trait(_trait("loner")), BustlePersonality.ALREADY)
	assert_eq(personality.add_trait(_trait("greedy")), BustlePersonality.OK)
	assert_eq(personality.add_trait(_trait("pious")), BustlePersonality.OK)
	assert_eq(personality.add_trait(_trait("low_spirited")), BustlePersonality.FULL, "three at most")
	var bad := BustleTraitDef.new()
	bad.id = &"odd"
	bad.mults = {&"Not A Key": 2.0}
	assert_eq(BustlePersonality.new().add_trait(bad), BustlePersonality.INVALID)
	bad.mults = {}
	bad.excludes = [&"odd"]
	assert_false(bad.is_valid(), "a trait can't exclude itself")


func test_a_trait_need_and_goal_appear_only_on_agents_with_that_trait() -> void:
	var with_trait := _agent([&"pious"])
	var without := _agent([&"greedy"])
	assert_true(with_trait["needs"].has_need(&"devotion"))
	assert_false(without["needs"].has_need(&"devotion"))
	assert_true(_goal_ids(with_trait["library"]).has(&"observe"))
	assert_false(_goal_ids(without["library"]).has(&"observe"))
	var personality: BustlePersonality = with_trait["personality"]
	personality.apply(with_trait["modifiers"], with_trait["needs"], with_trait["library"])
	assert_eq(_goal_ids(with_trait["library"]).count(&"observe"), 1, "applying again adds nothing twice")
	personality.remove_trait(&"pious")
	personality.apply(with_trait["modifiers"], with_trait["needs"], with_trait["library"])
	assert_false(with_trait["needs"].has_need(&"devotion"), "removed with the trait")
	assert_false(_goal_ids(with_trait["library"]).has(&"observe"))
	assert_true(with_trait["needs"].has_need(&"company"), "the agent's own needs stay")


func test_no_trait_has_code() -> void:
	for file: String in TRAIT_FILES:
		var path := TRAITS + file + ".tres"
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("GDScript"), "%s has no inline script" % path)
		var def := _trait(file)
		assert_eq((def.get_script() as Script).resource_path, "res://addons/bustle/core/personality/trait_def.gd")
		assert_true(def.is_valid(), "%s is valid data" % file)
		for line: String in text.split("\n"):
			if line.begins_with("[ext_resource") and line.contains("Script"):
				assert_true(line.contains("res://addons/bustle/"), "%s only uses Bustle's own data classes" % path)


func test_sliders_reach_the_scorer_with_trait_shifts() -> void:
	var personality := BustlePersonality.new()
	assert_eq(personality.slider(&"sociability"), 50.0)
	assert_true(personality.set_slider(&"sociability", 90.0))
	assert_false(personality.set_slider(&"charisma", 10.0), "only the eight sliders")
	assert_false(personality.set_slider(&"calm", NAN))
	personality.add_trait(_trait("outgoing"))
	assert_eq(personality.slider(&"sociability"), 100.0, "shifted by the trait, clamped")
	var inputs: Dictionary[StringName, float] = {}
	personality.fill_inputs(inputs)
	assert_eq(inputs.size(), 8)
	assert_eq(inputs[&"trait.sociability"], 1.0)
	assert_eq(inputs[&"trait.calm"], 0.5)
	for key: StringName in inputs:
		assert_true(BustleInputs.is_valid_input(key))


func test_personality_saves_and_bad_data_changes_nothing() -> void:
	var defs: Array[BustleTraitDef] = []
	for file: String in TRAIT_FILES:
		defs.append(_trait(file))
	var personality := BustlePersonality.new()
	personality.set_slider(&"kindness", 70.0)
	personality.add_trait(defs[0])
	personality.add_trait(defs[3])
	var saved := personality.export_state()
	assert_eq(saved, {"sliders": {"kindness": 70.0}, "traits": ["loner", "greedy"]})
	var other := BustlePersonality.new()
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved)), defs))
	assert_eq(other.export_state(), saved)
	assert_false(other.import_state({"sliders": {}, "traits": ["loner", "outgoing"]}, defs), "excluded pair")
	assert_false(other.import_state({"sliders": {}, "traits": ["unknown"]}, defs))
	assert_false(other.import_state({"sliders": {"charisma": 3}, "traits": []}, defs))
	assert_eq(other.export_state(), saved, "refused imports change nothing")


# One agent's evening: the same day and options for everyone; only [param trait_id] differs.
func _evening(trait_id: StringName) -> Dictionary:
	var agent := _agent([trait_id])
	var needs: BustleNeedSet = agent["needs"]
	var modifiers: BustleModifierSet = agent["modifiers"]
	var tolerance := BustleNeedSet.crowd_tolerance(modifiers)
	for minute in range(8 * 60, 12 * 60, 30):
		needs.advance(30.0, BustleNeedSet.social_conditions(3, tolerance), modifiers)
	for minute in range(12 * 60, 18 * 60, 30):
		needs.advance(30.0, [BustleNeedSet.ALONE], modifiers)
	var context := BustleScoreContext.new()
	needs.fill_inputs(context.inputs)
	modifiers.fill_context(context, needs.ids(), [&"social", &"quiet", &"solitary", &"devotional", &"work", &"indulgent"])
	var scorer := BustleUtilityScorer.new()
	var scores := {}
	for option: Array in OPTIONS:
		var relief: Dictionary[StringName, float] = {}
		relief.assign(option[1])
		var adds: Dictionary[StringName, float] = {}
		if int(option[3]) > tolerance:
			adds[&"solitude"] = 0.3
		var tags: Array[StringName] = []
		tags.assign(option[2])
		scores[option[0]] = scorer.advertisement_score(BustleAdvertisement.new(option[0], relief, adds, tags), context, BustleScoringConfig.new())
	return scores


# The same base agent for everyone: its needs, an empty library, and the given traits applied.
func _agent(trait_ids: Array[StringName]) -> Dictionary:
	var needs := BustleNeedSet.new()
	needs.add_need(_need(&"company", 0.08, [BustleNeedSet.ALONE], {BustleNeedSet.IN_COMPANY: -0.3}))
	needs.add_need(_need(&"solitude", 0.1, [BustleNeedSet.CROWDED], {}))
	needs.add_need(_need(&"money", 0.02, [], {}))
	needs.add_need(_need(&"leisure", 0.0, [], {}, 0.3))
	var modifiers := BustleModifierSet.new()
	var library := BustleGoalLibrary.new()
	var personality := BustlePersonality.new()
	for id: StringName in trait_ids:
		assert_eq(personality.add_trait(_trait(String(id))), BustlePersonality.OK)
	personality.apply(modifiers, needs, library)
	return {"needs": needs, "modifiers": modifiers, "library": library, "personality": personality}


func _trait(file: String) -> BustleTraitDef:
	return load(TRAITS + file + ".tres") as BustleTraitDef


func _need(id: StringName, rate: float, rises: Array[StringName], conditions: Dictionary[StringName, float], start: float = 0.0) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = rises
	def.condition_rates = conditions
	def.start = start
	return def


func _goal_ids(library: BustleGoalLibrary) -> Array[StringName]:
	var out: Array[StringName] = []
	for goal: BustleGoalDef in library.goals:
		out.append(goal.id)
	return out
