# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The Wyrd bridge installed on a society, against the pinned test-only Wyrd: Wyrd answers the
## social and roles ports, deeds are Wyrd deeds, and Wyrd evaluates the dialogue facts. Anonymous
## agents only. CI deletes this folder, the bridge and the vendored Wyrd in its core-only job.

const _Wyrd := preload("res://addons/wyrd/runtime/wyrd.gd")


## A world where every id exists and is alive.
class _World:
	extends WyrdWorldAdapter

	func exists(_id: StringName) -> bool:
		return true

	func is_alive(_id: StringName) -> bool:
		return true

	func kind(_id: StringName) -> StringName:
		return &"person"

	func tags(_id: StringName) -> PackedStringArray:
		return PackedStringArray()

	func display_name(id: StringName) -> String:
		return String(id)

	func members(_group: StringName) -> PackedStringArray:
		return PackedStringArray()


## Something that says it is another Wyrd release.
class _OtherWyrd:
	extends RefCounted

	func get_version() -> String:
		return "1.0.2"


## A mood for the dialogue facts.
class _Mood:
	extends RefCounted
	var mood: float = 50.0
	var emotion: StringName = &""
	var thoughts: Array[Dictionary] = []

	func reasons() -> Array[Dictionary]:
		return thoughts


var _wyrd: Node
var _society: BustleSociety


func before_each() -> void:
	_wyrd = _Wyrd.new()
	add_child_autofree(_wyrd)
	_wyrd.register_adapter(WyrdWorldAdapter, _World.new())
	var config := WyrdConfig.new()
	config.axis_verbs = PackedStringArray(["helped", "slighted"])
	config.axis_names = PackedStringArray(["affinity", "affinity"])
	config.axis_deltas = PackedFloat64Array([20.0, -30.0])
	_wyrd.configure(config)
	_wyrd.start_new_game(7)
	_society = BustleSociety.new(7)
	_society.register_archetype(&"plain", BustleGoalLibrary.new())
	for id: StringName in [&"a1", &"a2", &"a3", &"a4"]:
		_society.add_agent(id, &"plain")


func _install(mood_of: Callable = Callable()) -> BustleWyrdBridge:
	var bridge := BustleWyrdBridge.install(_society, _wyrd, mood_of)
	assert_not_null(bridge, "installs on the pinned Wyrd")
	return bridge


func test_installing_makes_wyrd_the_social_and_roles_ports() -> void:
	var bridge := _install()
	assert_same(_society.ports.social, bridge.social)
	assert_same(_society.ports.roles, bridge.roles)
	assert_false(_society.ports.social is BustleSocialStore, "the built-in store is off")
	assert_false(_society.ports.social.has_method(&"add_opinion"), "no store opinions or relationship rules")
	assert_eq(bridge.registered, BustleWyrdFacts.NAMES, "every dialogue fact is registered")


func test_another_wyrd_release_installs_nothing() -> void:
	var default_social := _society.ports.social
	var default_roles := _society.ports.roles
	assert_false(BustleWyrdBridge.supports(_OtherWyrd.new()))
	assert_null(BustleWyrdBridge.install(_society, _OtherWyrd.new()))
	assert_null(BustleWyrdBridge.install(_society, null))
	assert_null(BustleWyrdBridge.install(null, _wyrd))
	assert_same(_society.ports.social, default_social, "nothing changed")
	assert_same(_society.ports.roles, default_roles)
	assert_true(BustleWyrdBridge.supports(_wyrd), "while the pinned release is supported")


func test_a_recorded_deed_is_a_wyrd_deed() -> void:
	var bridge := _install()
	watch_signals(_wyrd)
	var witnesses: Array[Dictionary] = [{"id": &"a3"}, {"id": "a3"}, {"name": "no id"}, {"id": &"p1"}]
	var key := bridge.social.record_deed(&"a1", &"helped", &"a2", &"square", witnesses)
	assert_eq(key, &"deed_1")
	assert_signal_emit_count(_wyrd, "deed_recorded", 1)
	var row: Dictionary = _wyrd.deeds.row_at(0)
	assert_eq([row["verb"], row["actor"], row["target"], row["place"]], [&"helped", &"a1", &"a2", &"square"])
	assert_eq(row["witnesses"], PackedStringArray(["a3", "p1"]), "each id once; a non-agent id is fine")
	assert_eq(bridge.social.record_deed(&"", &"helped", &"a2", &"", []), &"")
	assert_eq(bridge.social.record_deed(&"a1", &"", &"a2", &"", []), &"")
	assert_eq(_wyrd.deeds.size(), 1, "an empty actor or verb records nothing")


