# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The population bench: a synthetic, neutral town of 40 FULL agents (in the player's area), 40
## LIGHT (next door) and 200 OFF_SCREEN (elsewhere), run through [BustleSimRings]. Every agent has
## six goals, each a two-step sequence of timed waits, chosen from needs that rise and fall on a
## fixed per-agent cycle (no rolls), so choices and sequences keep changing.
##
## [b]Budgets.[/b] One game hour at 60 frames a second and 30× game speed: it times each ring's
## thinking per frame (FULL is the brains and their sequences) and reports the averages and 99th
## percentiles against the proposed budgets, the whole frame, the static memory the population
## takes, and the save size per agent. Numbers from a shared CI runner are a report, not a claim
## about any machine.
##
## [b]Stuck at scale.[/b] Then a run of game days, one game minute a tick (the real seconds a game
## minute takes at 30×, so FULL and LIGHT agents think at most once a minute), with every agent
## watched for being stuck each minute (the demo harness's stuck watch): a step still inside its
## expected time, or off-screen catch-up still advancing, is legitimate; anything else needs
## progress (a new goal or step).
##
## It exits 1 when an average is over budget, the save size is over budget, or an agent was stuck.
##   godot --headless --path . -s res://bench/population_bench.gd [-- --full=40 --light=40 --offscreen=200 --frames=7200 --days=1 --seed=1]

const StuckWatch := preload("res://demo/harness/demo_stuck_watch.gd")

## FULL brains and sequences: average and 99th percentile milliseconds per frame.
const BUDGET_FULL_MS := 1.0
const BUDGET_FULL_P99_MS := 2.0
## LIGHT: average milliseconds per frame.
const BUDGET_LIGHT_MS := 0.3
## OFF_SCREEN: average milliseconds per frame, amortised over the game hour.
const BUDGET_OFFSCREEN_MS := 0.5
## Save size: bytes per agent.
const BUDGET_SAVE_BYTES := 2048
## Game seconds per real second in the budget run.
const GAME_SPEED := 30.0
## The needs, each with its own rise per game minute.
const NEEDS := {&"need.food": 0.0009, &"need.sleep": 0.0007, &"need.company": 0.0011}

var _full := 40
var _light := 40
var _offscreen := 200
var _frames := 7200
var _days := 1
var _seed := 1


## Puts FULL agents in the player's area (indoors, so the whole of it is FULL), LIGHT ones next
## door and everyone else far away.
class Town:
	extends BustleWorldPort
	var area: Dictionary = {}

	func area_of(id: StringName) -> StringName:
		return area.get(id, &"far")

	func player_area() -> StringName:
		return &"square"

	func is_interior(p_area: StringName) -> bool:
		return p_area == &"square"

	func neighbour_areas(_area: StringName) -> Array[StringName]:
		var out: Array[StringName] = [&"lane"]
		return out


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1).to_int()
		match arg.get_slice("=", 0):
			"--full": _full = value
			"--light": _light = value
			"--offscreen": _offscreen = value
			"--frames": _frames = value
			"--days": _days = value
			"--seed": _seed = value
	_run.call_deferred()


