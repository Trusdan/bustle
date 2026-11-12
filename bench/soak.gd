# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The demo soak: runs the house and colony demos (at their own sizes, every module on) for a
## number of game days from a fixed seed, twice, and checks that the second run reproduces the
## first one's timeline hash. For each demo it reports the evidence a soak needs: the seed, the
## engine version and build commit, the population, the simulated days, the wall time and memory,
## the timeline size and hash, and the stuck diagnostics (stuck spells and each agent's longest
## run with no legitimate activity and no progress). It exits 1 when any agent was stuck, the
## replay's hash differs, or a run ends early.
##   godot --headless --path . -s res://bench/soak.gd [-- --days=30 --seed=1 --demo=house,colony]
## CI runs a short smoke on every change; the full 30-day soak runs nightly
## ([code].github/workflows/soak.yml[/code]).

const House := preload("res://demo/house/house.gd")
const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440

var _days := 30
var _seed := 1
var _demos: PackedStringArray = PackedStringArray(["house", "colony"])


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			_days = maxi(arg.get_slice("=", 1).to_int(), 1)
		elif arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--demo="):
			_demos = arg.get_slice("=", 1).split(",", false)
	_run.call_deferred()


func _run() -> void:
	var failed := false
	print("soak: seed %d, %d game days, engine %s, build %s" % [_seed, _days, Engine.get_version_info()["string"], build_sha()])
	for demo: String in _demos:
		var first := soak(demo, _seed, _days)
		var second := soak(demo, _seed, _days)
		var replayed: bool = first["hash"] == second["hash"]
		var stuck: Array = first["spells"]
		var ok: bool = replayed and stuck.is_empty() and int(first["days"]) == _days
		failed = failed or not ok
		print("soak %s: %d agents, %d days in %.0f ms (%.1f ms a day), static memory %.1f MiB, timeline %d entries, hash %s, replay %s, stuck spells %d, longest still %s: %s" % [
			demo, first["agents"], first["days"], first["wall_ms"], float(first["wall_ms"]) / float(first["days"]),
			float(first["memory"]) / 1048576.0, first["size"], first["hash"], "same" if replayed else "DIFFERENT",
			stuck.size(), JSON.stringify(first["longest"], "", true), "OK" if ok else "FAIL"])
		for spell: Dictionary in stuck:
			print("  stuck: %s" % JSON.stringify(spell, "", true))
	quit(1 if failed else 0)


## One soak of [param demo] ("house" or "colony") seeded [param world_seed] for [param days] game
## days: its evidence as {agents, days, wall_ms, memory, size, hash, spells, longest}.
static func soak(demo: String, world_seed: int, days: int) -> Dictionary:
	var run: RefCounted = House.build(world_seed) if demo == "house" else Colony.build(world_seed)
	var start: int = run.now
	var began := Time.get_ticks_usec()
	run.run(days * DAY)
	var longest := {}
	for id: StringName in run.agent_ids():
		longest[String(id)] = run.stuck.longest_still(id)
	return {"agents": run.agent_ids().size(), "days": (int(run.now) - start) / DAY,
		"wall_ms": float(Time.get_ticks_usec() - began) / 1000.0, "memory": OS.get_static_memory_usage(),
		"size": run.timeline.size(), "hash": run.timeline.hash(), "spells": run.stuck.spells(), "longest": longest}


## The build's commit: [code]GITHUB_SHA[/code] in CI, else what [code].git/HEAD[/code] names, else
## "unknown".
static func build_sha() -> String:
	var env := OS.get_environment("GITHUB_SHA")
	if env != "":
		return env
	var head := FileAccess.get_file_as_string("res://.git/HEAD").strip_edges()
	if head.begins_with("ref: "):
		head = FileAccess.get_file_as_string("res://.git/" + head.substr(5)).strip_edges()
	return head if head != "" else "unknown"
