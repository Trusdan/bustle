# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Memory and FindPerson: half-life decay and forgetting below the threshold, stronger notes
## winning, capacity, saving, event-driven writes from perception, and FindPerson by sensing, in
## another area from memory, by routine, by asking, and giving up with a cooldown.

const S := BustleDetectionMeter.State
const HOUR := 60

var _memories: Dictionary[StringName, BustleMemory] = {}


func before_each() -> void:
	_memories = {&"seeker": BustleMemory.new(), &"neighbour": BustleMemory.new(), &"stranger": BustleMemory.new()}


func test_entries_decay_on_their_half_lives_and_drop_below_the_threshold() -> void:
	var memory := BustleMemory.new()
	assert_true(memory.note(BustleMemory.PERSON, &"smith", &"forge", Vector3(1, 0, 2), BustleMemory.SAW, 0))
	assert_true(memory.note(BustleMemory.PLACE, &"well", &"square", Vector3.ZERO, BustleMemory.SAW, 0))
	assert_almost_eq(memory.confidence(BustleMemory.PERSON, &"smith", 6 * HOUR), 0.5, 1e-6, "a person halves in 6 hours")
	assert_almost_eq(memory.confidence(BustleMemory.PERSON, &"smith", 12 * HOUR), 0.25, 1e-6)
	assert_almost_eq(memory.confidence(BustleMemory.PLACE, &"well", 720 * HOUR), 0.5, 1e-6, "a place lasts far longer")
	assert_almost_eq(memory.confidence(BustleMemory.PERSON, &"smith", 19 * HOUR), pow(0.5, 19.0 / 6.0), 1e-6, "0.11: still held")
	assert_eq(memory.recall(BustleMemory.PERSON, &"smith", 20 * HOUR), {}, "0.099: forgotten")
	assert_eq(memory.size(), 1, "and gone for good")
	var told := BustleMemory.new()
	told.note(BustleMemory.ITEM, &"ladder", &"barn", null, BustleMemory.TOLD, 0)
	assert_almost_eq(told.confidence(BustleMemory.ITEM, &"ladder", 72 * HOUR), 0.4, 1e-6, "told starts at 0.8")
	assert_eq(told.recall(BustleMemory.ITEM, &"ladder", 0)["position"], null, "the position may be unknown")


func test_a_weaker_note_never_overwrites_a_stronger_one_and_capacity_drops_the_weakest() -> void:
	var memory := BustleMemory.new()
	memory.note(BustleMemory.PERSON, &"smith", &"forge", Vector3.ZERO, BustleMemory.SAW, 0)
	assert_false(memory.note(BustleMemory.PERSON, &"smith", &"tavern", null, BustleMemory.HEARD, 60), "a rumour doesn't beat a fresh sighting")
	assert_eq(memory.recall(BustleMemory.PERSON, &"smith", 60)["area"], &"forge")
	assert_true(memory.note(BustleMemory.PERSON, &"smith", &"tavern", null, BustleMemory.HEARD, 10 * HOUR), "but beats a faded one")
	assert_false(memory.note(BustleMemory.PERSON, &"x", &"a", null, &"dreamt", 0), "unknown sources aren't kept")
	var small := BustleMemoryConfig.new()
	small.capacity = 2
	var full := BustleMemory.new(small)
	full.note(BustleMemory.PERSON, &"a", &"one", null, BustleMemory.SAW, 0)
	full.note(BustleMemory.PERSON, &"b", &"two", null, BustleMemory.ROUTINE, 0)
	full.note(BustleMemory.PERSON, &"c", &"three", null, BustleMemory.TOLD, 0)
	assert_eq(full.size(), 2)
	assert_eq(full.recall(BustleMemory.PERSON, &"b", 0), {}, "the weakest went")
	assert_false(full.recall(BustleMemory.PERSON, &"a", 0).is_empty())
	assert_eq(BustleMemoryConfig.new().capacity, 32)


func test_memory_saves_and_bad_data_changes_nothing() -> void:
	var memory := BustleMemory.new()
	memory.note(BustleMemory.PERSON, &"smith", &"forge", Vector3(1, 2, 3), BustleMemory.SAW, 10)
	memory.note(BustleMemory.ITEM, &"ladder", &"barn", null, BustleMemory.TOLD, 20)
	var saved := memory.export_state()
	var other := BustleMemory.new()
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.export_state(), saved)
	assert_eq(other.recall(BustleMemory.PERSON, &"smith", 10)["position"], Vector3(1, 2, 3))
	assert_false(other.import_state({"entries": [{"kind": "person", "subject": "x", "area": "", "source": "saw", "strength": NAN, "at": 0, "position": null}]}))
	assert_false(other.import_state({"entries": [{"kind": "person", "subject": "x", "area": "", "source": "saw", "strength": 1, "at": 0, "position": [1, 2]}]}))
	assert_false(other.import_state("nope"))
	assert_eq(other.export_state(), saved, "refused imports change nothing")