func _run() -> void:
	var memory_before := OS.get_static_memory_usage()
	var town := build(_full, _light, _offscreen, _seed)
	var memory := OS.get_static_memory_usage() - memory_before
	var perf := time_hour(town, _frames)
	var save := save_bytes(town)
	var stuck := stuck_pass(build(_full, _light, _offscreen, _seed), _days)
	var counts: Dictionary = perf["counts"]
	var agents := _full + _light + _offscreen
	var ok: bool = perf["full_avg"] <= BUDGET_FULL_MS and perf["full_p99"] <= BUDGET_FULL_P99_MS \
		and perf["light_avg"] <= BUDGET_LIGHT_MS and perf["off_avg"] <= BUDGET_OFFSCREEN_MS \
		and save / agents <= BUDGET_SAVE_BYTES and (stuck["spells"] as Array).is_empty()
	print("population bench: %d FULL, %d LIGHT, %d OFF_SCREEN, seed %d, %d frames (%d game min), %d stuck days, Godot %s, build %s: FULL average %.3f ms p99 %.3f ms (budget %.1f / %.1f), LIGHT average %.3f ms p99 %.3f ms (budget %.1f), OFF_SCREEN average %.3f ms p99 %.3f ms (budget %.1f), frame average %.3f ms p99 %.3f ms, memory %.1f KiB (%.0f B an agent), save %d B an agent (budget %d), stuck spells %d, longest still %d min: %s" % [
		counts["FULL"], counts["LIGHT"], counts["OFF_SCREEN"], _seed, _frames, perf["minutes"], _days,
		Engine.get_version_info()["string"], _build_sha(), perf["full_avg"], perf["full_p99"], BUDGET_FULL_MS,
		BUDGET_FULL_P99_MS, perf["light_avg"], perf["light_p99"], BUDGET_LIGHT_MS, perf["off_avg"], perf["off_p99"],
		BUDGET_OFFSCREEN_MS, perf["frame_avg"], perf["frame_p99"], memory / 1024.0, float(memory) / agents,
		save / agents, BUDGET_SAVE_BYTES, (stuck["spells"] as Array).size(), stuck["longest"], "OK" if ok else "OVER BUDGET"])
	for spell: Dictionary in stuck["spells"]:
		print("  stuck: %s" % JSON.stringify(spell, "", true))
	quit(0 if ok else 1)


## A town of [param full] FULL, [param light] LIGHT and [param offscreen] OFF_SCREEN agents seeded
## [param world_seed]: {society, rings, town}. The rings are sorted once.
static func build(full: int, light: int, offscreen: int, world_seed: int) -> Dictionary:
	var society := BustleSociety.new(world_seed)
	society.register_archetype(&"townsfolk", library())
	var town := Town.new()
	society.set_port(&"world", town)
	for i: int in full + light + offscreen:
		var id := StringName("townsfolk_%03d" % i)
		society.add_agent(id, &"townsfolk")
		town.area[id] = &"square" if i < full else (&"lane" if i < full + light else &"far")
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	var rings := BustleSimRings.new(society, config)
	rings.senses_provider = func(id: StringName, _ring: int, minute: int) -> BustleSenses:
		return senses_for(world_seed, id, minute)
	rings.tick(0.0)
	return {"society": society, "rings": rings, "town": town}


## The senses of [param id] at game [param minute]: each need on its own fixed cycle, offset per
## agent from the seed. No rolls.
static func senses_for(world_seed: int, id: StringName, minute: int) -> BustleSenses:
	var senses := BustleSenses.new()
	var phase := float(posmod(BustleBrain.seed_for(world_seed, id), 1000)) / 1000.0
	var index := 0
	for need: StringName in NEEDS:
		senses.inputs[need] = fposmod(phase + index / 3.0 + float(minute) * float(NEEDS[need]), 1.0)
		index += 1
	senses.now_minutes = minute
	return senses


## Six goals over the three needs, each a two-step sequence of timed waits.
static func library() -> BustleGoalLibrary:
	var out := BustleGoalLibrary.new()
	var specs := [[&"eat", &"need.food", 30], [&"cook", &"need.food", 50], [&"rest", &"need.sleep", 60],
		[&"nap", &"need.sleep", 20], [&"chat", &"need.company", 15], [&"visit", &"need.company", 40]]
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
		goal.sequence = BustleActionSequence.new()
		for minutes: int in [int(spec[2]), int(spec[2]) / 2]:
			var step := BustleActionStep.new()
			step.action = &"wait"
			step.params = {"minutes": minutes}
			goal.sequence.steps.append(step)
		out.goals.append(goal)
	return out


