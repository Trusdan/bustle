# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The rest-when-sick goal: an agent with a host-listed sick tag, or a capacity below its line,
## rests instead of working (at its bed, from the property port, or where it stands) until the port
## says it is better. Orders, locks and urgent needs still come first, seeking care can come first,
## Bustle keeps no illness state, makes no rolls, and a resting brain survives a save.

const Recovering := preload("res://tests/health/fake_recovering_port.gd")
const World := preload("res://tests/health/fake_world_port.gd")
const _Warn := preload("res://addons/bustle/core/warn_once.gd")
const STEP := 10

var _ports: BustlePorts
var _port: Recovering
var _world: World
var _health: BustleHealthBehaviour
var _rest: BustleRestSick
var _locked: Array[StringName] = []


func before_each() -> void:
	_Warn.reset()
	_ports = BustlePorts.new()
	_port = Recovering.new()
	_ports.health = _port
	_world = World.new()
	_world.areas = {&"a": &"field", &"healer": &"infirmary"}
	_world.set_place(&"field", Vector3(-10, 0, 0))
	_world.set_place(&"cottage", Vector3(20, 0, 0))
	_world.set_place(&"infirmary", Vector3(10, 0, 0))
	_ports.world = _world
	_health = BustleHealthBehaviour.new(null, _ports)
	_rest = BustleRestSick.new(_health)
	_locked = []
	_rest.is_locked = func(id: StringName) -> bool: return _locked.has(id)


func after_each() -> void:
	_Warn.reset()


func _goal(id: StringName, band: int, input: StringName, tags: Array[StringName] = []) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.tags = tags
	goal.preconditions = [{"kind": &"input", "input": input}]
	return goal


func _brain(id: StringName = &"a", seek: BustleSeekCare = null) -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals.append(BustleRestSick.goal_def())
	if seek != null:
		library.goals.append(BustleSeekCare.goal_def(30))
	library.goals.append(_goal(&"shift", BustleBands.DUTY, &"fact.on_shift", [&"work"]))
	library.goals.append(_goal(&"errand", BustleBands.PERSONAL, &"fact.errand"))
	library.goals.append(_goal(&"starving", BustleBands.URGENT, &"need.starving"))
	var idle := BustleGoalDef.new()
	idle.id = &"idle"
	idle.band = BustleBands.IDLE
	library.goals.append(idle)
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(id, library, config, 5)
	brain.gate = _health.allows
	brain.runner.register(BustleRestSick.ACTION, BustleRestSickAction.new(_rest))
	if seek != null:
		brain.runner.register(BustleSeekCare.ACTION, BustleSeekCareAction.new(seek))
	return brain


func _tick(brain: BustleBrain, minute: int, extra: Dictionary = {}, seek: BustleSeekCare = null) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = minute
	_rest.fill_inputs(brain.agent_id, senses.inputs)
	if seek != null:
		seek.fill_inputs(brain.agent_id, senses.inputs)
	for key: StringName in extra:
		senses.inputs[key] = extra[key]
	return brain.tick(1.0, senses)


func _sick(on: bool = true) -> void:
	_port.tags = {&"a": [&"sick"]} if on else {}


func test_a_listed_sick_tag_or_a_capacity_below_its_line_makes_an_agent_rest() -> void:
	assert_eq(_rest.sickness(&"a"), 0.0, "well")
	_port.tags = {&"a": [&"tired"]}
	assert_eq(_rest.sickness(&"a"), 0.0, "a tag the host didn't list")
	_sick()
	assert_eq(_rest.sickness(&"a"), 1.0, "a listed tag counts its weight")
	_sick(false)
	_port.capacities = {&"a": {&"consciousness": 0.25}}
	assert_almost_eq(_rest.sickness(&"a"), 0.5, 1e-6, "halfway below a 0.5 line")
	_port.capacities = {&"a": {&"consciousness": 0.5}}
	assert_eq(_rest.sickness(&"a"), 0.0, "at the line is well enough")
	_rest.capacity_lines = {&"moving": 0.8}
	_port.capacities = {&"a": {&"moving": 0.4, &"consciousness": 0.1}}
	assert_almost_eq(_rest.sickness(&"a"), 0.5, 1e-6, "only the listed capacities count")
	_rest.tag_weight = 0.3
	_rest.capacity_weight = 0.4
	_sick()
	assert_almost_eq(_rest.sickness(&"a"), 0.3, 1e-6, "the highest of the weighted readings")
	var inputs: Dictionary[StringName, float] = {}
	_rest.fill_inputs(&"a", inputs)
	assert_almost_eq(inputs[BustleRestSick.INPUT], 0.3, 1e-6)


