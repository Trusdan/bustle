# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The learn_trade ambition template and its skill filler (BustleTradeTargets): off by default;
## once turned on, assigned to a curious agent with an installed skill below the line (passion
## first, else the lowest level, ties by id; the host can pin one); done when the level reaches the
## line or on trade_learned; moot only when the skill is gone or trade_unlearnable; the per-template
## cooldown; untargeted work and train boosts. No job is needed, and nothing is random.

const DAY := 1440

var _skills: BustleSkills
var _config: BustleAmbitionConfig
var _targets: BustleTradeTargets
var _ambitions: BustleAmbitions
var _curious: BustlePersonality


func before_each() -> void:
	var defs: Array[BustleSkillDef] = []
	for id: StringName in [&"cooking", &"crafts", &"farming"]:
		var def := BustleSkillDef.new()
		def.id = id
		defs.append(def)
	var passion := BustlePassionDef.new()
	passion.skill = &"farming"
	_skills = BustleSkills.new(defs, [passion] as Array[BustlePassionDef])
	_skills.assign_passion(&"baker", &"farming")
	_config = _only_learn_trade()
	_targets = BustleTradeTargets.new(_skills, _config)
	_ambitions = BustleAmbitions.new(&"baker", _config)
	_curious = BustlePersonality.new()
	_curious.set_slider(&"curiosity", 70.0)


# A library of only learn_trade, turned on.
func _only_learn_trade() -> BustleAmbitionConfig:
	var config := BustleAmbitionConfig.new()
	var learn := config.find(&"learn_trade")
	learn.enabled = true
	config.templates = [learn] as Array[BustleAmbitionDef]
	return config


# Fills the trade inputs (on top of [param extra]) and updates the ambition at [param now].
func _update(now: int, extra: Dictionary = {}) -> Dictionary:
	var inputs := extra.duplicate()
	_targets.fill(&"baker", _ambitions.active(), inputs, _curious)
	return _ambitions.update(now, _curious, inputs)


func test_the_template_is_in_the_default_library_switched_off() -> void:
	var learn := BustleAmbitionConfig.new().find(&"learn_trade")
	assert_not_null(learn)
	assert_false(learn.enabled, "off until a host turns it on")
	assert_eq(learn.weights, {&"curiosity": 1.0, &"diligence": 0.4} as Dictionary[StringName, float])
	assert_eq(learn.min_sliders, {&"curiosity": 50.0} as Dictionary[StringName, float])
	assert_eq(learn.requires, [&"has_trade_target"] as Array[StringName])
	assert_eq(learn.progress_input, &"skill_level")
	assert_eq(learn.target, 5.0)
	assert_eq(learn.done_fact, &"trade_learned")
	assert_eq(learn.moot_facts, [&"trade_skill_gone", &"trade_unlearnable"] as Array[StringName])
	assert_eq(learn.boosts, {&"work": 1.5, &"train": 2.0} as Dictionary[StringName, float])
	assert_eq(learn.target_input, &"", "boosts aren't narrowed to the skill")
	assert_eq(learn.subject_input, &"trade_skill")
	assert_eq(learn.next, &"")
	assert_true(learn.is_valid())


func test_switched_off_it_is_never_assigned() -> void:
	var library := BustleAmbitionConfig.new()
	for def: BustleAmbitionDef in library.templates:
		def.enabled = def.id == &"learn_trade"
	library.find(&"learn_trade").enabled = false
	_ambitions = BustleAmbitions.new(&"baker", library)
	_targets = BustleTradeTargets.new(_skills, library)
	assert_true(_update(0).is_empty(), "nothing else enabled, and learn_trade off")
	var keen := BustleAmbitions.new(&"baker", BustleAmbitionConfig.new())
	keen.pin = &"learn_trade"
	var inputs := {}
	_targets.fill(&"baker", {}, inputs, _curious)
	assert_true(inputs["has_trade_target"])
	assert_ne(keen.update(0, _curious, inputs).get("id", ""), "learn_trade", "not even pinned")


