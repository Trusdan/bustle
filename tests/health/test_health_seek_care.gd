# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The seek-care goal: an agent whose need for care reaches the threshold, and who isn't downed,
## goes to the holder of a care role (or a care place) and waits there, where a healer's tend job
## can find it. The host moves the body; Bustle keeps no health state, makes no rolls, and a brain
## mid-way survives a save.

const Recovering := preload("res://tests/health/fake_recovering_port.gd")
const World := preload("res://tests/health/fake_world_port.gd")
const _Warn := preload("res://addons/bustle/core/warn_once.gd")
const STEP := 10

var _ports: BustlePorts
var _port: Recovering
var _world: World
var _health: BustleHealthBehaviour
var _seek: BustleSeekCare
var _job: BustleTendJob


func before_each() -> void:
	_Warn.reset()
	_ports = BustlePorts.new()
	_port = Recovering.new()
	_ports.health = _port
	_world = World.new()
	_world.areas = {&"healer": &"infirmary", &"p1": &"farm", &"p2": &"farm"}
	_world.set_place(&"infirmary", Vector3(10, 0, 0))
	_world.set_place(&"farm", Vector3(-10, 0, 0))
	_ports.world = _world
	_ports.roles.set_holder(&"doctor", &"healer")
	_health = BustleHealthBehaviour.new(null, _ports)
	_seek = BustleSeekCare.new(_health, [&"doctor"] as Array[StringName])
	_job = BustleTendJob.new(_health, func(healer: StringName) -> Array[StringName]:
		var near: Array[StringName] = []
		for id: StringName in [&"healer", &"p1", &"p2"]:
			if _world.area_of(id) == _world.area_of(healer):
				near.append(id)
		return near)


func after_each() -> void:
	_Warn.reset()


func _brain(id: StringName, with_tend: bool = false) -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(BustleSeekCare.goal_def(30))
	if with_tend:
		library.goals.append(BustleTendJob.goal_def(30))
	var shift := BustleGoalDef.new()
	shift.id = &"shift"
	shift.band = BustleBands.DUTY
	shift.tags = [&"work"]
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
	brain.runner.register(BustleSeekCare.ACTION, BustleSeekCareAction.new(_seek))
	brain.runner.register(BustleTendJob.ACTION, BustleTendAction.new(_job))
	return brain


func _tick(brain: BustleBrain, minute: int, extra: Dictionary = {}) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = minute
	_seek.fill_inputs(brain.agent_id, senses.inputs)
	_job.fill_inputs(brain.agent_id, senses.inputs)
	for key: StringName in extra:
		senses.inputs[key] = extra[key]
	return brain.tick(1.0, senses)


func test_care_is_sought_from_the_threshold_by_an_agent_who_is_up() -> void:
	var inputs: Dictionary[StringName, float] = {}
	for row: Array in [[0.0, false], [0.3, false], [0.5, true], [0.8, true]]:
		_port.care_needed = {&"p1": row[0]}
		_seek.fill_inputs(&"p1", inputs)
		assert_eq(inputs.has(BustleSeekCare.INPUT), row[1], "need %s" % row[0])
	assert_eq(inputs, {&"fact.seek_care": 0.8}, "the input is the need itself")
	_port.downed = [&"p1"]
	_seek.fill_inputs(&"p1", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float], "a downed agent doesn't seek care")
	_port.downed = []
	_seek.threshold = 0.9
	_seek.fill_inputs(&"p1", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float], "the threshold is a setting")


func test_the_destination_is_the_first_held_care_role_then_the_care_place() -> void:
	_seek.care_roles = [&"surgeon", &"doctor", &"nurse"]
	_ports.roles.set_holder(&"nurse", &"p2")
	assert_eq(_seek.destination_for(&"p1"), {"kind": &"agent", "target": &"healer"}, "the surgeon role is vacant")
	assert_eq(_seek.destination_for(&"healer"), {"kind": &"agent", "target": &"p2"}, "never itself")
	_port.downed = [&"healer"]
	assert_eq(_seek.destination_for(&"p1"), {"kind": &"agent", "target": &"p2"}, "never a downed holder")
	_port.downed = [&"healer", &"p2"]
	assert_eq(_seek.destination_for(&"p1"), {}, "no able holder, no care place")
	_seek.care_place = &"infirmary"
	_seek.where = func(_id: StringName) -> Variant: return null
	assert_eq(_seek.destination_for(&"p1"), {"kind": &"place", "target": &"infirmary"})
	_seek.care_place = &"nowhere"
	assert_eq(_seek.destination_for(&"p1"), {}, "a place the world port doesn't know isn't used")


