# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Fetching a healer: a bystander who sees a downed or urgent patient, with no healer within reach,
## goes to the nearest healer by the fetch-help rule and tells it; the unchanged tend job then
## tends the patient. Errands end when the patient recovers or dies, survive a save, and nothing is
## random.

const Recovering := preload("res://tests/health/fake_recovering_port.gd")
const _Warn := preload("res://addons/bustle/core/warn_once.gd")
const STEP := 10

var _ports: BustlePorts
var _port: Recovering
var _health: BustleHealthBehaviour
var _fetch: BustleFetchHealer
var _at: Dictionary = {}
var _busy: Array[StringName] = []
var _dead: Array[StringName] = []
var _ended: Array = []


func before_each() -> void:
	_Warn.reset()
	_ports = BustlePorts.new()
	_port = Recovering.new()
	_ports.health = _port
	_ports.roles.set_holder(&"doctor", &"healer")
	_health = BustleHealthBehaviour.new(null, _ports)
	_at = {&"patient": Vector3.ZERO, &"bystander": Vector3(1, 0, 0), &"other": Vector3(2, 0, 0),
		&"healer": Vector3(50, 0, 0), &"far_healer": Vector3(90, 0, 0)}
	_busy = []
	_dead = []
	_ended = []
	_fetch = BustleFetchHealer.new(_health, [&"doctor"] as Array[StringName])
	_fetch.where = func(id: StringName) -> Variant: return _at.get(id)
	_fetch.is_busy = func(id: StringName) -> bool: return _busy.has(id)
	_fetch.is_dead = func(id: StringName) -> bool: return _dead.has(id)
	_fetch.errand_ended.connect(func(b: StringName, p: StringName, reason: StringName) -> void: _ended.append([b, p, reason]))
	_port.downed = [&"patient"]
	_port.care_needed = {&"patient": 0.9}


func after_each() -> void:
	_Warn.reset()


func _brain(id: StringName, tend: BustleTendJob = null) -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(BustleFetchHealer.goal_def())
	if tend != null:
		library.goals.append(BustleTendJob.goal_def(30))
	var idle := BustleGoalDef.new()
	idle.id = &"idle"
	idle.band = BustleBands.IDLE
	library.goals.append(idle)
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(id, library, config, 5)
	brain.gate = _health.allows
	brain.runner.register(BustleFetchHealer.ACTION, BustleFetchHealerAction.new(_fetch))
	if tend != null:
		brain.runner.register(BustleTendJob.ACTION, BustleTendAction.new(tend))
	return brain


func _tick(brain: BustleBrain, minute: int, tend: BustleTendJob = null) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = minute
	_fetch.fill_inputs(brain.agent_id, senses.inputs)
	if tend != null:
		tend.fill_inputs(brain.agent_id, senses.inputs)
	return brain.tick(1.0, senses)


func test_a_downed_or_urgent_patient_needs_a_healer() -> void:
	assert_eq(_fetch.urgency(&"patient"), 1.0, "downed")
	_port.downed = []
	assert_almost_eq(_fetch.urgency(&"patient"), 0.9, 1e-6, "urgent care: its need")
	_port.care_needed = {&"patient": 0.7}
	assert_eq(_fetch.urgency(&"patient"), 0.0, "below the urgent line")
	_fetch.urgent_at = 0.5
	_fetch.care_weight = 0.5
	assert_almost_eq(_fetch.urgency(&"patient"), 0.35, 1e-6, "the line and weight are settings")
	_port.downed = [&"patient"]
	_fetch.downed_weight = 0.6
	assert_almost_eq(_fetch.urgency(&"patient"), 0.6, 1e-6)
	_dead = [&"patient"]
	assert_eq(_fetch.urgency(&"patient"), 0.0, "the dead need no healer")