func test_assigned_to_a_curious_agent_with_no_job_needed() -> void:
	var started := _update(0)
	assert_eq(started.get("id"), "learn_trade", "no has_role, teacher or practice input")
	assert_eq(started["target"], "farming", "its passion, below the line")
	var dull := BustlePersonality.new()
	dull.set_slider(&"curiosity", 49.0)
	var other := BustleAmbitions.new(&"smith", _config)
	var inputs := {}
	_targets.fill(&"smith", {}, inputs, dull)
	assert_true(other.update(0, dull, inputs).is_empty(), "curiosity under 50")


func test_never_eligible_without_installed_skills() -> void:
	_targets = BustleTradeTargets.new(BustleSkillSet.new(), _config)
	var inputs := {}
	_targets.fill(&"baker", {}, inputs, _curious)
	assert_false(inputs["has_trade_target"], "the default port installs no skill")
	assert_false(inputs.has("trade_skill"))
	assert_true(_ambitions.update(0, _curious, inputs).is_empty())
	_targets = BustleTradeTargets.new(BustleSkills.new(), _config)
	assert_true(_update(0).is_empty(), "nor does a skills module with no defs")


func test_the_skill_is_the_passion_else_the_lowest_level_ties_by_id() -> void:
	assert_eq(_targets.target_for(&"baker", _curious), &"farming", "the passion qualifies")
	_skills.set_level(&"baker", &"farming", 5.0)
	assert_eq(_targets.target_for(&"baker", _curious), &"cooking", "passion at the line: lowest level, cooking before crafts")
	_skills.set_level(&"baker", &"cooking", 3.0)
	assert_eq(_targets.target_for(&"baker", _curious), &"crafts")
	_skills.set_level(&"baker", &"crafts", 5.0)
	_skills.set_level(&"baker", &"cooking", 5.0)
	assert_eq(_targets.target_for(&"baker", _curious), &"", "nothing below the line")
	var inputs := {}
	_targets.fill(&"baker", {}, inputs, _curious)
	assert_false(inputs["has_trade_target"])


func test_the_current_skill_is_kept_while_it_still_qualifies() -> void:
	_skills.set_level(&"baker", &"farming", 4.0)
	assert_eq(_update(0)["target"], "farming")
	_skills.remove_passion(&"baker", &"farming")
	_skills.set_level(&"baker", &"farming", 4.5)
	assert_eq(_update(10)["target"], "farming", "other skills are lower, but the current one is kept")
	assert_eq(_ambitions.active()["last_target"], "farming")


func test_the_host_can_pin_the_skill() -> void:
	var started := _update(0, {"trade_skill": "crafts"})
	assert_eq(started["target"], "crafts", "the host's pick over the passion")
	assert_eq(_update(10, {"trade_skill": "crafts"})["target"], "crafts")


func test_progress_then_completion_with_the_deed_and_the_cooldown() -> void:
	var social := BustleSocialStore.new()
	_ambitions.social = social
	watch_signals(_ambitions)
	_update(0)
	_skills.set_level(&"baker", &"farming", 3.0)
	assert_eq(_update(DAY)["progress"], 3.0, "progress is the level")
	_skills.set_level(&"baker", &"farming", 5.0)
	assert_true(_update(2 * DAY).is_empty(), "done at the line; the cooldown keeps it from starting again")
	assert_signal_emitted_with_parameters(_ambitions, "ambition_completed",
		[&"baker", &"learn_trade", {"id": "learn_trade", "since": 0, "progress": 3.0, "target": "farming",
			"last_target": "farming", "completed_at": 2 * DAY}])
	var deed: Dictionary = social.deeds_of(&"baker", 1)[0]
	assert_eq([deed["verb"], deed["target"]], [BustleAmbitions.DEED, &"learn_trade"])
	assert_true(_update(2 * DAY + 7 * DAY - 10).is_empty(), "still within 7 days")
	var again := _update(2 * DAY + 7 * DAY)
	assert_eq(again.get("id"), "learn_trade", "after the cooldown")
	assert_eq(again["target"], "cooking", "a different skill still below the line")


