# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Each path docs/errors.md changed: hooks of the wrong type act as if unset, refused imports keep
## the old state, the void imports warn and still import, refusals warn instead of erroring, and
## the run-time ignores warn once with no other change.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")


## Walks for params.ticks ticks, then is done.
class Walk:
	extends BustleActionHandler

	func start(context: BustleActionContext) -> void:
		context.data["left"] = int(context.params.get("ticks", 1))

	func tick(context: BustleActionContext, _delta: float) -> Status:
		context.data["left"] = int(context.data["left"]) - 1
		return Status.DONE if int(context.data["left"]) <= 0 else Status.RUNNING


func before_each() -> void:
	_Warn.reset()


func _sequence(ticks: int) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = &"walk"
	step.params = {"ticks": ticks}
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _brain(goal_id: StringName, id: StringName = &"baker") -> BustleBrain:
	var goal := BustleGoalDef.new()
	goal.id = goal_id
	goal.band = BustleBands.PERSONAL
	var consideration := BustleConsideration.new()
	consideration.input = &"need.food"
	consideration.curve = Curve.new()
	consideration.curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	consideration.curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	goal.considerations.append(consideration)
	goal.sequence = _sequence(5)
	var library := BustleGoalLibrary.new()
	library.goals.append(goal)
	var brain := BustleBrain.new(id, library, BustleScoringConfig.new(), 7)
	brain.runner.register(&"walk", Walk.new())
	return brain


func _senses(now: int) -> BustleSenses:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	senses.inputs[&"need.food"] = 0.6
	return senses


func test_a_null_returning_gate_warns_once_and_lets_everything_through() -> void:
	var brain := _brain(&"eat")
	brain.gate = func(_id: StringName, _goal: Array[StringName], _option: Array[StringName]) -> Variant: return null
	for t in 20:
		assert_eq(brain.tick(0.1, _senses(t)).goal_id, &"eat", "minute %d: the broken gate passes" % t)
	assert_true(_Warn.has_warned("BustleBrain.gate.wrong_type"))
	assert_push_warning_count(1, "one warning in 20 ticks")
	assert_engine_error_count(0, "no script error on any call")


func test_a_gate_returning_a_string_is_unset_too() -> void:
	var conversation := BustleConversation.new(BustleSocialInteractions.new(BustleSocialStore.new()))
	conversation.accepts = func(_r: StringName, _i: StringName, _o: StringName) -> Variant: return "no"
	assert_false(conversation.turned_away(&"baker", &"smith"), "a broken accepts turns no one away")
	assert_false(conversation.turned_away(&"smith", &"baker"))
	assert_push_warning_count(1)
	assert_true(_Warn.has_warned("BustleConversation.accepts.wrong_type"))


func test_a_hook_over_a_fallback_uses_the_fallback() -> void:
	var def := BustleAffordanceDef.new()
	def.id = &"well"
	def.price = 3
	def.others_mult = 0.25
	var well := BustleAffordance.new(&"well_1", def)
	well.owner = &"smith"
	well.access_hook = func(_a: StringName, _w: BustleAffordance) -> Variant: return null
	well.cost_hook = func(_a: StringName, _w: BustleAffordance) -> Variant: return 2.5
	assert_eq(well.access(&"baker"), 0.25, "the owner's share for others, as with no hook")
	assert_eq(well.price_for(&"baker"), 3, "the def's price, as with no hook")
	assert_true(_Warn.has_warned("BustleAffordance.access_hook.wrong_type"))
	assert_true(_Warn.has_warned("BustleAffordance.cost_hook.wrong_type"))


func test_a_refused_brain_import_keeps_the_old_state() -> void:
	var brain := _brain(&"eat")
	for t in 3:
		brain.tick(0.1, _senses(t))
	var before := brain.export_state()
	var other_agent := _brain(&"eat", &"smith")
	other_agent.tick(0.1, _senses(0))
	var unknown_goal := _brain(&"drink")
	unknown_goal.tick(0.1, _senses(0))
	var bad_runner := before.duplicate(true)
	bad_runner["runner"]["step"] = 9
	for saved: Dictionary in [other_agent.export_state(), unknown_goal.export_state(), bad_runner]:
		assert_false(brain.import_state(saved))
		assert_eq(brain.export_state(), before, "nothing changed")
	assert_eq(brain.tick(0.1, _senses(3)).goal_id, &"eat", "and it carries on")


func test_a_refused_runner_import_keeps_its_state_and_sequence() -> void:
	var runner := BustleSequenceRunner.new()
	runner.register(&"walk", Walk.new())
	var sequence := _sequence(5)
	runner.start(sequence, &"eat", 0)
	runner.tick(0.1, 1)
	var before := runner.export_state()
	assert_false(runner.import_state(_sequence(1), {"state": BustleSequenceRunner.State.RUNNING, "step": 4}))
	assert_eq(runner.export_state(), before)
	assert_eq(runner.sequence, sequence, "the old sequence is kept")
	assert_eq(runner.state, BustleSequenceRunner.State.RUNNING)


func test_the_void_imports_warn_and_still_import() -> void:
	var meter := BustleDetectionMeter.new()
	var saved := meter.export_state()
	saved["level"] = 0.5
	saved["state"] = "bewildered"
	meter.import_state(saved)
	assert_eq(meter.level, 0.5, "the good values still import")
	assert_eq(meter.state, BustleDetectionMeter.State.UNAWARE, "an unknown state reads as unaware")
	assert_true(_Warn.has_warned("BustleDetectionMeter.bad_value"))
	var awareness := BustleAwareness.new()
	awareness.import_state({"smith": BustleDetectionMeter.new().export_state(), "baker": 3}, BustlePerceptionProfile.new())
	assert_not_null(awareness.meter(&"smith"), "a good row still imports")
	assert_null(awareness.meter(&"baker"), "a bad row is skipped")
	assert_true(_Warn.has_warned("BustleAwareness.bad_row"))
	assert_push_warning_count(2)


