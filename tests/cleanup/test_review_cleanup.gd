# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Review follow-ups: saves read back from JSON load, a death time is checked, a role that didn't
## vacate isn't reported, several director orders can reach one agent, a passion's thought must be
## held, recovery keeps a tag still shown, and romance can switch its jealousy entry off.

const LifeRules := preload("res://tests/life_stages/test_life_stage_rules.gd")
const DAY := 1440


static func _json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state))


func _life() -> BustleLifeStages:
	var module := BustleLifeStages.new(LifeRules.three())
	module.set_age(&"a", 1590.0)
	module.advance_to(DAY + 30)
	module.birth(&"b")
	module.advance_to(2 * DAY)
	module.note_death(&"c", "illness")
	return module


func test_a_life_stages_save_read_back_from_json_loads_the_same() -> void:
	var module := _life()
	var saved := module.export_state()
	var round_trip := _json(saved)
	assert_true(round_trip["now"] is float, "JSON turns whole minutes into floats")
	var loaded := BustleLifeStages.new(LifeRules.three())
	assert_true(loaded.import_state(round_trip))
	assert_eq(loaded.export_state(), saved)
	module.advance_to(40 * DAY)
	loaded.advance_to(40 * DAY)
	assert_eq(loaded.export_state(), module.export_state(), "and carries on exactly")


func test_a_life_stages_save_with_a_part_minute_or_a_bad_death_time_is_refused() -> void:
	var good := _life().export_state()
	var bad: Array[Dictionary] = []
	for i: int in 5:
		bad.append(good.duplicate(true))
	bad[0]["now"] = 2880.5
	bad[1]["anchors"]["a"] = [1590.0, 0.25]
	bad[2]["dead"]["c"]["at"] = 10.5
	bad[3]["dead"]["c"]["at"] = -1
	bad[4]["dead"]["c"]["at"] = 2 * DAY + 1
	var target := BustleLifeStages.new(LifeRules.three())
	target.set_age(&"q", 2000.0)
	var before := target.export_state()
	for saved: Dictionary in bad:
		assert_false(target.import_state(saved))
		assert_eq(target.export_state(), before, "a refused load changes nothing")
	var at_now := good.duplicate(true)
	at_now["dead"]["c"]["at"] = 2 * DAY
	assert_true(BustleLifeStages.new(LifeRules.three()).import_state(at_now), "a death at now is fine")


class StuckRoles extends BustleRolesPort:
	func set_holder(_role: StringName, _id: StringName) -> void:
		pass


func test_a_role_that_did_not_vacate_is_not_reported() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"a"}
	var module := BustleLifeStages.new(LifeRules.three())
	module.roles = StuckRoles.new(table)
	var vacated: Array = []
	module.vacated.connect(func(id: StringName, kind: StringName, what: StringName) -> void: vacated.append([id, kind, what]))
	assert_eq(module.note_death(&"a", "illness"), "")
	assert_eq(vacated, [], "the host's port kept the holder, so no vacancy")
	var working := BustleLifeStages.new(LifeRules.three())
	var other := BustleRoleTable.new()
	other.holders = {&"clerk": &"a"}
	working.roles = BustleRolesPort.new(other)
	working.vacated.connect(func(id: StringName, kind: StringName, what: StringName) -> void: vacated.append([id, kind, what]))
	working.note_death(&"a", "illness")
	assert_eq(vacated, [[&"a", &"role", &"clerk"]], "the default port vacates and reports")


func _director_with(events: Array[BustleEventDef]) -> BustleDirector:
	var director := BustleDirector.new()
	for def: BustleEventDef in events:
		director.add_event(def)
	return director


func test_a_director_save_read_back_from_json_loads_the_same() -> void:
	var def := BustleEventDef.new()
	def.id = &"a"
	def.cooldown_minutes = 60
	var director := _director_with([def])
	director.update(0)
	director.update(120)
	var saved := director.export_state()
	var round_trip := _json(saved)
	assert_true(round_trip["last"]["a"] is float)
	var loaded := _director_with([def])
	assert_true(loaded.import_state(round_trip))
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.update(150), director.update(150), "the cooldown carries over")
	var part := saved.duplicate(true)
	part["history"][0][1] = 0.5
	var target := _director_with([def])
	var before := target.export_state()
	assert_false(target.import_state(part))
	assert_eq(target.export_state(), before)
	var part_last := saved.duplicate(true)
	part_last["last"]["a"] = 120.5
	assert_false(target.import_state(part_last))