## One game hour of [param town] at 60 frames a second and 30× speed, over [param frames] frames:
## each ring's average and 99th percentile milliseconds per frame, the whole frame's, the game
## minutes simulated and the ring counts.
static func time_hour(town: Dictionary, frames: int) -> Dictionary:
	var society: BustleSociety = town["society"]
	var rings: BustleSimRings = town["rings"]
	var step := 1.0 / 60.0
	var game_seconds := 0.0
	var samples := {"FULL": [] as Array[float], "LIGHT": [] as Array[float], "OFF_SCREEN": [] as Array[float],
		"frame": [] as Array[float]}
	var started := society.ports.clock.now_minutes()
	for frame: int in frames:
		game_seconds += step * GAME_SPEED
		while game_seconds >= 60.0:
			game_seconds -= 60.0
			society.ports.clock.advance(1)
		var began := Time.get_ticks_usec()
		rings.tick(step)
		(samples["frame"] as Array[float]).append((Time.get_ticks_usec() - began) / 1000.0)
		for ring: String in ["FULL", "LIGHT", "OFF_SCREEN"]:
			(samples[ring] as Array[float]).append(rings.last_timings[ring] / 1000.0)
	return {"counts": rings.counts(), "minutes": society.ports.clock.now_minutes() - started,
		"full_avg": average(samples["FULL"]), "full_p99": p99(samples["FULL"]),
		"light_avg": average(samples["LIGHT"]), "light_p99": p99(samples["LIGHT"]),
		"off_avg": average(samples["OFF_SCREEN"]), "off_p99": p99(samples["OFF_SCREEN"]),
		"frame_avg": average(samples["frame"]), "frame_p99": p99(samples["frame"])}


## [param town]'s save (the society's export as JSON), in bytes.
static func save_bytes(town: Dictionary) -> int:
	return JSON.stringify((town["society"] as BustleSociety).export_state()).to_utf8_buffer().size()


## [param days] game days of [param town], one game minute a tick, every agent watched each
## minute: {spells, longest, hash}, the hash being the society's state at the end.
static func stuck_pass(town: Dictionary, days: int) -> Dictionary:
	var society: BustleSociety = town["society"]
	var rings: BustleSimRings = town["rings"]
	var watch := StuckWatch.new()
	var steps := {}
	for minute: int in days * 1440:
		society.ports.clock.advance(1)
		rings.tick(60.0 / GAME_SPEED)
		var now := society.ports.clock.now_minutes()
		for id: StringName in society.agent_ids():
			var state := society.get_agent(id)
			var intent := state.brain.last_intent
			var goal := intent.goal_id if intent != null else &""
			var key := "%s|%d" % [goal, state.brain.runner.step_index]
			var seen: Dictionary = steps.get(id, {})
			if seen.get("key", "") != key:
				seen = {"key": key, "since": now}
				steps[id] = seen
			var interval := 60 if state.sim_ring == BustleSimRings.Ring.OFF_SCREEN else 1
			watch.observe(id, now, 1, {"goal": goal,
				"step": state.brain.runner.step_index, "place": (town["town"] as Town).area_of(id),
				"legit": intent == null or now - int(seen["since"]) <= _step_minutes(state.brain) + interval
					or (state.sim_ring == BustleSimRings.Ring.OFF_SCREEN and now - state.last_update_minute <= interval)})
	var longest := 0
	for id: StringName in society.agent_ids():
		longest = maxi(longest, watch.longest_still(id))
	return {"spells": watch.spells(), "longest": longest, "hash": society.state_hash()}


## The arithmetic mean of [param samples].
static func average(samples: Array[float]) -> float:
	var total := 0.0
	for sample: float in samples:
		total += sample
	return total / maxi(samples.size(), 1)


## The 99th percentile of [param samples].
static func p99(samples: Array[float]) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if not sorted.is_empty() else 0.0


# The game minutes the brain's current step should take: its wait, or 0.
static func _step_minutes(brain: BustleBrain) -> int:
	if brain.last_intent == null or brain.library == null:
		return 0
	var goal := brain.library.find(brain.last_intent.goal_id)
	if goal == null or goal.sequence == null or brain.runner.step_index >= goal.sequence.steps.size():
		return 0
	return int(goal.sequence.steps[brain.runner.step_index].params.get("minutes", 0))


static func _build_sha() -> String:
	var env := OS.get_environment("GITHUB_SHA")
	if env != "":
		return env
	var head := FileAccess.get_file_as_string("res://.git/HEAD").strip_edges()
	if head.begins_with("ref: "):
		head = FileAccess.get_file_as_string("res://.git/" + head.substr(5)).strip_edges()
	return head if head != "" else "unknown"