func test_refusals_warn_once_instead_of_erroring() -> void:
	var modifiers := BustleModifierSet.new()
	for i in 5:
		assert_false(modifiers.set_source(&"", &"work.speed", 1.0), "still refused")
		assert_false(modifiers.set_source(&"tool", &"work.speed", NAN))
	var society := BustleSociety.new()
	for i in 5:
		society.register_archetype(&"", null)
		assert_null(society.add_agent(&"baker", &"nobody"), "still refused")
	assert_eq(society.agent_ids().size(), 0)
	assert_push_error_count(0)
	assert_push_warning_count(3, "one per problem")


## Each case calls one run-time entry point twice; each must warn once and do what it did before.
func test_run_time_ignores_warn_once_with_no_other_change() -> void:
	var bare := RefCounted.new()
	var bad_block := BustleScheduleDef.new()
	bad_block.id = &"rota"
	bad_block.day = BustleScheduleDay.new()
	bad_block.day.blocks.append(BustleScheduleBlock.new())
	var schedule := BustleSchedule.new(bad_block)
	var aspirations := BustleAspirations.new(&"baker", BustleAspirationConfig.new())
	aspirations.config.wants.append(BustleWantDef.new())
	var social := BustleSocialInteractions.new(BustleSocialStore.new())
	var conversation := BustleConversation.new(social, [BustleInteractionDef.new()] as Array[BustleInteractionDef])
	var store := BustleSocialStore.new()
	store.set_time(100)
	var rules := BustleRomanceRules.new()
	rules.courting_release = 1000
	var romance := BustleRomance.new(store, rules)
	var cases: Array = [
		["BustleHealthBehaviour.no_port", func() -> void:
			var inputs: Dictionary[StringName, float] = {}
			BustleHealthBehaviour.new(BustleHealthConfig.new()).fill_inputs(&"baker", inputs)
			assert_true(inputs.is_empty())],
		["BustleHealthBehaviour.mood_without_set_held", func() -> void:
			BustleHealthBehaviour.new(BustleHealthConfig.new()).recovered(&"baker", bare)],
		["BustleSkills.mood_without_set_held", func() -> void: BustleSkills.new().apply(&"baker", null, &"", null, bare)],
		["BustleDirector.invalid_rules", func() -> void:
			var director := BustleDirector.new(_bad_director_rules())
			assert_eq(director.tension(0, {}), 0.0)
			assert_true(director.eligible(0, {}, false).is_empty())],
		["BustleLifeStages.invalid_rules", func() -> void: assert_false(BustleLifeStages.new().set_age(&"baker", 3.0))],
		["BustleRomance.invalid_rules", func() -> void: assert_eq(romance.update(&"baker", &"smith", 0), &"")],
		["BustleAffordance.invalid_def:", func() -> void:
			assert_eq(BustleAffordance.new(&"well_1").reserve(&"baker", 0), BustleAffordance.REFUSED_ACCESS)],
		["BustleSchedule.invalid_block:rota", func() -> void: assert_true(schedule.occurrences(0).is_empty())],
		["BustleAspirations.invalid_want:", func() -> void: assert_null(aspirations.choose(0))],
		["BustleConversation.invalid_interaction:", func() -> void: assert_true(conversation.weights(&"baker", &"smith").is_empty())],
		["BustleSocialInteractions.invalid_def:", func() -> void:
			assert_eq(social.interact(BustleInteractionDef.new(), &"baker", &"smith", 0)["reason"], &"invalid")],
		["BustleNeedSet.non_finite_minutes", func() -> void: BustleNeedSet.new().advance(NAN, [] as Array[StringName])],
		["BustleLeisure.non_finite_minutes", func() -> void: BustleLeisure.new().advance(INF)],
		["BustleSimRings.no_society", func() -> void:
			var rings := BustleSimRings.new()
			rings.tick(0.1)
			rings.update(0.1)],
		["BustleCombatPort.no_pair", func() -> void: BustleCombatPort.new().engage(&"baker", &"baker")],
		["BustleRolesPort.empty_role", func() -> void:
			var roles := BustleRolesPort.new()
			roles.set_holder(&"", &"baker")
			assert_eq(roles.holder_of(&""), &"")],
		["BustleScheduleRoster.empty_id", func() -> void: BustleScheduleRoster.new().add_agent(&"")],
		["BustleSocialStore.time_backwards", func() -> void:
			store.set_time(50)
			assert_eq(store.now_minutes, 100, "the clock stays")],
		["BustleSocialStore.bad_kind", func() -> void:
			store.set_kind(&"baker", &"baker", &"friend")
			assert_true(store.kinds_between(&"baker", &"baker").is_empty())],
	]
	for row: Array in cases:
		var key: String = row[0]
		var call: Callable = row[1]
		call.call()
		call.call()
		assert_true(_Warn.has_warned(key), "%s warns" % key)
	assert_push_warning_count(cases.size(), "each warns once, not once per call")
	assert_push_error_count(0)


func _bad_director_rules() -> BustleDirectorRules:
	var rules := BustleDirectorRules.new()
	rules.memory_minutes = -1
	return rules
