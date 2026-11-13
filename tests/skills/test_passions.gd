# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Passions, work modifiers and the passion thought, with the demo's generic skills (cooking,
## farming, crafts) and their passions.

const DIR := "res://demo/skills/"
const DAY := BustleClockPort.MINUTES_PER_DAY


func _skills() -> BustleSkills:
	var defs: Array[BustleSkillDef] = []
	var passions: Array[BustlePassionDef] = []
	for id: String in ["cooking", "farming", "crafts"]:
		defs.append(load(DIR + id + ".tres"))
		passions.append(load(DIR + id + "_passion.tres"))
	return BustleSkills.new(defs, passions)


func _person(sliders: Dictionary) -> BustlePersonality:
	var personality := BustlePersonality.new()
	for slider: StringName in sliders:
		personality.set_slider(slider, sliders[slider])
	return personality


func test_the_demo_fixture_is_valid() -> void:
	var skills := _skills()
	assert_eq(skills.skill_ids(), [&"cooking", &"crafts", &"farming"] as Array[StringName])
	for skill: StringName in skills.skill_ids():
		assert_not_null(skills.passion_def_of(skill), skill)
	assert_push_warning_count(0)


# Acceptance (1): a passion speeds learning by its multiplier.
func test_a_passion_speeds_learning_by_its_multiplier() -> void:
	var skills := _skills()
	assert_true(skills.assign_passion(&"baker", &"cooking"))
	for hour: int in 30:
		skills.add_xp(&"baker", &"cooking", 10.0)
		skills.add_xp(&"smith", &"cooking", 10.0)
	assert_almost_eq(skills.xp_of(&"baker", &"cooking"), 450.0, 1e-9)
	assert_almost_eq(skills.xp_of(&"smith", &"cooking"), 300.0, 1e-9)
	assert_gt(skills.level(&"baker", &"cooking"), skills.level(&"smith", &"cooking"))
	skills.add_xp(&"baker", &"farming", 10.0)
	assert_almost_eq(skills.xp_of(&"baker", &"farming"), 10.0, 1e-9, "only the passion's skill")


func test_a_derived_passion_speeds_learning_too() -> void:
	var skills := _skills()
	var keen := _person({&"diligence": 85.0})
	skills.add_xp(&"baker", &"farming", 40.0, keen)
	assert_almost_eq(skills.xp_of(&"baker", &"farming"), 60.0, 1e-9)


func test_passions_derive_from_the_highest_slider_match() -> void:
	var skills := _skills()
	assert_eq(skills.passions_of(&"baker", _person({&"diligence": 80.0})), [&"farming"] as Array[StringName])
	assert_eq(skills.passions_of(&"baker", _person({&"diligence": 80.0, &"sociability": 90.0})),
			[&"cooking"] as Array[StringName], "the higher score wins")
	assert_eq(skills.passions_of(&"baker", _person({&"curiosity": 75.0, &"diligence": 75.0})),
			[&"crafts"] as Array[StringName], "a tie goes to the first skill id")
	assert_eq(skills.passions_of(&"baker", _person({&"diligence": 69.0})), [] as Array[StringName], "below the threshold")
	assert_eq(skills.passions_of(&"baker", BustlePersonality.new()), [] as Array[StringName], "average sliders")
	assert_eq(skills.passions_of(&"baker"), [] as Array[StringName], "no personality")


func test_derivation_thresholds_are_configurable() -> void:
	var skills := _skills()
	var person := _person({&"curiosity": 80.0, &"diligence": 90.0, &"sociability": 75.0})
	assert_eq(skills.derived_passions(person), [&"farming"] as Array[StringName])
	skills.max_derived_passions = 2
	assert_eq(skills.derived_passions(person), [&"farming", &"crafts"] as Array[StringName], "best first")
	skills.passion_min_score = 0.35
	assert_eq(skills.derived_passions(person), [&"farming"] as Array[StringName])
	skills.max_derived_passions = 0
	assert_true(skills.derived_passions(person).is_empty())


func test_same_sliders_give_the_same_passions() -> void:
	var person := _person({&"curiosity": 72.0, &"diligence": 71.0, &"sociability": 72.0})
	var first := _skills().passions_of(&"baker", person)
	for run: int in 5:
		assert_eq(_skills().passions_of(&"baker", person), first)
	assert_eq(first, [&"cooking"] as Array[StringName])


func test_an_assigned_passion_replaces_derived_ones() -> void:
	var skills := _skills()
	var keen := _person({&"diligence": 90.0})
	skills.assign_passion(&"baker", &"crafts")
	assert_eq(skills.passions_of(&"baker", keen), [&"crafts"] as Array[StringName])
	assert_null(skills.passion_of(&"baker", &"farming", keen))
	skills.remove_passion(&"baker", &"crafts")
	assert_eq(skills.passions_of(&"baker", keen), [&"farming"] as Array[StringName], "derived again")
	assert_false(skills.assign_passion(&"baker", &"weaving"), "no passion def")
	assert_false(skills.assign_passion(&"", &"crafts"))