func test_the_patient_goes_to_the_healer_and_waits_there_to_be_tended() -> void:
	_port.care_needed = {&"p1": 0.7}
	var patient := _brain(&"p1")
	var healer := _brain(&"healer", true)
	var first := _tick(patient, 0)
	assert_eq(first.goal_id, &"seek_care")
	assert_true(first.has_move_to)
	assert_eq(first.move_to, Vector3(10, 0, 0), "towards the healer's area")
	assert_eq(first.talk_to, &"healer")
	assert_eq(patient.runner.context.output["seek_care"], &"healer")
	assert_eq(_tick(healer, 0).goal_id, &"rest", "not near yet, so nobody to tend")
	assert_eq(_tick(patient, STEP).goal_id, &"seek_care", "still on the way")
	_world.areas[&"p1"] = &"infirmary"
	var there := _tick(patient, 2 * STEP)
	assert_eq(there.goal_id, &"seek_care")
	assert_false(there.has_move_to, "arrived: no more moving")
	assert_eq(_tick(patient, 3 * STEP).action, &"wait", "it waits there for care")
	assert_eq(_tick(healer, 3 * STEP).goal_id, &"tend", "now near, the tend job finds it")
	assert_eq(_port.calls, [[&"healer", &"p1"]], "the host was asked to care")


func test_recovering_on_the_way_ends_the_trip() -> void:
	_port.care_needed = {&"p1": 0.7}
	var patient := _brain(&"p1")
	assert_eq(_tick(patient, 0).action, &"seek_care")
	_port.care_needed = {&"p1": 0.1}
	assert_eq(_tick(patient, STEP).goal_id, &"rest", "below the threshold, it stops")
	assert_eq(_port.calls, [], "no care asked for")


func test_a_downed_or_busy_agent_does_not_seek_care() -> void:
	_port.care_needed = {&"p1": 0.9}
	_port.downed = [&"p1"]
	var downed := _brain(&"p1")
	assert_eq(_tick(downed, 0).goal_id, &"rest")
	assert_eq(_tick(downed, STEP, {&"fact.seek_care": 1.0}).goal_id, &"rest",
		"even with the input forced, the downed gate blocks travel")
	_port.downed = []
	var busy := _brain(&"p1")
	assert_eq(_tick(busy, 0, {&"fact.on_shift": 1.0}).goal_id, &"shift", "on duty, it doesn't go")
	assert_eq(_tick(busy, STEP).goal_id, &"seek_care", "free again, it does")


func test_nowhere_to_go_means_no_goal() -> void:
	_port.care_needed = {&"p1": 0.9}
	_seek.care_roles = []
	var brain := _brain(&"p1")
	assert_eq(_tick(brain, 0).goal_id, &"rest")
	assert_false(_seek.wants_care(&"p1"))
	var context := BustleActionContext.new()
	context.agent_id = &"p1"
	assert_eq(BustleSeekCareAction.new(_seek).tick(context, 1.0), BustleActionHandler.Status.FAILED)
	assert_eq(context.failure, &"no_care")
	var unset := BustleActionContext.new()
	assert_eq(BustleSeekCareAction.new().tick(unset, 1.0), BustleActionHandler.Status.FAILED)


func test_a_care_place_is_reached_within_reach_of_it() -> void:
	_seek.care_roles = []
	_seek.care_place = &"infirmary"
	var at := {&"p1": Vector3(-10, 0, 0)}
	_seek.where = func(id: StringName) -> Variant: return at.get(id)
	_port.care_needed = {&"p1": 0.6}
	var brain := _brain(&"p1")
	var going := _tick(brain, 0)
	assert_eq(going.move_to, Vector3(10, 0, 0), "towards the place")
	assert_eq(going.talk_to, &"", "nobody to talk to at a place")
	at[&"p1"] = Vector3(8.5, 0, 0)
	assert_false(_tick(brain, STEP).has_move_to, "within two metres: there")
	assert_eq(_tick(brain, 2 * STEP).action, &"wait")


func test_a_care_place_needs_a_way_to_tell_arrival() -> void:
	_seek.care_roles = []
	_seek.care_place = &"infirmary"
	_port.care_needed = {&"p1": 0.6}
	assert_eq(_seek.destination_for(&"p1"), {})
	assert_true(_Warn.has_warned("BustleSeekCare.care_place"))
	_seek.can_reach = func(_patient: StringName, _target: StringName) -> bool: return false
	assert_eq(_seek.destination_for(&"p1"), {"kind": &"place", "target": &"infirmary"})