func test_first_hand_knowledge_and_one_hop_of_news() -> void:
	var bridge := _install()
	var social := bridge.social
	var key := social.record_deed(&"a1", &"slighted", &"a2", &"", [{"id": &"a3"}] as Array[Dictionary])
	assert_true(social.knows(&"a1", key), "the actor knows first-hand")
	assert_true(social.knows(&"a3", key), "so does a witness")
	assert_false(social.knows(&"a2", key), "the target, unseen, doesn't")
	assert_false(social.knows(&"a4", key))
	assert_false(social.knows(&"a1", &"deed_99"), "an unknown key")
	assert_false(social.knows(&"a1", &"other"), "a key that isn't one of the bridge's")
	assert_eq(social.share_news(&"a3", &"a4", &""), 1, "the witness tells")
	assert_true(social.knows(&"a4", key), "the listener now knows")
	assert_true((_wyrd.deeds.believer_index(&"a4") as Dictionary).has(1), "as a Wyrd believer")
	assert_eq(social.share_news(&"a4", &"a2", &""), 0, "second-hand news isn't passed on")
	assert_eq(social.share_news(&"a3", &"a4", &""), 0, "nor told twice")
	assert_eq(social.share_news(&"a1", &"a1", &""), 0)


func test_opinions_kinds_and_reasons_come_from_wyrd() -> void:
	var bridge := _install()
	var social := bridge.social
	assert_eq(social.opinion(&"a2", &"a1"), 50, "neutral before any deed")
	var first := social.record_deed(&"a1", &"slighted", &"a2", &"", [] as Array[Dictionary])
	var second := social.record_deed(&"a1", &"helped", &"a3", &"", [{"id": &"a2"}] as Array[Dictionary])
	social.record_deed(&"a1", &"helped", &"a4", &"", [] as Array[Dictionary])
	assert_eq(social.opinion(&"a2", &"a1"), _wyrd.social.disposition(&"a2", &"a1"), "Wyrd's disposition")
	assert_eq(social.opinion(&"a2", &"a1"), 45, "50 + (-30 + 20) / 2")
	assert_eq(social.reasons(&"a2", &"a1"), [
		{"deed": second, "verb": &"helped", "minute": 0, "as": &"witness"},
		{"deed": first, "verb": &"slighted", "minute": 0, "as": &"target"},
	] as Array[Dictionary], "newest first; a deed a2 neither suffered nor saw isn't a reason")
	assert_eq(social.reasons(&"a2", &"a1", 1).size(), 1)
	assert_eq(social.kinds_between(&"a2", &"a1"), PackedStringArray())
	_wyrd.social.set_kind(&"a2", &"a1", &"rival")
	_wyrd.social.set_kind(&"a2", &"a1", &"kin")
	assert_eq(social.kinds_between(&"a2", &"a1"), PackedStringArray(["kin", "rival"]))
	assert_eq(social.kinds_between(&"a1", &"a2"), PackedStringArray(), "one-way")


func test_an_interaction_on_the_installed_port_moves_wyrd_opinions() -> void:
	var bridge := _install()
	var interactions := BustleSocialInteractions.new(_society.ports.social, 7)
	var def := BustleInteractionDef.new()
	def.id = &"helped"
	def.recipient_value = 2.0
	def.initiator_value = 2.0
	var result := interactions.interact(def, &"a1", &"a2", 0, &"", [{"id": &"a3"}] as Array[Dictionary])
	assert_true(result["ok"])
	var row: Dictionary = _wyrd.deeds.row_at(0)
	assert_eq(row["verb"], &"helped", "a Wyrd deed")
	assert_almost_eq(float(row["magnitude"]), float(result["to_recipient"]), 0.000001, "weighed by the recipient's outcome")
	assert_eq(bridge.social.opinion(&"a2", &"a1"), clampi(int(round(50.0 + 20.0 * float(result["to_recipient"]) / 2.0)), 0, 100),
		"so the recipient's opinion moves in Wyrd: 50 + delta × magnitude / 2")
	assert_ne(bridge.social.opinion(&"a2", &"a1"), BustleSocialPort.NEUTRAL_OPINION)
	assert_true(bridge.social.knows(&"a3", result["deed"]), "the witness knows it")


