# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The health behaviour: capacities scale work and movement, thoughts follow the port, inputs are
## filled while non-zero, the default port is quiet, and nothing of the body is kept.

const FakeHealth := preload("res://tests/health/fake_health_port.gd")

var _port: FakeHealth
var _health: BustleHealthBehaviour


func before_each() -> void:
	var ports := BustlePorts.new()
	_port = FakeHealth.new()
	ports.health = _port
	_health = BustleHealthBehaviour.new(null, ports)


func test_reduced_capacity_slows_the_matching_work_and_movement() -> void:
	var modifiers := BustleModifierSet.new()
	_port.capacities = {&"a": {&"moving": 0.5}}
	_health.apply(&"a", modifiers)
	assert_eq(modifiers.value(&"move.speed", 1.0), 0.5)
	assert_eq(modifiers.value(&"capacity.moving", 1.0), 0.5)
	assert_false(modifiers.has(&"work.speed"), "moving doesn't touch work")
	_port.capacities = {&"a": {&"manipulation": 0.25}}
	_health.apply(&"a", modifiers)
	assert_eq(modifiers.value(&"work.speed", 1.0), 0.25)
	assert_false(modifiers.has(&"move.speed"), "the old effect is gone")
	_port.capacities = {&"a": {&"moving": 0.5, &"consciousness": 0.5}}
	_health.apply(&"a", modifiers)
	assert_eq(modifiers.value(&"move.speed", 1.0), 0.25, "effects on one key multiply")
	assert_eq(modifiers.value(&"work.speed", 1.0), 0.5)
	assert_eq(modifiers.value(&"capacity.consciousness", 1.0), 0.5)


func test_it_combines_with_other_sources_and_clears_at_full_capacity() -> void:
	var modifiers := BustleModifierSet.new()
	modifiers.set_source(&"skill", &"work.speed", 0.5)
	_port.capacities = {&"a": {&"manipulation": 0.5}}
	_health.apply(&"a", modifiers)
	assert_eq(modifiers.value(&"work.speed", 1.0), 0.75, "(1 + 0.5) × 0.5")
	_port.capacities = {}
	_health.apply(&"a", modifiers)
	assert_eq(modifiers.value(&"work.speed", 1.0), 1.5, "back to the other source alone")
	assert_false(modifiers.has(&"capacity.manipulation"))


func test_the_curve_is_configurable() -> void:
	var config := BustleHealthConfig.defaults()
	config.effects[0].at_zero = 0.2
	config.effects[0].power = 2.0
	var health := BustleHealthBehaviour.new(config, _health.ports)
	var modifiers := BustleModifierSet.new()
	_port.capacities = {&"a": {&"moving": 0.5}}
	health.apply(&"a", modifiers)
	assert_almost_eq(modifiers.value(&"move.speed", 1.0), 0.2 + 0.8 * 0.25, 1e-9)
	_port.capacities = {&"a": {&"moving": -3.0}}
	health.apply(&"a", modifiers)
	assert_almost_eq(modifiers.value(&"move.speed", 1.0), 0.2, 1e-9, "clamped to 0")
	_port.capacities = {&"a": {&"moving": NAN}}
	health.apply(&"a", modifiers)
	assert_false(modifiers.has(&"move.speed"), "an unusable reading counts as full")


func test_thoughts_appear_and_clear_with_the_port() -> void:
	var mood := BustleMood.new()
	_port.pains = {&"a": 0.3}
	assert_eq(_health.sync(&"a", mood), [&"in_pain"] as Array[StringName])
	assert_eq(mood.count(&"in_pain"), 1)
	_port.pains = {&"a": 0.7}
	_port.tags = {&"a": [&"sick"]}
	assert_eq(_health.sync(&"a", mood), [&"in_great_pain", &"feeling_sick"] as Array[StringName])
	assert_eq(mood.count(&"in_pain"), 0, "the milder pain thought gives way")
	assert_eq(mood.count(&"in_great_pain"), 1)
	assert_eq(mood.count(&"feeling_sick"), 1)
	_health.sync(&"a", mood)
	assert_eq(mood.count(), 2, "held, not stacked")
	_port.pains = {}
	_port.tags = {}
	assert_eq(_health.sync(&"a", mood), [] as Array[StringName])
	assert_eq(mood.count(), 0, "they clear on recovery")


func test_thoughts_without_a_mood_are_just_reported() -> void:
	_port.pains = {&"a": 0.9}
	assert_eq(_health.sync(&"a"), [&"in_great_pain"] as Array[StringName])
	_health.tick(&"a", null)