func test_two_order_effects_in_one_event_both_reach_one_agent() -> void:
	var effects: Array[BustleEventEffect] = []
	for i: int in 2:
		var step := BustleActionStep.new()
		step.action = &"wait"
		step.params = {"minutes": 30}
		var sequence := BustleActionSequence.new()
		sequence.steps.append(step)
		var effect := BustleEventEffect.new()
		effect.kind = BustleEventEffect.ORDER
		effect.sequence = sequence
		effect.target_ids = [&"a"]
		effects.append(effect)
	var def := BustleEventDef.new()
	def.id = &"call"
	def.effects = effects
	var brain := BustleBrain.new(&"a")
	var applier := BustleDirectorEffects.new()
	applier.brain_of = func(_id: StringName) -> BustleBrain: return brain
	var out := applier.apply(def, 100)
	assert_eq(out.map(func(r: Dictionary) -> Array: return [r["what"], r["done"]]), [[&"call.100", true], [&"call.100.1", true]])
	assert_eq(brain.orders.ids(), [&"call.100", &"call.100.1"] as Array[StringName], "both queued")


func test_a_passion_thought_must_be_a_held_thought() -> void:
	var passion := BustlePassionDef.new()
	passion.skill = &"farming"
	assert_true(passion.is_valid(), "no thought is fine")
	var held := BustleThoughtDef.new()
	held.id = &"enjoying_work"
	held.value = 4.0
	passion.thought = held
	assert_true(passion.is_valid(), "a held thought is fine")
	var timed := BustleThoughtDef.new()
	timed.id = &"enjoying_work"
	timed.value = 4.0
	timed.duration_hours = 2.0
	passion.thought = timed
	assert_false(passion.is_valid(), "a timed thought isn't")
	passion.thought = BustleSkillDef.new()
	assert_false(passion.is_valid(), "another resource isn't")


class TwoTags extends BustleHealthPort:
	var tags: Array[StringName] = []

	func visible_tags(_id: StringName) -> Array[StringName]:
		return tags


func test_recovering_keeps_a_tag_still_shown() -> void:
	var ports := BustlePorts.new()
	var port := TwoTags.new()
	port.tags = [&"sick", &"fever"]
	ports.health = port
	var health := BustleHealthBehaviour.new(null, ports)
	var mood := BustleMood.new()
	health.illness_began(&"a", &"sick", mood)
	health.illness_began(&"a", &"fever", mood)
	port.tags = [&"fever"]
	health.recovered(&"a", mood)
	assert_eq(mood.count(&"feeling_sick"), 0, "the recovered tag's thought goes")
	assert_eq(mood.count(&"feverish"), 1, "the tag still shown keeps its thought")


func test_romance_can_switch_the_jealousy_entry_off_with_no_length() -> void:
	var rules := BustleRomanceRules.new()
	rules.jealousy_opinion_value = 0.0
	rules.jealousy_opinion_days = 0.0
	assert_true(rules.is_valid(), "off, with no length")
	rules.jealousy_opinion_value = 4.0
	assert_false(rules.is_valid(), "on, it needs a length")
	rules.jealousy_opinion_days = 2.0
	assert_true(rules.is_valid(), "a positive value is allowed")
	rules.jealousy_opinion_days = INF
	assert_false(rules.is_valid())


func test_rings_drop_the_cached_roster_when_the_society_changes() -> void:
	var first := BustleSociety.new(1)
	var second := BustleSociety.new(1)
	for society: BustleSociety in [first, second]:
		society.register_archetype(&"plain", BustleGoalLibrary.new())
	first.add_agent(&"x", &"plain")
	first.add_agent(&"y", &"plain")
	second.add_agent(&"p", &"plain")
	second.add_agent(&"q", &"plain")
	assert_eq(first.roster_version, second.roster_version, "the same roster version")
	var rings := BustleSimRings.new(first)
	assert_eq(rings.call(&"_roster"), [&"x", &"y"] as Array[StringName])
	rings.society = second
	assert_eq(rings.call(&"_roster"), [&"p", &"q"] as Array[StringName], "the other society's agents, not a stale copy")
