# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The tend job: a patient who needs care draws an able, free healer, who asks the host to care;
## the host's recovery is then faster. A downed or busy agent doesn't tend, nothing is kept, and a
## brain mid-tend survives a save.

const Recovering := preload("res://tests/health/fake_recovering_port.gd")
const STEP := 10

var _port: Recovering
var _health: BustleHealthBehaviour
var _job: BustleTendJob
var _around: Array[StringName] = []
var _tended: Array = []


func before_each() -> void:
	var ports := BustlePorts.new()
	_port = Recovering.new()
	ports.health = _port
	_health = BustleHealthBehaviour.new(null, ports)
	_around = [&"healer", &"p1", &"p2"]
	_job = BustleTendJob.new(_health, func(_healer: StringName) -> Array[StringName]: return _around)
	_tended = []
	_job.tended.connect(func(healer: StringName, patient: StringName, done: bool) -> void: _tended.append([healer, patient, done]))


func _brain(id: StringName = &"healer") -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(BustleTendJob.goal_def(30))
	var shift := BustleGoalDef.new()
	shift.id = &"shift"
	shift.band = BustleBands.DUTY
	shift.preconditions = [{"kind": &"input", "input": &"fact.on_shift"}]
	library.goals.append(shift)
	var rest := BustleGoalDef.new()
	rest.id = &"rest"
	rest.band = BustleBands.IDLE
	library.goals.append(rest)
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(id, library, config, 5)
	brain.gate = _health.allows
	brain.runner.register(BustleTendJob.ACTION, BustleTendAction.new(_job))
	return brain


func _tick(brain: BustleBrain, minute: int, extra: Dictionary = {}) -> String:
	var senses := BustleSenses.new()
	senses.now_minutes = minute
	_job.fill_inputs(brain.agent_id, senses.inputs)
	for key: StringName in extra:
		senses.inputs[key] = extra[key]
	return String(brain.tick(1.0, senses).goal_id)


func test_a_patient_who_needs_care_draws_an_able_healer() -> void:
	_port.care_needed = {&"p1": 0.4, &"p2": 0.7, &"healer": 0.9}
	assert_eq(_job.patient_for(&"healer"), &"p2", "the most urgent, never itself")
	var inputs: Dictionary[StringName, float] = {}
	_job.fill_inputs(&"healer", inputs)
	assert_eq(inputs, {&"fact.tend": 0.7})
	var brain := _brain()
	assert_eq(_tick(brain, 0), "tend")
	assert_eq(_port.calls, [[&"healer", &"p2"]], "it asked the host")
	assert_eq(_tended, [[&"healer", &"p2", true]])
	_port.care_needed = {&"p1": 0.5, &"p2": 0.5}
	assert_eq(_job.patient_for(&"healer"), &"p1", "ties in id order")


func test_urgency_scales_with_the_need_for_care() -> void:
	var scores: Array[float] = []
	for need: float in [0.2, 0.8]:
		_port.care_needed = {&"p1": need}
		var brain := _brain()
		_tick(brain, 0)
		var tend: Array = brain.last_candidates.filter(func(c: BustleCandidate) -> bool: return c.goal_id == &"tend")
		scores.append(tend[0].raw_score)
	assert_almost_eq(scores[1], scores[0] * 4.0, 1e-6)


func test_a_downed_or_busy_agent_does_not_tend() -> void:
	_port.care_needed = {&"p1": 0.9}
	_port.downed = [&"healer"]
	assert_eq(_job.patient_for(&"healer"), &"")
	var downed := _brain()
	assert_eq(_tick(downed, 0), "rest")
	assert_eq(_tick(downed, STEP, {&"fact.tend": 1.0}), "rest", "even with the input forced, the downed gate holds")
	_port.downed = []
	var busy := _brain()
	assert_eq(_tick(busy, 0, {&"fact.on_shift": 1.0}), "shift", "on duty, it doesn't tend")
	assert_eq(_port.calls, [], "no care asked for")
	assert_eq(_tick(busy, 2 * STEP), "tend", "free again, it does")