func test_memory_writes_come_from_perception_events() -> void:
	var world := BustlePerceptionWorld.new()
	var profile := BustlePerceptionProfile.new()
	profile.perception_hz = 0.0
	world.line_of_sight = func(_a: Vector3, _b: Vector3, _p: StringName, _t: StringName) -> bool: return true
	var seeker := BustlePerceptionActor.new(&"seeker", profile)
	world.add_actor(seeker)
	var target := BustlePerceptionActor.new(&"smith")
	target.position = Vector3(0, 0, -3)
	world.add_actor(target)
	var minute := [480]
	var feed := BustleMemoryFeed.new(world, func(id: StringName) -> BustleMemory: return _memories.get(id), func() -> int: return minute[0])
	feed.area_of = func(_id: StringName) -> StringName: return &"square"
	assert_eq(_memories[&"seeker"].size(), 0, "nothing until perception changes")
	for i in 180:
		world.tick(1.0 / 60.0)
	var seen := _memories[&"seeker"].recall(BustleMemory.PERSON, &"smith", 480)
	assert_eq([seen["area"], seen["position"], seen["source"]], [&"square", Vector3(0, 0, -3), BustleMemory.SAW], "noted when alert")
	minute[0] = 600
	world.perception_changed.emit(&"stranger", &"smith", S.SUSPICIOUS, S.ALERT)
	assert_eq(_memories[&"stranger"].recall(BustleMemory.PERSON, &"smith", 600)["area"], &"square", "each perceiver's own memory")
	world.perception_changed.emit(&"nobody", &"smith", S.UNAWARE, S.ALERT)
	feed.disconnect_world()
	world.perception_changed.emit(&"neighbour", &"smith", S.SUSPICIOUS, S.ALERT)
	assert_eq(_memories[&"neighbour"].size(), 0, "no writes after disconnecting")
	for id: StringName in world.actor_ids():
		world.remove_actor(id)


func test_losing_track_notes_the_area_that_goes_with_the_last_known_position() -> void:
	var world := BustlePerceptionWorld.new()
	var profile := BustlePerceptionProfile.new()
	profile.perception_hz = 0.0
	world.line_of_sight = func(_a: Vector3, _b: Vector3, _p: StringName, _t: StringName) -> bool: return true
	world.add_actor(BustlePerceptionActor.new(&"seeker", profile))
	var target := BustlePerceptionActor.new(&"smith")
	target.position = Vector3(0, 0, -3)
	world.add_actor(target)
	var minute := [480]
	var where := {&"smith": &"square"}
	var feed := BustleMemoryFeed.new(world, func(id: StringName) -> BustleMemory: return _memories.get(id), func() -> int: return minute[0])
	feed.area_of = func(id: StringName) -> StringName: return where.get(id, &"")
	for i in 180:
		world.tick(1.0 / 60.0)
	var last: Variant = world.last_known(&"seeker", &"smith")
	assert_eq(last, Vector3(0, 0, -3))
	where[&"smith"] = &"mill"
	minute[0] = 540
	world.perception_changed.emit(&"seeker", &"smith", S.SEARCHING, S.UNAWARE)
	var lost := _memories[&"seeker"].recall(BustleMemory.PERSON, &"smith", 540)
	assert_eq([lost["area"], lost["position"], lost["source"], lost["at"]], [&"square", last, BustleMemory.SAW, 540],
		"the area it was seen in, not the one it walked into")
	world.perception_changed.emit(&"stranger", &"cart", S.SEARCHING, S.UNAWARE)
	assert_eq(_memories[&"stranger"].size(), 0, "no last-known position: nothing written")
	world.perception_changed.emit(&"neighbour", &"smith", S.SUSPICIOUS, S.UNAWARE)
	assert_eq(_memories[&"neighbour"].size(), 0, "suspicion alone, never alert: nothing written")
	world.perception_changed.emit(&"stranger", &"smith", S.UNAWARE, S.SUSPICIOUS)
	assert_eq(_memories[&"stranger"].size(), 0, "a suspicion writes nothing")
	world.perception_changed.emit(&"seeker", &"smith", S.SEARCHING, S.UNAWARE)
	assert_eq(_memories[&"seeker"].recall(BustleMemory.PERSON, &"smith", 540)["area"], &"square", "a second loss without a new sighting adds nothing new")
	feed.disconnect_world()
	for id: StringName in world.actor_ids():
		world.remove_actor(id)