func test_roles_follow_wyrd_assign_vacate_and_signals() -> void:
	var bridge := _install()
	var roles := bridge.roles
	watch_signals(roles)
	roles.set_holder(&"keeper", &"a1")
	assert_eq(_wyrd.roles.holder(&"keeper"), &"a1", "assigned in Wyrd")
	assert_signal_emitted_with_parameters(roles, "holder_changed", [&"keeper", &"", &"a1"])
	_wyrd.roles.assign(&"keeper", &"a2")
	assert_eq(roles.holder_of(&"keeper"), &"a2", "Wyrd's change is the port's")
	assert_signal_emitted_with_parameters(roles, "holder_changed", [&"keeper", &"a1", &"a2"])
	assert_eq(roles.roles_of(&"a2"), PackedStringArray(["keeper"]))
	assert_eq(roles.roles_of(&"a1"), PackedStringArray())
	roles.set_holder(&"keeper", &"a2")
	assert_signal_emit_count(roles, "holder_changed", 2, "no change, no signal")
	roles.set_holder(&"keeper", &"")
	assert_eq(_wyrd.roles.holder(&"keeper"), &"", "vacated in Wyrd")
	assert_eq(roles.holder_of(&"keeper"), &"")
	assert_signal_emit_count(roles, "holder_changed", 3, "a vacancy is reported too")
	assert_eq(get_signal_parameters(roles, "holder_changed"), [&"keeper", &"a2", &""])
	# A role Wyrd leaves contested (host_decides) reports the departure at once.
	roles.set_holder(&"seat", &"a3")
	_wyrd.roles.define(&"seat", "host_decides")
	_wyrd.roles.vacate(&"seat", &"left")
	assert_eq(get_signal_parameters(roles, "holder_changed"), [&"seat", &"a3", &""])
	roles.set_holder(&"seat", &"a4")
	assert_eq(get_signal_parameters(roles, "holder_changed"), [&"seat", &"", &"a4"], "then the new holder")


func test_wyrd_evaluates_the_dialogue_facts() -> void:
	var mood := _Mood.new()
	mood.mood = 20.0
	mood.emotion = &"tense"
	mood.thoughts = [{"thought": &"hungry_thought", "value": -12.0}, {"thought": &"slept", "value": 4.0}] as Array[Dictionary]
	_install(func(id: StringName) -> Object: return mood if id == &"a1" else null)
	var brain := _society.get_agent(&"a1").brain
	brain.last_intent = BustleIntent.new()
	brain.last_intent.goal_id = &"eat"
	var candidate := BustleCandidate.new()
	candidate.goal_id = &"eat"
	candidate.reasons = [
		{"kind": &"need", "need": &"rest", "value": 0.2}, {"kind": &"need", "need": &"hunger", "value": 0.7},
	] as Array[Dictionary]
	brain.last_candidates = [candidate] as Array[BustleCandidate]
	brain.last_senses = BustleSenses.new()
	brain.last_senses.inputs = {&"need.hunger": 0.7, &"need.rest": 0.7, &"need.rest.weight": 9.0, &"mood": 20.0}
	assert_eq(_call(&"npc_goal", [&"a1"]), &"eat")
	assert_eq(_call(&"npc_goal_reason", [&"a1"]), &"hunger", "the need that weighed most")
	assert_almost_eq(float(_call(&"npc_need", [&"a1", &"rest"])), 0.7, 0.000001)
	assert_eq(_call(&"npc_top_need", [&"a1"]), &"hunger", "ties by id; a need's weight isn't a need")
	assert_eq(_call(&"npc_mood_band", [&"a1"]), &"low", "below the low-state line")
	assert_eq(_call(&"npc_emotion", [&"a1"]), &"tense")
	assert_eq(_call(&"npc_mood_reason", [&"a1"]), &"hungry_thought", "the strongest thought")
	mood.mood = 85.0
	assert_eq(_call(&"npc_mood_band", [&"a1"]), &"high")
	mood.mood = 50.0
	assert_eq(_call(&"npc_mood_band", [&"a1"]), &"normal")
	for fact: StringName in [&"npc_goal", &"npc_goal_reason", &"npc_top_need", &"npc_mood_band", &"npc_emotion", &"npc_mood_reason"]:
		assert_eq(_call(fact, [&"a2"]), &"", "%s: nothing to report for an idle agent with no mood" % fact)
		assert_eq(_call(fact, [&"nobody"]), &"", "%s: or an unknown one" % fact)
	assert_eq(float(_call(&"npc_need", [&"nobody", &"rest"])), 0.0)


# Wyrd evaluates a call to host function [param fact] with constant arguments, as compiled content
# does.
func _call(fact: StringName, args: Array) -> Variant:
	var code := PackedInt32Array()
	var consts: Array = []
	for arg: Variant in args:
		code.append_array([WyrdOpcodes.PUSH_CONST, consts.size()])
		consts.append(arg)
	code.append_array([WyrdOpcodes.CALL, consts.size(), args.size()])
	consts.append(fact)
	var compiled := WyrdCompiledCondition.new()
	compiled.code = code
	compiled.consts = consts
	return WyrdRpnEval.new().eval(compiled, {}, _wyrd._runtime.function_table())