func test_the_reach_hook_decides_arrival_and_a_wrong_answer_warns_once() -> void:
	var destination := {"kind": &"agent", "target": &"healer"}
	_seek.can_reach = func(_patient: StringName, target: StringName) -> bool: return target == &"healer"
	assert_true(_seek.has_reached(&"p1", destination), "the hook says so, in another area")
	_seek.can_reach = func(_patient: StringName, _target: StringName) -> Variant: return "yes"
	assert_false(_seek.has_reached(&"p1", destination), "falls back to the areas")
	assert_true(_Warn.has_warned("BustleSeekCare.can_reach.wrong_type"))
	_seek.where = func(_id: StringName) -> Variant: return "here"
	assert_eq(_seek.position_of(&"p1"), null)
	assert_true(_Warn.has_warned("BustleSeekCare.where.wrong_type"))


func test_a_threshold_out_of_range_warns_once_and_uses_the_default() -> void:
	_port.care_needed = {&"p1": 0.6, &"p2": 0.4}
	for bad: float in [NAN, -0.5, 1.5]:
		_seek.threshold = bad
		assert_eq(_seek.need(&"p1"), 0.6, "%s: 0.5 is used" % bad)
		assert_eq(_seek.need(&"p2"), 0.0)
	assert_true(_Warn.has_warned("BustleSeekCare.threshold"))
	_port.care_needed = {&"p1": INF}
	_seek.threshold = 0.5
	assert_eq(_seek.need(&"p1"), 0.0, "an unusable reading counts as none")


func test_a_seeking_brain_survives_a_save() -> void:
	_port.care_needed = {&"p1": 0.8}
	var first := _brain(&"p1")
	_tick(first, 0)
	_tick(first, STEP)
	var saved := first.export_state()
	var second := _brain(&"p1")
	assert_true(second.import_state(saved))
	var a: Array[String] = []
	var b: Array[String] = []
	for minute: int in range(2 * STEP, 200, STEP):
		if minute == 60:
			_world.areas[&"p1"] = &"infirmary"
		a.append("%s/%s" % [_tick(first, minute).goal_id, first.runner.context.output.get("seek_care", &"")])
		b.append("%s/%s" % [_tick(second, minute).goal_id, second.runner.context.output.get("seek_care", &"")])
	assert_eq(a, b, "the restored brain carries on the same")


func test_the_default_port_or_no_health_changes_nothing() -> void:
	var quiet := BustleSeekCare.new(BustleHealthBehaviour.new(null, BustlePorts.new()), [&"doctor"] as Array[StringName])
	var inputs: Dictionary[StringName, float] = {}
	quiet.fill_inputs(&"a", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float], "everyone is healthy")
	for none: BustleSeekCare in [BustleSeekCare.new(), BustleSeekCare.new(BustleHealthBehaviour.new(null, null))]:
		none.fill_inputs(&"a", inputs)
		assert_eq(inputs, {} as Dictionary[StringName, float])
		assert_eq(none.destination_for(&"a"), {})
		assert_false(none.has_reached(&"a", {"kind": &"agent", "target": &"b"}))
		assert_eq(none.position_for({"kind": &"place", "target": &"b"}), null)


func test_it_keeps_no_health_state_and_makes_no_rolls() -> void:
	var names: Array[String] = []
	for property: Dictionary in (BustleSeekCare as Script).get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["health", "threshold", "care_roles", "care_place", "where", "can_reach"] as Array[String],
		"settings and hooks only: no patients, destinations or readings kept")
	for path: String in ["seek_care.gd", "seek_care_action.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/health/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])


func test_the_goal_def_carries_its_band_and_wait() -> void:
	var goal := BustleSeekCare.goal_def(45, BustleBands.DUTY)
	assert_eq(goal.id, &"seek_care")
	assert_eq(goal.band, BustleBands.DUTY)
	assert_eq(goal.tags, [&"seek_care", &"travel"] as Array[StringName])
	assert_eq(goal.fail_cooldown_minutes, 45)
	assert_eq(goal.sequence.steps[1].params, {"minutes": 45})
	assert_eq(BustleSeekCare.goal_def().band, BustleBands.PERSONAL)
	assert_eq(BustleSeekCare.goal_def(-5).fail_cooldown_minutes, 0)