func test_it_outranks_work_and_errands_but_not_orders_locks_or_urgent_needs() -> void:
	_sick()
	var brain := _brain()
	assert_eq(_tick(brain, 0, {&"fact.on_shift": 1.0, &"fact.errand": 1.0}).goal_id, &"rest_sick", "over duty and errands")
	assert_eq(_tick(brain, STEP, {&"need.starving": 1.0}).goal_id, &"starving", "an urgent need comes first")
	_locked = [&"a"]
	assert_eq(_tick(brain, 2 * STEP, {&"fact.on_shift": 1.0}).goal_id, &"shift", "a lock holds it to its task")
	_locked = []
	var wait := BustleActionStep.new()
	wait.action = &"wait"
	wait.params = {"minutes": 60}
	var sequence := BustleActionSequence.new()
	sequence.steps.append(wait)
	assert_eq(brain.order(BustleOrder.new(&"fetch_water", sequence)), &"")
	var ordered := _tick(brain, 3 * STEP)
	assert_eq(ordered.order_id, &"fetch_water", "an order isn't gated: it runs")
	assert_eq(BustleRestSick.BAND, 65)
	assert_true(BustleRestSick.BAND > BustleBands.DUTY and BustleRestSick.BAND < BustleBands.ORDERED)


func test_it_ends_on_the_first_tick_after_the_port_says_better() -> void:
	_sick()
	var brain := _brain()
	for minute: int in range(0, 60, STEP):
		assert_eq(_tick(brain, minute, {&"fact.on_shift": 1.0}).goal_id, &"rest_sick")
	_sick(false)
	assert_eq(_tick(brain, 60, {&"fact.on_shift": 1.0}).goal_id, &"shift", "back to work at once")
	_port.capacities = {&"a": {&"consciousness": 0.2}}
	assert_eq(_tick(brain, 70, {&"fact.on_shift": 1.0}).goal_id, &"rest_sick")
	_port.capacities = {&"a": {&"consciousness": 0.9}}
	assert_eq(_tick(brain, 80, {&"fact.on_shift": 1.0}).goal_id, &"shift", "the capacity came back")
	var context := BustleActionContext.new()
	context.agent_id = &"a"
	assert_eq(BustleRestSickAction.new(_rest).tick(context, 1.0), BustleActionHandler.Status.DONE, "the action ends too")


func test_a_downed_agent_does_not_take_the_goal() -> void:
	_sick()
	_port.downed = [&"a"]
	var brain := _brain()
	assert_false(_rest.wants_rest(&"a"))
	assert_eq(_tick(brain, 0).goal_id, &"idle")
	assert_eq(_tick(brain, STEP, {&"fact.rest_sick": 1.0}).goal_id, &"idle", "even forced, the downed gate blocks it")


func test_it_rests_at_its_bed_from_the_property_port() -> void:
	_rest.bed_need = &"energy"
	var at := {&"a": Vector3(-10, 0, 0)}
	_rest.where = func(id: StringName) -> Variant: return at.get(id)
	assert_true(_ports.property.register(&"cot", &"a", &"field", {&"energy": 0.3}))
	assert_true(_ports.property.register(&"bed", &"a", &"cottage", {&"energy": 0.8}))
	assert_true(_ports.property.register(&"other_bed", &"b", &"cottage", {&"energy": 1.0}))
	assert_true(_ports.property.register(&"far_bed", &"a", &"nowhere", {&"energy": 1.0}))
	assert_eq(_rest.bed_for(&"a"), {"item": &"bed", "place": &"cottage"}, "its own, known place, the most rest")
	_sick()
	var brain := _brain()
	var going := _tick(brain, 0)
	assert_eq(going.goal_id, &"rest_sick")
	assert_eq(going.move_to, Vector3(20, 0, 0), "to the bed")
	assert_eq(brain.runner.context.output["rest_sick"], &"bed")
	at[&"a"] = Vector3(19, 0, 0)
	assert_false(_tick(brain, STEP).has_move_to, "there: it rests")
	assert_eq(brain.runner.context.output["rest_sick"], &"bed")


func test_without_a_bed_it_rests_where_it_stands() -> void:
	_sick()
	var brain := _brain()
	var resting := _tick(brain, 0)
	assert_eq(resting.goal_id, &"rest_sick")
	assert_false(resting.has_move_to)
	assert_eq(brain.runner.context.output["rest_sick"], &"")
	_rest.bed_need = &"energy"
	_ports.property.register(&"bed", &"a", &"cottage", {&"energy": 1.0})
	assert_eq(_rest.bed_for(&"a"), {}, "a bed with no way to tell arrival isn't used")
	assert_true(_Warn.has_warned("BustleRestSick.bed"))
	_rest.can_reach = func(_agent: StringName, _place: StringName) -> bool: return true
	assert_eq(_rest.bed_for(&"a"), {"item": &"bed", "place": &"cottage"})
	assert_true(_rest.has_reached(&"a", _rest.bed_for(&"a")), "the hook decides")


