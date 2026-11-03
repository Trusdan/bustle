# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The disposition port and table: data decides who is hostile, with no code change.

const D := BustleDispositionPort.Disposition


func _table() -> BustleDispositionTable:
	var table := BustleDispositionTable.new()
	table.set_group_rule(&"village", &"bandits", D.HOSTILE)
	table.set_group_rule(&"village", &"travellers", D.FRIENDLY)
	return table


func test_the_standalone_port_is_neutral() -> void:
	assert_eq(BustleDispositionPort.new().disposition(&"a", &"village", &"b", &"bandits"), D.NEUTRAL)


func test_group_rules_are_symmetric_and_actor_rules_win() -> void:
	var table := _table()
	assert_eq(table.lookup(&"baker", &"village", &"thief", &"bandits"), D.HOSTILE)
	assert_eq(table.lookup(&"thief", &"bandits", &"baker", &"village"), D.HOSTILE, "symmetric")
	table.symmetric = false
	assert_eq(table.lookup(&"thief", &"bandits", &"baker", &"village"), D.NEUTRAL, "one-way")
	table.actors["baker>thief"] = D.FRIENDLY
	assert_eq(table.lookup(&"baker", &"village", &"thief", &"bandits"), D.FRIENDLY, "an actor rule wins")
	assert_eq(table.lookup(&"baker", &"village", &"smith", &"village"), D.NEUTRAL, "same group")
	table.same_group = D.FRIENDLY
	assert_eq(table.lookup(&"baker", &"village", &"smith", &"village"), D.FRIENDLY)
	assert_eq(table.lookup(&"x", &"", &"y", &""), D.NEUTRAL, "no group: the default")


func test_a_tres_value_switches_hostility_without_code() -> void:
	var path := "user://test_bustle_dispositions.tres"
	assert_eq(ResourceSaver.save(_table(), path), OK)
	var world := BustlePerceptionWorld.new()
	var profile := BustlePerceptionProfile.new()
	profile.perception_hz = 0.0
	var baker := world.add_actor(BustlePerceptionActor.new(&"baker", profile))
	baker.group = &"village"
	var stranger := world.add_actor(BustlePerceptionActor.new(&"stranger"))
	stranger.group = &"bandits"
	stranger.position = Vector3(0, 0, -4)
	world.disposition = BustleDispositionPort.new(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BustleDispositionTable)
	for i in 120:
		world.tick(1.0 / 60.0)
	assert_eq(world.known_with(&"baker", D.HOSTILE), [&"stranger"] as Array[StringName])
	var edited := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BustleDispositionTable
	edited.groups["village>bandits"] = D.NEUTRAL
	assert_eq(ResourceSaver.save(edited, path), OK)
	world.disposition = BustleDispositionPort.new(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BustleDispositionTable)
	assert_eq(world.known_with(&"baker", D.HOSTILE), [] as Array[StringName], "neutral now")
	assert_eq(world.known_with(&"baker", D.NEUTRAL), [&"stranger"] as Array[StringName])
	assert_eq(world.disposition_between(&"baker", &"stranger"), D.NEUTRAL)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
