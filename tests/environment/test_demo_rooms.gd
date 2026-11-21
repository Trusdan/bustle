# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The demo room set (experimental demo data in demo/environment/, not part of the addon): its rooms
## load and score as docs/environment.md says, an agent placed in one reads as indoors with that
## room's scores, the documented typical rule set gives the documented thoughts, and leaving the
## environment conditions out (as a host does while an agent sleeps) holds the indoors and outdoors
## needs still.

const DemoRooms := preload("res://demo/environment/demo_rooms.gd")
const INDOORS_NEED := preload("res://demo/environment/indoors.tres")
const OUTDOORS_NEED := preload("res://demo/environment/outdoors.tres")

var _ports: BustlePorts
var _env: BustleEnvironmentPort


func before_each() -> void:
	_ports = BustlePorts.new()
	_env = _ports.environment


func test_the_demo_rooms_score_as_documented() -> void:
	assert_eq(DemoRooms.rooms(), [&"cellar", &"house_room", &"workshop"] as Array[StringName])
	assert_eq(DemoRooms.scores_of(&"house_room"),
		{&"beauty": 0.6, &"comfort": 0.7, &"cleanliness": 0.7, &"impressiveness": 0.3} as Dictionary[StringName, float])
	assert_eq(DemoRooms.scores_of(&"workshop"),
		{&"beauty": 0.3, &"comfort": 0.4, &"cleanliness": 0.35, &"impressiveness": 0.5} as Dictionary[StringName, float])
	assert_eq(DemoRooms.scores_of(&"cellar"),
		{&"beauty": 0.1, &"comfort": 0.2, &"cleanliness": 0.2} as Dictionary[StringName, float])
	assert_false(DemoRooms.scores_of(&"cellar").has(&"impressiveness"), "left unset, not 0")
	assert_eq(DemoRooms.scores_of(&"hall"), {} as Dictionary[StringName, float], "not a demo room")
	for room: StringName in DemoRooms.rooms():
		for score: StringName in DemoRooms.scores_of(room):
			assert_true(BustleEnvironmentPort.SCORES.has(score), "%s: %s is a port score" % [room, score])


func test_install_gives_the_port_the_scores_and_places_nobody() -> void:
	_env.set_scores(&"hall", {&"beauty": 0.9})
	_env.set_room(&"smith", &"hall")
	assert_true(DemoRooms.install(_env))
	for room: StringName in DemoRooms.rooms():
		assert_eq(_env.scores(room), DemoRooms.scores_of(room), "%s loads as documented" % room)
	assert_eq(_env.scores(&"hall"), {&"beauty": 0.9} as Dictionary[StringName, float], "other rooms are left alone")
	assert_eq(_env.room_of(&"smith"), &"hall", "and so is everyone's room")
	assert_eq(_env.room_of(&"baker"), &"", "nobody is placed")
	assert_eq(_env.conditions(&"baker"), [BustleEnvironmentPort.OUTDOORS] as Array[StringName],
		"an agent no host has placed counts as outdoors with the default port")
	var saved := _env.export_state()
	assert_true(DemoRooms.install(_env), "installing again changes nothing")
	assert_eq(_env.export_state(), saved)
	assert_false(DemoRooms.install(null))


func test_an_agent_in_a_demo_room_is_indoors_with_its_scores() -> void:
	DemoRooms.install(_env)
	for room: StringName in DemoRooms.rooms():
		assert_true(_env.set_room(&"baker", room))
		assert_true(_env.is_indoors(&"baker"), "indoors in the %s" % room)
		assert_eq(BustleEnvironmentPort.conditions_of(_env, &"baker"), [BustleEnvironmentPort.INDOORS] as Array[StringName])
		assert_eq(_env.scores(_env.room_of(&"baker")), DemoRooms.scores_of(room))
	_env.set_room(&"baker", &"")
	assert_eq(_env.conditions(&"baker"), [BustleEnvironmentPort.OUTDOORS] as Array[StringName], "out again")


func test_one_room_per_agent() -> void:
	DemoRooms.install(_env)
	_env.set_room(&"baker", &"workshop")
	_env.set_room(&"baker", &"cellar")
	assert_eq(_env.room_of(&"baker"), &"cellar", "a move replaces the room; an agent is never in two")


func test_the_typical_rules_give_the_documented_thoughts() -> void:
	DemoRooms.install(_env)
	var rules: Array[BustleRoomThought] = [
		_rule(&"beauty", _thought(&"pleasant_room", 3.0), 0.6),
		_rule(&"beauty", _thought(&"beautiful_room", 6.0), 0.85),
		_rule(&"cleanliness", _thought(&"dirty_room", -4.0), NAN, 0.3),
		_rule(&"cleanliness", _thought(&"filthy_room", -8.0), NAN, 0.1),
		_rule(&"comfort", _thought(&"cramped_room", -3.0), NAN, 0.25),
		_rule(&"impressiveness", _thought(&"impressive_room", 5.0), 0.8),
	]
	var thoughts := BustleRoomThoughts.new(rules, _ports)
	var expected := {
		&"house_room": [&"pleasant_room"],
		&"workshop": [],
		&"cellar": [&"cramped_room", &"dirty_room"],
	}
	for room: StringName in DemoRooms.rooms():
		var mood := BustleMood.new()
		_env.set_room(&"baker", room)
		var chosen := thoughts.sync(&"baker", mood)
		chosen.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		assert_eq(chosen, Array(expected[room], TYPE_STRING_NAME, "", null), "thoughts in the %s" % room)


func test_leaving_the_conditions_out_while_asleep_holds_both_needs_still() -> void:
	DemoRooms.install(_env)
	_env.set_room(&"baker", &"house_room")
	var needs := BustleNeedSet.new()
	needs.add_need(INDOORS_NEED.duplicate())
	needs.add_need(OUTDOORS_NEED.duplicate())
	needs.set_pressure(&"indoors", 0.5)
	needs.set_pressure(&"outdoors", 0.5)
	var before := [needs.pressure(&"indoors"), needs.pressure(&"outdoors")]
	var asleep: Array[StringName] = [&"asleep"]
	needs.advance(8 * 60, asleep)
	assert_eq([needs.pressure(&"indoors"), needs.pressure(&"outdoors")], before,
		"eight hours asleep without the environment conditions: neither need rises or falls")
	var awake: Array[StringName] = [&"awake"]
	awake.append_array(BustleEnvironmentPort.conditions_of(_env, &"baker"))
	needs.advance(60, awake)
	assert_almost_eq(needs.pressure(&"outdoors"), before[1] + 0.05, 0.0001, "awake indoors, the outdoors need rises again")


func _thought(id: StringName, value: float) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.reason_kind = &"environment"
	return def


func _rule(score: StringName, thought: BustleThoughtDef, at_least: float = NAN, at_most: float = NAN) -> BustleRoomThought:
	var rule := BustleRoomThought.new()
	rule.score = score
	rule.thought = thought
	rule.at_least = at_least
	rule.at_most = at_most
	return rule