func test_trade_learned_completes_it() -> void:
	_update(0)
	watch_signals(_ambitions)
	_update(10, {"trade_learned": true})
	assert_signal_emitted(_ambitions, "ambition_completed")
	assert_true(_ambitions.active().is_empty())


func test_moot_only_when_the_skill_is_gone_or_unlearnable() -> void:
	_update(0)
	watch_signals(_ambitions)
	_update(10, {"has_role": false, "role_lost": true})
	assert_eq(_ambitions.active().get("id"), "learn_trade", "losing a job doesn't end it")
	_update(20, {"trade_unlearnable": true})
	assert_signal_emitted_with_parameters(_ambitions, "ended_moot", [&"baker", &"learn_trade", &"trade_unlearnable"])
	assert_true(_ambitions.active().is_empty(), "not eligible while the host says so")
	assert_eq(_update(30).get("target"), "farming", "and assigned again at once once it's lifted: no cooldown")
	var without_farming: Array[BustleSkillDef] = []
	for id: StringName in [&"cooking", &"crafts"]:
		var def := BustleSkillDef.new()
		def.id = id
		without_farming.append(def)
	_targets.skills = BustleSkills.new(without_farming)
	assert_true(_update(40).is_empty(), "its skill is no longer installed")
	assert_signal_emitted_with_parameters(_ambitions, "ended_moot", [&"baker", &"learn_trade", &"trade_skill_gone"])
	assert_eq(_update(50).get("target"), "cooking", "at the next update, another installed skill")


func test_boosts_work_and_train_for_any_option_and_never_a_fight() -> void:
	_update(0)
	assert_eq(_ambitions.boost(&"work", &"mill"), 1.5, "not narrowed to the skill")
	assert_eq(_ambitions.boost(&"work", &"farming"), 1.5)
	assert_eq(_ambitions.boost(&"work"), 1.5)
	assert_eq(_ambitions.boost(&"train", &"anyone"), 2.0, "a host with no train goal never asks")
	assert_eq(_ambitions.boost(&"explore"), 1.0)
	_config.find(&"learn_trade").boosts[&"steal"] = 3.0
	assert_eq(_ambitions.boost(&"steal"), 1.0, "never_boost holds")
	_update(10, {"locked": true})
	assert_eq(_ambitions.boost(&"work"), 1.0, "off while locked")
	assert_eq(_ambitions.active().get("id"), "learn_trade", "and still assigned")


func test_it_saves_and_loads_with_its_skill() -> void:
	_update(0)
	_skills.set_level(&"baker", &"farming", 2.0)
	_update(10)
	var saved := _ambitions.export_state()
	assert_eq(saved["active"]["target"], "farming")
	var loaded := BustleAmbitions.new(&"baker", _config)
	assert_true(loaded.import_state(saved.duplicate(true)))
	assert_eq(loaded.active(), _ambitions.active())
	assert_eq(loaded.boost(&"work", &"mill"), 1.5)


func test_the_same_inputs_give_the_same_run() -> void:
	var runs: Array = []
	for attempt: int in 2:
		before_each()
		var log: Array = []
		for step: int in 12:
			_skills.set_level(&"baker", StringName(["farming", "cooking", "crafts"][step % 3]), float(step) * 0.5)
			log.append(_update(step * DAY).duplicate())
		runs.append([log, _ambitions.export_state()])
	assert_eq(runs[1], runs[0])


func test_the_default_library_is_unchanged_with_it_off() -> void:
	var library := BustleAmbitionConfig.new()
	assert_eq(library.templates.map(func(d: BustleAmbitionDef) -> StringName: return d.id),
		[&"save_money", &"get_promoted", &"court_someone", &"settle_feud", &"leave_settlement", &"learn_trade", &"open_business"])
	var plain := BustleAmbitions.new(&"baker", library)
	var inputs := {}
	BustleTradeTargets.new(_skills, library).fill(&"baker", {}, inputs, _curious)
	assert_eq(plain.update(0, _curious, inputs).get("id"), "leave_settlement", "the same choice as without learn_trade")