func test_a_free_bystander_sets_off_for_the_nearest_healer() -> void:
	_fetch.healers = func() -> Array[StringName]: return [&"far_healer"]
	assert_eq(_fetch.healers_for(&"patient"), [&"far_healer", &"healer"] as Array[StringName], "care roles and the hook")
	assert_false(_fetch.healer_within_reach(&"patient"))
	var started: Array = []
	_fetch.errand_started.connect(func(b: StringName, p: StringName, h: StringName) -> void: started.append([b, p, h]))
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer", "the nearer one")
	assert_eq(started, [[&"bystander", &"patient", &"healer"]])
	assert_eq(_fetch.errand_of(&"bystander"), {"patient": &"patient", "healer": &"healer", "since": 0})
	assert_eq(_fetch.errand_for(&"patient"), {"bystander": &"bystander", "healer": &"healer", "since": 0})
	assert_eq(_fetch.notice(&"other", &"patient", 0), &"", "one errand per patient")
	assert_eq(_fetch.notice(&"bystander", &"other", 0), &"", "one errand per bystander")


func test_nobody_sets_off_when_a_healer_is_near_or_the_bystander_cant() -> void:
	_at[&"healer"] = Vector3(10, 0, 0)
	assert_true(_fetch.healer_within_reach(&"patient"), "within 15 metres")
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"")
	_fetch.reach = 5.0
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer", "the reach is a setting")
	_fetch.drop(&"patient")
	_fetch.reach = 15.0
	_at[&"healer"] = Vector3(50, 0, 0)
	_busy = [&"bystander"]
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"", "busy with an order")
	_busy = []
	_port.downed = [&"patient", &"bystander"]
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"", "downed itself")
	_port.downed = [&"patient"]
	assert_eq(_fetch.notice(&"patient", &"patient", 0), &"")
	assert_eq(_fetch.notice(&"healer", &"patient", 0), &"", "a healer tends; it doesn't fetch")
	_port.downed = []
	_port.care_needed = {&"patient": 0.3}
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"", "not urgent")
	_port.downed = [&"patient"]
	_ports.roles.set_holder(&"doctor", &"")
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"", "no healer anywhere")


func test_the_errand_reaches_the_healer_and_the_tend_job_does_the_rest() -> void:
	var tend := BustleTendJob.new(_health, _fetch.nearby_with_summons(func(_h: StringName) -> Array[StringName]: return []))
	var bystander := _brain(&"bystander")
	var healer := _brain(&"healer", tend)
	assert_eq(_tick(healer, 0, tend).goal_id, &"idle", "the patient is out of its sight")
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer")
	var going := _tick(bystander, 0)
	assert_eq(going.goal_id, &"fetch_healer")
	assert_eq(going.band, BustleBands.URGENT)
	assert_eq(going.move_to, Vector3(50, 0, 0), "to the healer, by the fetch-help rule")
	assert_eq(going.talk_to, &"healer")
	assert_eq(bystander.runner.context.output["fetch_healer"], &"patient")
	_at[&"bystander"] = Vector3(48.5, 0, 0)
	var told: Array = []
	_fetch.summoned.connect(func(h: StringName, p: StringName) -> void: told.append([h, p]))
	assert_false(_tick(bystander, STEP).has_move_to, "within two metres: it tells the healer")
	assert_eq(told, [[&"healer", &"patient"]])
	assert_eq(_ended, [[&"bystander", &"patient", &"arrived"]])
	assert_eq(_fetch.summoned_to(&"healer"), &"patient")
	var inputs: Dictionary[StringName, float] = {}
	_fetch.fill_inputs(&"healer", inputs)
	assert_eq(inputs, {&"fact.summoned": 1.0}, "the healer's fact points at the patient")
	assert_eq(_tick(bystander, 2 * STEP).goal_id, &"idle", "the errand is over")
	tend.tended.connect(_fetch.tended)
	assert_eq(_tick(healer, 2 * STEP, tend).goal_id, &"tend", "the unchanged tend job takes over")
	assert_eq(_port.calls, [[&"healer", &"patient"]])
	assert_eq(_fetch.summoned_to(&"healer"), &"", "tended: the summons ends")


