# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted
## A seeded ring scenario that records everything the rings decide, for
## test_rings_unchanged.gd: every think in tick order (agent, ring, minute), every ring change,
## catch-up report and summary, and the society's save at intervals. FULL, LIGHT and OFF_SCREEN
## agents mix in id order; areas change; the clock jumps past the catch-up cap; the host edits
## OFF_SCREEN agents' last_update_minute; the roster and the OFF_SCREEN interval change. Each
## block of the record is hashed; the fixture holds the hashes made by the code before the
## performance work, so the same results give the same lines.

## Frames per hashed block (one real second).
const BLOCK := 60


## Places agents by a table the scenario edits; the player is in "square", next to "lane".
class Town:
	extends BustleWorldPort
	var areas: Dictionary = {}

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"far")

	func player_area() -> StringName:
		return &"square"

	func neighbour_areas(_area: StringName) -> Array[StringName]:
		var out: Array[StringName] = [&"lane"]
		return out


static func lines() -> PackedStringArray:
	var society := BustleSociety.new(23)
	society.register_archetype(&"villager", _library())
	var town := Town.new()
	society.set_port(&"world", town)
	var record: Array[String] = []
	for i in 40:
		var id := StringName("v%02d" % i)
		var state := society.add_agent(id, &"villager")
		match i % 5:
			0:
				town.areas[id] = &"square"
				state.position = Vector3(i * 2.0, 0, 0)
				state.has_position = true
			1:
				town.areas[id] = &"lane"
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	config.catch_up_cap_game_days = 1
	var rings := BustleSimRings.new(society, config)
	var inputs: Dictionary[StringName, float] = {&"need.food": 0.4, &"need.sleep": 0.6, &"need.company": 0.5}
	rings.senses_provider = func(id: StringName, ring: int, minute: int) -> BustleSenses:
		record.append("think %s %d %d" % [id, ring, minute])
		var senses := BustleSenses.new()
		senses.inputs = inputs
		return senses
	rings.summary_hook = func(id: StringName, report: Dictionary) -> void:
		record.append("summary %s %s" % [id, var_to_str(report)])
	rings.caught_up.connect(func(id: StringName, report: Dictionary) -> void:
		record.append("caught_up %s %s" % [id, var_to_str(report)]))
	rings.ring_changed.connect(func(id: StringName, old: int, new: int) -> void:
		record.append("ring %s %d %d" % [id, old, new]))
	var out := PackedStringArray()
	for frame in 2400:
		if frame % 4 == 0:
			society.ports.clock.advance(1)
		match frame:
			600:
				for id: StringName in [&"v02", &"v03", &"v04", &"v07"]:
					town.areas[id] = &"lane"
				for id: StringName in [&"v01", &"v06"]:
					town.areas[id] = &"far"
			900:
				society.ports.clock.advance(3 * 1440 + 17)
			1200:
				society.get_agent(&"v08").last_update_minute = -1
				society.get_agent(&"v09").last_update_minute -= 3 * 60
			1500:
				society.remove_agent(&"v12")
				society.add_agent(&"v40", &"villager")
			1800:
				config.offscreen_interval_game_minutes = 30
		rings.tick(1.0 / 60.0)
		record.append("frame %d timings %s" % [frame, var_to_str(rings.last_timings.keys())])
		if frame % 300 == 299:
			record.append("save %s" % _sha(var_to_bytes(society.export_state())))
			for id: StringName in society.agent_ids():
				var state := society.get_agent(id)
				record.append("%s ring %d last %d" % [id, rings.ring_of(id), state.last_update_minute])
		if frame % BLOCK == BLOCK - 1:
			out.append(_block("rings %d" % (frame / BLOCK), record))
	return out


static func _library() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	var specs := [[&"eat", &"need.food"], [&"rest", &"need.sleep"], [&"chat", &"need.company"],
		[&"work", &"need.food"], [&"walk", &"need.company"], [&"sit", &"need.sleep"]]
	for spec: Array in specs:
		var goal := BustleGoalDef.new()
		goal.id = spec[0]
		goal.band = BustleBands.PERSONAL
		var consideration := BustleConsideration.new()
		consideration.input = spec[1]
		consideration.curve = Curve.new()
		consideration.curve.add_point(Vector2(0, 0))
		consideration.curve.add_point(Vector2(1, 1))
		goal.considerations.append(consideration)
		library.goals.append(goal)
	return library


# One fixture line for the record so far, which it then clears.
static func _block(label: String, record: Array[String]) -> String:
	var line := "%s: %d lines %s" % [label, record.size(), _sha("\n".join(record).to_utf8_buffer())]
	record.clear()
	return line


static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().substr(0, 24)
