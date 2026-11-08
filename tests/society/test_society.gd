# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The society: the registry, ports, bodies coming and going, and saving and loading all or nothing.


func _library(id: StringName) -> BustleGoalLibrary:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.PERSONAL
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 30}
	goal.sequence = BustleActionSequence.new()
	goal.sequence.steps.append(step)
	var library := BustleGoalLibrary.new()
	library.goals.append(goal)
	return library


func _society(seed: int = 5) -> BustleSociety:
	var society := BustleSociety.new(seed)
	society.register_archetype(&"baker", _library(&"bake"))
	society.register_archetype(&"smith", _library(&"forge"))
	return society


## Two agents, each part-way through its goal's wait, with module data and a position.
func _populated() -> BustleSociety:
	var society := _society()
	var ann := society.add_agent(&"ann", &"baker", &"village")
	var bo := society.add_agent(&"bo", &"smith")
	ann.area = &"square"
	ann.data = {"mood": 42, "notes": ["early"]}
	bo.position = Vector3(1.5, 0, -2)
	bo.has_position = true
	for state: BustleNpcState in [ann, bo]:
		var senses := BustleSenses.new()
		senses.now_minutes = 10
		state.brain.tick(0.1, senses)
	return society


func test_agents_are_registered_once_from_known_archetypes() -> void:
	var society := _society()
	assert_not_null(society.add_agent(&"bo", &"smith"))
	assert_not_null(society.add_agent(&"ann", &"baker"))
	assert_null(society.add_agent(&"ann", &"smith"), "a taken id")
	assert_null(society.add_agent(&"cy", &"weaver"), "an unknown archetype")
	assert_null(society.add_agent(&"", &"baker"), "an empty id")
	assert_push_error_count(3)
	assert_eq(society.agent_ids(), [&"ann", &"bo"])
	assert_eq(society.get_agent(&"ann").brain.library, society.get_agent(&"ann").brain.library)
	society.remove_agent(&"ann")
	assert_eq(society.agent_ids(), [&"bo"])


func test_ports_start_as_defaults_and_take_only_the_right_kind() -> void:
	var society := _society()
	assert_eq(society.ports.missing(), PackedStringArray())
	var clock := BustleClockPort.new()
	assert_true(society.set_port(&"clock", clock))
	assert_eq(society.ports.clock, clock)
	assert_false(society.set_port(&"clock", BustleTradePort.new()), "the wrong kind of port")
	assert_false(society.set_port(&"weather", BustleClockPort.new()), "no such port")


func test_state_survives_freeing_and_recreating_a_body() -> void:
	var society := _populated()
	var ann := society.get_agent(&"ann")
	var brain_before := ann.brain.export_state()
	var body := Node3D.new()
	add_child(body)
	ann.attach_body(body)
	body.global_position = Vector3(4, 0, 3)
	ann.detach_body()
	body.free()
	assert_null(ann.body())
	assert_eq(ann.position, Vector3(4, 0, 3), "the position was kept")
	var again := Node3D.new()
	add_child_autofree(again)
	ann.attach_body(again)
	assert_eq(again.global_position, Vector3(4, 0, 3), "the new body starts where the old one was")
	assert_eq(ann.brain.export_state(), brain_before, "the brain didn't notice")
	assert_eq(society.get_agent(&"ann").data["mood"], 42)


func test_a_body_freed_without_detaching_leaves_its_last_exported_position() -> void:
	var society := _populated()
	var bo := society.get_agent(&"bo")
	var body := Node3D.new()
	add_child(body)
	bo.attach_body(body)
	body.global_position = Vector3(7, 0, 7)
	society.export_state()
	body.free()
	assert_null(bo.body())
	assert_eq(society.export_state()["agents"][1]["position"], [7.0, 0.0, 7.0])


func test_export_then_import_gives_an_identical_state_hash() -> void:
	var one := _populated()
	var saved := one.export_state()
	var two := _society(99)
	var report := two.import_state(saved)
	assert_true(report.ok, str(report.errors))
	assert_eq(report.schema, BustleSociety.SCHEMA)
	assert_eq(two.state_hash(), one.state_hash())
	assert_eq(two.export_state(), saved)
	assert_eq(two.world_seed, 5)
	assert_eq(saved["world_seed"], "5", "64-bit numbers are written as decimal strings")
	assert_typeof(saved["agents"][0]["brain"]["rng_state"], TYPE_STRING)
	var senses := BustleSenses.new()
	senses.now_minutes = 39
	assert_eq(two.get_agent(&"ann").brain.tick(0.1, senses).to_dictionary(),
		one.get_agent(&"ann").brain.tick(0.1, senses).to_dictionary(), "the brains carry on alike")