func test_without_positions_the_bystander_arrives_at_once() -> void:
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer")
	_fetch.where = func(id: StringName) -> Variant: return null if id == &"bystander" else _at.get(id)
	var context := BustleActionContext.new()
	context.agent_id = &"bystander"
	assert_eq(BustleFetchHealerAction.new(_fetch).tick(context, 1.0), BustleActionHandler.Status.DONE)
	assert_eq(_fetch.summoned_to(&"healer"), &"patient", "as fetching help does")


func test_the_errand_ends_when_the_patient_recovers_or_dies() -> void:
	for case: String in ["recovered", "dead", "dropped", "bystander_downed", "no_healer"]:
		_ended = []
		_port.downed = [&"patient"]
		_dead = []
		_ports.roles.set_holder(&"doctor", &"healer")
		assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer", case)
		match case:
			"recovered":
				_port.downed = []
				_port.care_needed = {&"patient": 0.1}
			"dead":
				_dead = [&"patient"]
			"dropped":
				_fetch.drop(&"patient")
			"bystander_downed":
				_port.downed = [&"patient", &"bystander"]
			"no_healer":
				_ports.roles.set_holder(&"doctor", &"")
		assert_eq(_fetch.errand_of(&"bystander"), {}, case)
		assert_eq(_ended, [[&"bystander", &"patient", StringName(case)]], case)
		_port.care_needed = {&"patient": 0.9}


func test_a_summons_ends_when_the_patient_recovers_or_dies() -> void:
	_fetch.notice(&"bystander", &"patient", 0)
	_fetch.arrive(&"bystander", 5)
	assert_eq(_fetch.summoned_to(&"healer"), &"patient")
	_dead = [&"patient"]
	assert_eq(_fetch.summoned_to(&"healer"), &"", "died")
	_dead = []
	_fetch.notice(&"bystander", &"patient", 10)
	_fetch.arrive(&"bystander", 15)
	_fetch.tended(&"healer", &"patient", false)
	assert_eq(_fetch.summoned_to(&"healer"), &"patient", "a refused care keeps it")
	_fetch.drop(&"patient")
	assert_eq(_fetch.summoned_to(&"healer"), &"")
	assert_false(_fetch.arrive(&"bystander", 20), "no errand to arrive from")


func test_look_checks_whom_the_bystander_sees_in_id_order() -> void:
	_port.downed = [&"patient", &"another"]
	_at[&"another"] = Vector3(3, 0, 0)
	_fetch.nearby = func(_b: StringName) -> Array[StringName]: return [&"patient", &"another", &"other"]
	assert_eq(_fetch.look(&"bystander", 0), &"healer")
	assert_eq(StringName(_fetch.errand_of(&"bystander")["patient"]), &"another", "id order")
	assert_eq(BustleFetchHealer.new(_health).look(&"bystander", 0), &"", "no nearby hook: sees nobody")


func test_errands_and_summons_survive_a_save() -> void:
	_port.downed = [&"patient", &"p2"]
	_at[&"p2"] = Vector3(5, 0, 0)
	_fetch.notice(&"bystander", &"patient", 7)
	_fetch.notice(&"other", &"p2", 8)
	_fetch.arrive(&"other", 9)
	var saved := _fetch.export_state()
	assert_eq(saved, {"version": 1, "errands": {"bystander": {"patient": "patient", "healer": "healer", "since": 7}},
		"summons": {"healer": "p2"}})
	var restored := BustleFetchHealer.new(_health, [&"doctor"] as Array[StringName])
	restored.where = _fetch.where
	assert_true(restored.import_state(JSON.parse_string(JSON.stringify(saved))), "also through JSON")
	assert_eq(restored.export_state(), saved)
	assert_eq(restored.summoned_to(&"healer"), &"p2")
	_fetch = restored
	assert_eq(_tick(_brain(&"bystander"), 10).move_to, Vector3(50, 0, 0), "the restored errand carries on")