func test_seeking_care_comes_first_when_deferred_to() -> void:
	_ports.roles.set_holder(&"doctor", &"healer")
	var seek := BustleSeekCare.new(_health, [&"doctor"] as Array[StringName])
	_sick()
	_port.care_needed = {&"a": 0.8}
	var plain := _brain(&"a", seek)
	assert_eq(_tick(plain, 0, {}, seek).goal_id, &"rest_sick", "not deferring: resting outranks seeking care")
	_rest.seek_care = seek
	var deferring := _brain(&"a", seek)
	assert_eq(_tick(deferring, 0, {}, seek).goal_id, &"seek_care", "deferring: it goes for care first")
	_port.care_needed = {&"a": 0.2}
	assert_eq(_tick(deferring, STEP, {}, seek).goal_id, &"rest_sick", "care no longer needed: it rests")


func test_bad_settings_and_hooks_warn_once() -> void:
	_rest.capacity_lines = {&"consciousness": 1.5}
	_port.capacities = {&"a": {&"consciousness": 0.2}}
	assert_eq(_rest.sickness(&"a"), 0.0, "an unusable line is skipped")
	assert_true(_Warn.has_warned("BustleRestSick.capacity_lines"))
	_rest.tag_weight = NAN
	_sick()
	assert_eq(_rest.sickness(&"a"), 1.0, "a weight that isn't a number counts as 1")
	assert_true(_Warn.has_warned("BustleRestSick.tag_weight"))
	_rest.is_locked = func(_id: StringName) -> Variant: return "no"
	assert_true(_rest.wants_rest(&"a"), "a wrong lock answer counts as unlocked")
	assert_true(_Warn.has_warned("BustleRestSick.is_locked.wrong_type"))
	_rest.where = func(_id: StringName) -> Variant: return 5
	assert_eq(_rest.position_of(&"a"), null)
	assert_true(_Warn.has_warned("BustleRestSick.where.wrong_type"))
	_rest.can_reach = func(_a: StringName, _p: StringName) -> Variant: return "yes"
	assert_false(_rest.has_reached(&"a", {"item": &"bed", "place": &"cottage"}))
	assert_true(_Warn.has_warned("BustleRestSick.can_reach.wrong_type"))


func test_a_resting_brain_survives_a_save() -> void:
	_sick()
	var first := _brain()
	_tick(first, 0, {&"fact.on_shift": 1.0})
	_tick(first, STEP, {&"fact.on_shift": 1.0})
	var saved := first.export_state()
	var second := _brain()
	assert_true(second.import_state(saved))
	var a: Array[String] = []
	var b: Array[String] = []
	for minute: int in range(2 * STEP, 200, STEP):
		if minute == 100:
			_sick(false)
		a.append(String(_tick(first, minute, {&"fact.on_shift": 1.0}).goal_id))
		b.append(String(_tick(second, minute, {&"fact.on_shift": 1.0}).goal_id))
	assert_eq(a, b, "the restored brain carries on the same")
	assert_eq(a[-1], "shift")


func test_the_default_port_or_no_health_changes_nothing() -> void:
	var quiet := BustleRestSick.new(BustleHealthBehaviour.new(null, BustlePorts.new()))
	var inputs: Dictionary[StringName, float] = {}
	quiet.fill_inputs(&"a", inputs)
	assert_eq(inputs, {} as Dictionary[StringName, float], "everyone is healthy")
	for none: BustleRestSick in [BustleRestSick.new(), BustleRestSick.new(BustleHealthBehaviour.new(null, null))]:
		none.fill_inputs(&"a", inputs)
		assert_eq(inputs, {} as Dictionary[StringName, float])
		assert_false(none.wants_rest(&"a"))
		assert_eq(none.bed_for(&"a"), {})
	var context := BustleActionContext.new()
	assert_eq(BustleRestSickAction.new().tick(context, 1.0), BustleActionHandler.Status.DONE)


func test_it_keeps_no_illness_state_and_makes_no_rolls() -> void:
	var names: Array[String] = []
	for property: Dictionary in (BustleRestSick as Script).get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["health", "sick_tags", "capacity_lines", "tag_weight", "capacity_weight", "bed_need", "seek_care",
		"is_locked", "where", "can_reach"] as Array[String], "settings and hooks only")
	for path: String in ["rest_sick.gd", "rest_sick_action.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/health/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])


func test_the_proposed_defaults_and_the_goal_def() -> void:
	var fresh := BustleRestSick.new()
	assert_eq(fresh.sick_tags, [&"sick"] as Array[StringName])
	assert_eq(fresh.capacity_lines, {&"consciousness": 0.5} as Dictionary[StringName, float])
	assert_eq([fresh.tag_weight, fresh.capacity_weight], [1.0, 1.0])
	assert_eq(fresh.bed_need, &"")
	assert_eq(fresh.seek_care, null)
	var goal := BustleRestSick.goal_def()
	assert_eq(goal.id, &"rest_sick")
	assert_eq(goal.band, BustleRestSick.BAND)
	assert_eq(goal.tags, [&"rest_sick", &"travel"] as Array[StringName])
	assert_eq(BustleRestSick.goal_def(BustleBands.PERSONAL).band, BustleBands.PERSONAL)