func test_inputs_follow_the_port() -> void:
	var inputs: Dictionary[StringName, float] = {&"need.food": 0.4}
	_port.pains = {&"a": 0.5}
	_port.care_needed = {&"a": 0.8}
	_port.downed = [&"a"]
	_port.contagious = [&"a"]
	_health.fill_inputs(&"a", inputs)
	assert_eq(inputs, {&"need.food": 0.4, &"health.pain": 0.5, &"health.needs_care": 0.8, &"fact.downed": 1.0, &"fact.contagious": 1.0})
	for key: StringName in inputs:
		assert_true(BustleInputs.is_valid_input(key), String(key))
	_port.pains = {}
	_port.care_needed = {}
	_port.downed = []
	_port.contagious = []
	_health.fill_inputs(&"a", inputs)
	assert_eq(inputs, {&"need.food": 0.4}, "cleared with the port")
	assert_false(BustleInputs.is_valid_input(&"health.other"), "only the two health names")


func test_the_default_port_gives_a_quiet_tick() -> void:
	var health := BustleHealthBehaviour.new(null, BustlePorts.new())
	var modifiers := BustleModifierSet.new()
	var mood := BustleMood.new(null, modifiers)
	var inputs: Dictionary[StringName, float] = {}
	health.tick(&"a", modifiers, mood, inputs)
	assert_false(modifiers.has(&"work.speed") or modifiers.has(&"move.speed") or modifiers.has(&"capacity.moving"))
	assert_eq(mood.count(), 0)
	assert_eq(inputs, {} as Dictionary[StringName, float])
	assert_true(health.allows(&"a", [&"work"] as Array[StringName], [&"travel"] as Array[StringName]))
	BustleHealthBehaviour.new().tick(&"a", modifiers, mood, inputs)
	assert_eq(mood.count(), 0, "no ports at all: also quiet")
	var port := BustleHealthPort.new()
	assert_eq([port.capacity(&"a", &"moving"), port.pain(&"a"), port.needs_care(&"a"), port.is_contagious(&"a"),
		port.visible_tags(&"a"), port.care(&"b", &"a")], [1.0, 0.0, 0.0, false, [], false])


func test_it_keeps_no_body_state() -> void:
	var names: Array[String] = []
	for property: Dictionary in (BustleHealthBehaviour as Script).get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["config", "ports"] as Array[String], "only its config and ports: readings aren't kept")
	_port.pains = {&"a": 0.9}
	var mood := BustleMood.new()
	_health.sync(&"a", mood)
	_port.pains = {}
	assert_eq(_health.sync(&"a", mood), [] as Array[StringName], "nothing remembered between ticks")


func test_the_same_readings_give_the_same_results_and_survive_a_mood_save() -> void:
	_port.pains = {&"a": 0.7}
	_port.tags = {&"a": [&"sick"]}
	_port.capacities = {&"a": {&"moving": 0.4}}
	var exports: Array[Dictionary] = []
	for i: int in 2:
		var modifiers := BustleModifierSet.new()
		var mood := BustleMood.new(null, modifiers)
		mood.start(0)
		_health.tick(&"a", modifiers, mood)
		exports.append(mood.export_state())
		assert_eq(modifiers.value(&"move.speed", 1.0), 0.4)
	assert_eq(exports[0], exports[1])
	var loaded := BustleMood.new()
	var defs: Array[BustleThoughtDef] = []
	for rule: BustleHealthThought in _health.config.thoughts:
		defs.append(rule.thought)
	assert_true(loaded.import_state(exports[0], defs))
	_health.sync(&"a", loaded)
	assert_eq(loaded.count(), 2, "a tick after loading adds no second copy")
	for path: String in ["health_behaviour.gd", "health_config.gd", "health_effect.gd", "health_thought.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/health/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])


func test_a_bad_config_does_nothing() -> void:
	var config := BustleHealthConfig.defaults()
	config.effects[0].power = 0.0
	assert_eq(config.validate(), "effect 0 is not valid")
	var health := BustleHealthBehaviour.new(config, _health.ports)
	var modifiers := BustleModifierSet.new()
	_port.capacities = {&"a": {&"moving": 0.5}}
	_port.pains = {&"a": 0.9}
	health.apply(&"a", modifiers)
	assert_false(modifiers.has(&"move.speed"))
	assert_eq(health.sync(&"a", BustleMood.new()), [] as Array[StringName])
	var timed := BustleHealthConfig.defaults()
	timed.thoughts[0].thought.duration_hours = 2.0
	assert_eq(timed.validate(), "thought rule 0 is not valid", "a health thought must be held")
	assert_eq(BustleHealthConfig.defaults().validate(), "")