func test_a_malformed_or_newer_save_is_refused_and_changes_nothing() -> void:
	_fetch.notice(&"bystander", &"patient", 0)
	var before := _fetch.export_state()
	for bad: Dictionary in [{"version": 2, "errands": {}, "summons": {}}, {"version": 1, "errands": [], "summons": {}},
			{"version": 1, "errands": {"b": {"patient": "", "healer": "h", "since": 0}}, "summons": {}},
			{"version": 1, "errands": {"b": {"patient": "p", "healer": "h", "since": 1.5}}, "summons": {}},
			{"version": 1, "errands": {}, "summons": {"h": 3}}]:
		assert_false(_fetch.import_state(bad), str(bad))
		assert_eq(_fetch.export_state(), before)
	assert_false(BustleSaveFormat.check(&"BustleFetchHealer", {"version": 2}).ok)
	assert_eq(BustleSaveFormat.current(&"BustleFetchHealer"), 1)


func test_hooks_of_the_wrong_type_warn_once() -> void:
	_fetch.healers = func() -> Variant: return "everyone"
	assert_eq(_fetch.healers_for(&"patient"), [&"healer"] as Array[StringName])
	assert_true(_Warn.has_warned("BustleFetchHealer.healers.wrong_type"))
	_fetch.where = func(_id: StringName) -> Variant: return 1
	assert_eq(_fetch.position_of(&"patient"), null)
	assert_true(_Warn.has_warned("BustleFetchHealer.where.wrong_type"))
	_fetch.nearby = func(_b: StringName) -> Variant: return null
	assert_eq(_fetch.look(&"bystander", 0), &"")
	assert_true(_Warn.has_warned("BustleFetchHealer.nearby.wrong_type"))
	_fetch.is_dead = func(_id: StringName) -> Variant: return "no"
	_fetch.urgency(&"patient")
	assert_true(_Warn.has_warned("BustleFetchHealer.is_dead.wrong_type"))
	_fetch.where = func(id: StringName) -> Variant: return _at.get(id)
	_fetch.urgent_at = NAN
	_fetch.reach = INF
	_port.downed = []
	_fetch.urgency(&"patient")
	_fetch.healer_within_reach(&"patient")
	assert_true(_Warn.has_warned("BustleFetchHealer.urgent_at"))
	assert_true(_Warn.has_warned("BustleFetchHealer.reach"))


func test_the_fetch_help_rule_is_shared() -> void:
	var context := BustleActionContext.new()
	assert_true(BustleFetchHelpAction.approach(context, Vector3.ZERO, Vector3(5, 0, 0), &"h"))
	assert_eq(context.output, {"move_to": Vector3(5, 0, 0), "talk_to": &"h"})
	var near := BustleActionContext.new()
	assert_false(BustleFetchHelpAction.approach(near, Vector3.ZERO, Vector3(2, 0, 0), &"h"), "within reach")
	assert_false(BustleFetchHelpAction.approach(near, null, Vector3(9, 0, 0), &"h"), "no position: there at once")
	assert_eq(near.output, {})


func test_the_default_port_or_no_health_changes_nothing() -> void:
	var quiet := BustleFetchHealer.new(BustleHealthBehaviour.new(null, BustlePorts.new()), [&"doctor"] as Array[StringName])
	assert_eq(quiet.notice(&"a", &"b", 0), &"", "everyone is healthy")
	var inputs: Dictionary[StringName, float] = {}
	quiet.fill_inputs(&"a", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float])
	for none: BustleFetchHealer in [BustleFetchHealer.new(), BustleFetchHealer.new(BustleHealthBehaviour.new(null, null))]:
		assert_eq(none.notice(&"a", &"b", 0), &"")
		assert_eq(none.healers_for(&"b"), [] as Array[StringName])
		assert_eq(none.export_state(), {"version": 1, "errands": {}, "summons": {}})
	var context := BustleActionContext.new()
	assert_eq(BustleFetchHealerAction.new().tick(context, 1.0), BustleActionHandler.Status.DONE)