func test_a_note_dropped_at_once_by_a_full_memory_reports_false() -> void:
	var small := BustleMemoryConfig.new()
	small.capacity = 1
	var memory := BustleMemory.new(small)
	memory.note(BustleMemory.PERSON, &"a", &"one", null, BustleMemory.SAW, 0)
	assert_false(memory.note(BustleMemory.PERSON, &"b", &"two", null, BustleMemory.ROUTINE, 0), "too weak to stay")
	assert_false(memory.recall(BustleMemory.PERSON, &"a", 0).is_empty())
	assert_false(memory.import_state({"entries": [{"kind": "person", "subject": "", "area": "", "source": "saw", "strength": 1, "at": 0, "position": null}]}), "an empty subject")
	assert_false(memory.import_state({"entries": [{"kind": "person", "subject": "x", "area": "", "source": "dreamt", "strength": 1, "at": 0, "position": null}]}), "an unknown source")


func test_find_person_by_sense_in_the_same_area() -> void:
	var finder := _finder()
	finder.sense = func(_s: StringName, t: StringName) -> Dictionary:
		return {"area": &"square", "position": Vector3(2, 0, 0)} if t == &"smith" else {}
	var found := finder.find(&"seeker", &"smith", 600)
	assert_eq([found["found"], found["how"], found["area"], found["position"]], [true, BustleFindPerson.SENSED, &"square", Vector3(2, 0, 0)])
	assert_eq(_memories[&"seeker"].recall(BustleMemory.PERSON, &"smith", 600)["source"], BustleMemory.SAW, "and remembers it")


func test_find_person_in_another_area_from_memory_or_routine() -> void:
	var finder := _finder()
	_memories[&"seeker"].note(BustleMemory.PERSON, &"smith", &"forge", Vector3(5, 0, 5), BustleMemory.SAW, 0)
	var found := finder.find(&"seeker", &"smith", 2 * HOUR)
	assert_eq([found["how"], found["area"]], [BustleFindPerson.REMEMBERED, &"forge"], "remembered in another area")
	finder.routine = func(t: StringName, _now: int) -> Dictionary: return {"area": &"mill"} if t == &"miller" else {}
	found = finder.find(&"seeker", &"miller", 2 * HOUR)
	assert_eq([found["how"], found["area"], found["position"]], [BustleFindPerson.GUESSED, &"mill", null], "guessed from the routine")
	assert_eq(_memories[&"seeker"].recall(BustleMemory.PERSON, &"miller", 2 * HOUR)["source"], BustleMemory.ROUTINE)
	assert_eq(finder.find(&"seeker", &"smith", 20 * HOUR)["how"], BustleFindPerson.UNKNOWN, "a memory too faded to act on doesn't count")


func test_find_person_by_asking() -> void:
	var finder := _finder()
	finder.ask_whom = func(_s: StringName) -> Array: return [&"stranger", &"neighbour"]
	_memories[&"neighbour"].note(BustleMemory.PERSON, &"smith", &"tavern", Vector3(9, 0, 1), BustleMemory.SAW, 540)
	var found := finder.find(&"seeker", &"smith", 600)
	assert_eq([found["how"], found["from"], found["area"]], [BustleFindPerson.ASKED, &"neighbour", &"tavern"], "the stranger didn't know; the neighbour did")
	var learnt := _memories[&"seeker"].recall(BustleMemory.PERSON, &"smith", 600)
	assert_eq([learnt["source"], learnt["area"]], [BustleMemory.TOLD, &"tavern"], "now the seeker knows too")


func test_find_person_gives_up_gracefully_with_a_cooldown() -> void:
	var finder := _finder()
	finder.ask_whom = func(_s: StringName) -> Array: return [&"stranger"]
	var lost := finder.find(&"seeker", &"hermit", 600)
	assert_eq([lost["found"], lost["how"], lost["area"], lost["position"]], [false, BustleFindPerson.UNKNOWN, &"", null])
	assert_eq(finder.cooldown_until(&"seeker", &"hermit"), 660)
	_memories[&"stranger"].note(BustleMemory.PERSON, &"hermit", &"woods", null, BustleMemory.SAW, 610)
	assert_eq(finder.find(&"seeker", &"hermit", 620)["how"], BustleFindPerson.COOLING_DOWN, "no search while cooling down")
	assert_eq(finder.find(&"seeker", &"hermit", 660)["how"], BustleFindPerson.ASKED, "then it tries again")
	assert_eq(finder.cooldown_until(&"seeker", &"hermit"), -1, "and the ended cooldown is dropped")
	assert_eq(BustleFindPerson.new().find(&"a", &"b", 0)["how"], BustleFindPerson.UNKNOWN, "with no sources at all, it just doesn't know")


func _finder() -> BustleFindPerson:
	var finder := BustleFindPerson.new()
	finder.memory_of = func(id: StringName) -> BustleMemory: return _memories.get(id)
	return finder
