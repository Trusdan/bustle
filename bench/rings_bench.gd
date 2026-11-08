# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The ring bench: a neutral town of 40 LIGHT agents (in the area next to the player's) and 200
## OFF_SCREEN agents (elsewhere), each with a small goal library, run for one game hour at 60 frames
## a second and 30× game speed (two real minutes). It times each ring's thinking per frame and
## reports the agent counts, the simulated time, the engine version and the raw timings (average
## and 99th percentile) against the proposed budgets, and exits 1 when an average is over budget.
##   godot --headless --path . -s res://bench/rings_bench.gd [-- --light=40 --offscreen=200 --frames=7200]

## LIGHT: average milliseconds per frame.
const BUDGET_LIGHT_MS := 0.3
## OFF_SCREEN: average milliseconds per frame, amortised over the game hour.
const BUDGET_OFFSCREEN_MS := 0.5
## Game seconds per real second.
const GAME_SPEED := 30.0

var _light := 40
var _offscreen := 200
var _frames := 7200


## Puts LIGHT agents in the neighbour area and everyone else far away.
class Town:
	extends BustleWorldPort
	var light: Dictionary = {}

	func area_of(id: StringName) -> StringName:
		return &"lane" if light.has(id) else &"far"

	func player_area() -> StringName:
		return &"square"

	func neighbour_areas(_area: StringName) -> Array[StringName]:
		var out: Array[StringName] = [&"lane"]
		return out


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--light="):
			_light = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--offscreen="):
			_offscreen = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--frames="):
			_frames = arg.get_slice("=", 1).to_int()
	_run.call_deferred()


func _run() -> void:
	var society := BustleSociety.new(11)
	society.register_archetype(&"villager", _library())
	var town := Town.new()
	society.set_port(&"world", town)
	for i in _light + _offscreen:
		var id := StringName("villager_%d" % i)
		society.add_agent(id, &"villager")
		if i < _light:
			town.light[id] = true
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	var rings := BustleSimRings.new(society, config)
	var inputs: Dictionary[StringName, float] = {&"need.food": 0.4, &"need.sleep": 0.6, &"need.company": 0.5}
	rings.senses_provider = func(_id: StringName, _ring: int, _minute: int) -> BustleSenses:
		var senses := BustleSenses.new()
		senses.inputs = inputs
		return senses
	rings.tick(0.0)
	var step := 1.0 / 60.0
	var game_seconds := 0.0
	var light_ms: Array[float] = []
	var off_ms: Array[float] = []
	for frame in _frames:
		game_seconds += step * GAME_SPEED
		while game_seconds >= 60.0:
			game_seconds -= 60.0
			society.ports.clock.advance(1)
		rings.tick(step)
		light_ms.append(rings.last_timings["LIGHT"] / 1000.0)
		off_ms.append(rings.last_timings["OFF_SCREEN"] / 1000.0)
	var counts := rings.counts()
	var light_avg := _average(light_ms)
	var off_avg := _average(off_ms)
	var ok := light_avg <= BUDGET_LIGHT_MS and off_avg <= BUDGET_OFFSCREEN_MS
	print("rings bench: %d LIGHT, %d OFF_SCREEN, %d frames (%.0f real s, %d game min), Godot %s: LIGHT average %.3f ms p99 %.3f ms (budget %.1f), OFF_SCREEN average %.3f ms p99 %.3f ms (budget %.1f): %s" % [
		counts["LIGHT"], counts["OFF_SCREEN"], _frames, _frames * step, society.ports.clock.now_minutes(),
		Engine.get_version_info()["string"], light_avg, _p99(light_ms), BUDGET_LIGHT_MS,
		off_avg, _p99(off_ms), BUDGET_OFFSCREEN_MS, "OK" if ok else "OVER BUDGET"])
	quit(0 if ok else 1)


func _library() -> BustleGoalLibrary:
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


func _average(samples: Array[float]) -> float:
	var total := 0.0
	for sample: float in samples:
		total += sample
	return total / maxi(samples.size(), 1)


func _p99(samples: Array[float]) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if not sorted.is_empty() else 0.0