func test_proposed_defaults_no_rolls_and_the_goal() -> void:
	var fresh := BustleFetchHealer.new()
	assert_eq([fresh.urgent_at, fresh.downed_weight, fresh.care_weight, fresh.reach], [0.8, 1.0, 1.0, 15.0])
	var goal := BustleFetchHealer.goal_def()
	assert_eq(goal.id, &"fetch_healer")
	assert_eq(goal.band, BustleBands.URGENT)
	assert_eq(goal.tags, [&"fetch_healer", &"travel"] as Array[StringName])
	assert_eq(BustleFetchHealer.goal_def(BustleBands.PERSONAL).band, BustleBands.PERSONAL)
	for path: String in ["fetch_healer.gd", "fetch_healer_action.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/health/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])


func test_two_patients_and_one_healer_never_take_the_healer_from_each_other() -> void:
	_port.downed = [&"patient", &"p2"]
	_at[&"p2"] = Vector3(4, 0, 0)
	assert_eq(_fetch.notice(&"bystander", &"patient", 0), &"healer")
	assert_eq(_fetch.notice(&"other", &"p2", 0), &"healer", "both set off before anyone arrives")
	assert_true(_fetch.arrive(&"bystander", 5))
	assert_eq(_fetch.summoned_to(&"healer"), &"patient")
	assert_false(_fetch.arrive(&"other", 6), "the healer is already summoned")
	assert_eq(_fetch.summoned_to(&"healer"), &"patient", "the first summons is kept")
	assert_eq(_ended, [[&"bystander", &"patient", &"arrived"], [&"other", &"p2", &"healer_busy"]])
	var nearby: Callable = _fetch.nearby_with_summons(func(_h: StringName) -> Array[StringName]: return [])
	assert_eq(nearby.call(&"healer"), [&"patient"] as Array[StringName], "the first patient stays reachable")
	assert_eq(_fetch.nearest_healer(&"p2"), &"", "the only healer is busy")
	assert_eq(_fetch.notice(&"other", &"p2", 7), &"", "so nobody sets off again for it")
	_at[&"spare"] = Vector3(70, 0, 0)
	_fetch.healers = func() -> Array[StringName]: return [&"spare"]
	assert_eq(_fetch.notice(&"other", &"p2", 8), &"spare", "the next-nearest free healer")
	_fetch.tended(&"healer", &"patient", true)
	assert_eq(_fetch.nearest_healer(&"p2"), &"healer", "free again once it tended the first")


func test_a_kept_summons_and_a_rerouted_errand_survive_a_save() -> void:
	_port.downed = [&"patient", &"p2"]
	_at[&"p2"] = Vector3(4, 0, 0)
	_at[&"spare"] = Vector3(70, 0, 0)
	_fetch.healers = func() -> Array[StringName]: return [&"spare"]
	_fetch.notice(&"bystander", &"patient", 0)
	_fetch.arrive(&"bystander", 5)
	assert_eq(_fetch.notice(&"other", &"p2", 6), &"spare")
	var saved := _fetch.export_state()
	assert_eq(saved, {"version": 1, "errands": {"other": {"patient": "p2", "healer": "spare", "since": 6}},
		"summons": {"healer": "patient"}})
	var restored := BustleFetchHealer.new(_health, [&"doctor"] as Array[StringName])
	restored.where = _fetch.where
	restored.healers = _fetch.healers
	assert_true(restored.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.export_state(), saved)
	assert_eq(restored.summoned_to(&"healer"), &"patient")
	assert_eq(restored.notice(&"third", &"p2", 7), &"", "p2 already has an errand")
	assert_true(restored.arrive(&"other", 8))
	assert_eq(restored.summoned_to(&"spare"), &"p2")
	assert_eq(restored.summoned_to(&"healer"), &"patient", "each healer keeps its own patient")