func test_passion_defs_are_checked() -> void:
	var skills := _skills()
	var passion := BustlePassionDef.new()
	passion.skill = &"weaving"
	assert_false(skills.add_passion_def(passion), "no skill def")
	passion.skill = &"cooking"
	assert_false(skills.add_passion_def(passion), "already has one")
	passion.sliders[&"charm"] = 1.0
	assert_false(passion.is_valid(), "unknown slider")
	passion.sliders.clear()
	passion.learn_mult = 0.0
	assert_false(passion.is_valid())


# Acceptance (2): skill raises work speed through the modifier set.
func test_skill_raises_work_speed_and_quality() -> void:
	var skills := _skills()
	var modifiers := BustleModifierSet.new()
	skills.apply(&"baker", modifiers, &"cooking")
	assert_eq(modifiers.value(&"work.speed", 1.0), 1.0, "level 0 changes nothing")
	assert_eq(modifiers.value(&"work.quality", 0.0), 0.0)
	skills.set_level(&"baker", &"cooking", 10.0)
	skills.apply(&"baker", modifiers, &"cooking")
	assert_almost_eq(modifiers.value(&"work.speed", 1.0), 1.25, 1e-9, "half of +0.5 at half the top level")
	assert_almost_eq(modifiers.value(&"work.quality", 0.0), 0.5, 1e-9)
	assert_almost_eq(modifiers.value(&"work.speed.cooking", 1.0), 1.25, 1e-9)
	skills.set_level(&"baker", &"cooking", 20.0)
	skills.apply(&"baker", modifiers, &"cooking")
	assert_almost_eq(modifiers.value(&"work.speed", 1.0), 1.5, 1e-9, "higher level, higher speed")


func test_skill_combines_with_other_sources_and_clears() -> void:
	var skills := _skills()
	var modifiers := BustleModifierSet.new()
	modifiers.set_source(&"mental", &"work.speed", 0.0, 0.75)
	skills.set_level(&"baker", &"farming", 20.0)
	skills.apply(&"baker", modifiers, &"farming")
	assert_almost_eq(modifiers.value(&"work.speed", 1.0), 1.125, 1e-9, "(1 + 0.5) × 0.75")
	assert_false(modifiers.has(&"work.speed.cooking"), "only the skill in use")
	skills.apply(&"baker", modifiers, &"")
	assert_almost_eq(modifiers.value(&"work.speed", 1.0), 0.75, 1e-9, "no skill in use")
	assert_false(modifiers.has(&"work.speed.farming"))


func test_the_passion_thought_is_held_while_doing_that_work() -> void:
	var skills := _skills()
	var mood := BustleMood.new()
	var modifiers := BustleModifierSet.new()
	var keen := _person({&"diligence": 90.0})
	skills.apply(&"baker", modifiers, &"farming", keen, mood)
	assert_eq(mood.count(&"enjoying_work"), 1)
	assert_gt(mood.target(), mood.baseline())
	skills.apply(&"baker", modifiers, &"cooking", keen, mood)
	assert_eq(mood.count(&"enjoying_work"), 0, "not a passion")
	skills.apply(&"baker", modifiers, &"farming", keen, mood)
	skills.apply(&"baker", modifiers, &"", keen, mood)
	assert_eq(mood.count(&"enjoying_work"), 0, "stopped working")
	skills.apply(&"smith", modifiers, &"farming", BustlePersonality.new(), mood)
	assert_eq(mood.count(&"enjoying_work"), 0, "no passion, no thought")
	skills.apply(&"baker", modifiers, &"farming", keen, null)
	assert_push_error_count(0)


func test_passions_save_and_load() -> void:
	var skills := _skills()
	skills.assign_passion(&"baker", &"farming")
	skills.assign_passion(&"baker", &"cooking")
	skills.assign_passion(&"smith", &"crafts")
	skills.add_xp(&"baker", &"farming", 80.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(skills.export_state()))
	var copy := _skills()
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), skills.export_state())
	assert_eq(copy.assigned_passions(&"baker"), [&"cooking", &"farming"] as Array[StringName])
	assert_true(copy.import_state({"xp": {}}), "a save without passions")
	assert_true(copy.assigned_passions(&"baker").is_empty())


func test_import_refuses_bad_passions_and_changes_nothing() -> void:
	var skills := _skills()
	skills.assign_passion(&"baker", &"cooking")
	var before := skills.export_state()
	for passions: Variant in [[], {"baker": "cooking"}, {"baker": ["weaving"]}, {"baker": ["cooking", "cooking"]},
			{"": ["cooking"]}, {"baker": [3]}]:
		assert_false(skills.import_state({"xp": {}, "passions": passions}), str(passions))
		assert_eq(skills.export_state(), before, str(passions))


func test_forget_drops_assigned_passions() -> void:
	var skills := _skills()
	skills.assign_passion(&"baker", &"cooking")
	assert_eq(skills.agent_ids(), [&"baker"] as Array[StringName])
	skills.forget(&"baker")
	assert_true(skills.assigned_passions(&"baker").is_empty())
	assert_true(skills.agent_ids().is_empty())