func test_nobody_to_tend_without_need_or_without_anyone_near() -> void:
	var brain := _brain()
	assert_eq(_tick(brain, 0), "rest")
	_port.care_needed = {&"p1": 0.9}
	_around = []
	assert_eq(_tick(brain, STEP), "rest", "nobody near")
	assert_eq(BustleTendJob.new(_health).patient_for(&"healer"), &"", "no nearby callable: nobody")


func test_tending_speeds_recovery_on_a_host_that_does_so() -> void:
	_port.care_needed = {&"p1": 0.9, &"p2": 0.9}
	_around = [&"healer", &"p1"]
	var brain := _brain()
	var recovered := {}
	for minute: int in range(0, 2000, STEP):
		_tick(brain, minute)
		_port.advance(STEP)
		for patient: StringName in [&"p1", &"p2"]:
			if not recovered.has(patient) and _port.care_needed[patient] == 0.0:
				recovered[patient] = minute
	assert_eq(_port.calls[0], [&"healer", &"p1"])
	assert_eq(_port.cared, [&"p1"] as Array[StringName], "only the tended patient")
	assert_true(recovered.has(&"p1") and recovered.has(&"p2"))
	assert_lt(recovered[&"p1"], recovered[&"p2"], "the tended patient recovers first")
	assert_eq(_tick(brain, 2000), "rest", "nothing left to tend")


func test_a_refused_request_waits_before_trying_again() -> void:
	_port.care_needed = {&"p1": 0.9}
	_port.answer = false
	var brain := _brain()
	_tick(brain, 0)
	assert_eq(_tended, [[&"healer", &"p1", false]])
	for minute: int in range(STEP, 30, STEP):
		_tick(brain, minute)
	assert_eq(_port.calls.size(), 1, "not asked again within the cooldown")
	_tick(brain, 40)
	assert_eq(_port.calls.size(), 2)


func test_a_tending_brain_survives_a_save() -> void:
	_port.care_needed = {&"p1": 0.9}
	var first := _brain()
	_tick(first, 0)
	_tick(first, STEP)
	var saved := first.export_state()
	var second := _brain()
	assert_true(second.import_state(saved))
	var a: Array[String] = []
	var b: Array[String] = []
	for minute: int in range(2 * STEP, 200, STEP):
		a.append(_tick(first, minute))
		b.append(_tick(second, minute))
	assert_eq(a, b, "the restored brain carries on the same")


func test_illness_thoughts_come_with_host_events_and_clear_on_recovery() -> void:
	var mood := BustleMood.new()
	assert_true(_health.illness_began(&"p1", &"sick", mood))
	assert_eq(mood.count(&"feeling_sick"), 1, "at once, on the event")
	assert_true(_health.illness_began(&"p1", &"fever", mood))
	assert_eq(mood.count(&"feverish"), 1)
	_health.illness_began(&"p1", &"sick", mood)
	assert_eq(mood.count(), 2, "held, not stacked")
	assert_false(_health.illness_began(&"p1", &"unknown", mood), "no rule for the tag")
	assert_false(_health.illness_began(&"", &"sick", mood))
	_health.recovered(&"p1", mood)
	assert_eq(mood.count(), 0, "cleared on recovery")
	_port.tags = {&"p1": [&"fever"]}
	assert_eq(_health.sync(&"p1", mood), [&"feverish"] as Array[StringName], "the port's tags drive it too")
	_port.tags = {}
	_health.sync(&"p1", mood)
	assert_eq(mood.count(), 0)


func test_it_keeps_no_health_state_and_the_default_port_is_quiet() -> void:
	var names: Array[String] = []
	for property: Dictionary in (BustleTendJob as Script).get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["health", "nearby"] as Array[String], "no patients or recovery kept")
	var quiet := BustleTendJob.new(BustleHealthBehaviour.new(null, BustlePorts.new()), func(_h: StringName) -> Array[StringName]: return [&"a", &"b"])
	var inputs: Dictionary[StringName, float] = {}
	quiet.fill_inputs(&"a", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float])
	assert_false(quiet.tend(&"a", &"b"), "the default port refuses care")
	assert_false(BustleTendJob.new().tend(&"a", &"b"))
	for path: String in ["tend_job.gd", "tend_action.gd", "health_behaviour.gd", "health_config.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/health/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])