func test_an_empty_population_round_trips_and_loading_twice_duplicates_nothing() -> void:
	var empty := _society()
	var copy := _society()
	assert_true(copy.import_state(empty.export_state()).ok)
	assert_eq(copy.agent_ids(), [])
	var saved := _populated().export_state()
	assert_true(copy.import_state(saved).ok)
	var hash := copy.state_hash()
	assert_true(copy.import_state(saved).ok)
	assert_eq(copy.agent_ids(), [&"ann", &"bo"])
	assert_eq(copy.state_hash(), hash)


func test_bad_payloads_return_a_report_and_change_nothing() -> void:
	var society := _populated()
	var hash := society.state_hash()
	var good := society.export_state()
	var cases := {
		"not a dictionary": "nonsense",
		"no schema": {"agents": []},
		"an old schema": _with(good, "schema", 0),
		"a newer schema": _with(good, "schema", 2),
		"agents not a list": _with(good, "agents", {}),
		"a repeated id": _with(good, "agents", [good["agents"][0], good["agents"][0]]),
		"an unknown archetype": _agent_with(good, "archetype", "weaver"),
		"a bad position": _agent_with(good, "position", [1, INF, 0]),
		"a missing brain": _agent_with(good, "brain", null),
		"a brain from another agent": _agent_with(good, "brain", good["agents"][1]["brain"]),
		"an empty id": _agent_with(good, "id", ""),
	}
	for name: String in cases:
		var report := society.import_state(cases[name])
		assert_false(report.ok, name)
		assert_gt(report.errors.size(), 0, "%s has a reason" % name)
		assert_eq(society.state_hash(), hash, "%s changed nothing" % name)
	assert_eq(society.import_state(_with(good, "schema", 2)).schema, 2, "the claimed schema is reported")


func test_attached_bodies_stay_attached_across_a_load() -> void:
	var society := _populated()
	var saved := society.export_state()
	var body := Node3D.new()
	add_child_autofree(body)
	society.get_agent(&"bo").attach_body(body)
	body.global_position = Vector3(9, 9, 9)
	assert_true(society.import_state(saved).ok)
	assert_eq(society.get_agent(&"bo").body(), body)
	assert_eq(body.global_position, Vector3(1.5, 0, -2), "moved to the loaded position")


func _with(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := source.duplicate(true)
	out[key] = value
	return out


func _agent_with(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := source.duplicate(true)
	out["agents"][0][key] = value
	return out


func test_64_bit_numbers_survive_a_json_round_trip_exactly() -> void:
	var big := 9007199254740993 # 2^53 + 1: not exact as a JSON float
	var society := BustleSociety.new(big)
	society.register_archetype(&"baker", _library(&"bake"))
	society.add_agent(&"ann", &"baker")
	var senses := BustleSenses.new()
	senses.now_minutes = 3
	society.get_agent(&"ann").brain.tick(0.1, senses)
	var text := JSON.stringify(society.export_state())
	var copy := _society()
	var report := copy.import_state(JSON.parse_string(text))
	assert_true(report.ok, str(report.errors))
	assert_eq(copy.world_seed, big)
	assert_eq(copy.get_agent(&"ann").brain.export_state()["rng_state"],
		society.get_agent(&"ann").brain.export_state()["rng_state"], "the generator state is exact")
	assert_eq(copy.state_hash(), society.state_hash())
	senses.now_minutes = 40
	assert_eq(copy.get_agent(&"ann").brain.tick(0.1, senses).to_dictionary(),
		society.get_agent(&"ann").brain.tick(0.1, senses).to_dictionary(), "and carries on alike")


func test_64_bit_fields_accept_ints_or_decimal_strings_and_refuse_others() -> void:
	assert_eq(BustleSociety.to_int64("-9223372036854775808"), -9223372036854775808)
	assert_eq(BustleSociety.to_int64("9223372036854775807"), 9223372036854775807)
	assert_eq(BustleSociety.to_int64(12), 12)
	assert_eq(BustleSociety.to_int64("007"), 7)
	for bad: Variant in ["9223372036854775808", "1.5", "+4", "--4", "", "x", 1.0, null]:
		assert_null(BustleSociety.to_int64(bad), "refused: %s" % [bad])
	var society := _populated()
	var saved := society.export_state()
	saved["world_seed"] = int(saved["world_seed"])
	saved["agents"][0]["brain"]["rng_state"] = int(saved["agents"][0]["brain"]["rng_state"])
	assert_true(_society().import_state(saved).ok, "plain ints are accepted too")
	var hash := society.state_hash()
	assert_false(society.import_state(_agent_with(society.export_state(), "brain", {"rng_state": "1e5"})).ok)
	assert_false(society.import_state(_with(society.export_state(), "world_seed", "12.5")).ok)
	assert_eq(society.state_hash(), hash)
