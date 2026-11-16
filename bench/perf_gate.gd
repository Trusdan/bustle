# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree
## The performance gate (docs/perf.md, "Budgets and the CI gate"). It reads the summary line each
## timing bench printed, one file per bench in a folder, and judges every budgeted number against
## bench/perf_budgets.gd: a timing fails only above [code]CI_HEADROOM[/code] times its budget, the
## save size fails above its budget, and any stuck agent fails. A missing or unreadable line, or a
## bench run with other than the budget configuration, fails too. It prints one line per number
## and the machine it ran on, and exits 1 on any failure.
##   godot --headless --path . -s res://bench/perf_gate.gd -- DIR
## DIR holds perception.txt, rings.txt and population.txt (tools/perf_bench.sh writes them).

const Budgets := preload("res://bench/perf_budgets.gd")

## The bench files, and the start each summary line must have: the budget configuration.
const BENCHES := {
	"perception": "perception bench: 40 actors, 600 frames:",
	"rings": "rings bench: 40 LIGHT, 200 OFF_SCREEN, 7200 frames",
	"population": "population bench: 40 FULL, 40 LIGHT, 200 OFF_SCREEN, seed 1, 7200 frames",
}
## Gated numbers: bench, label, pattern for the number, budget, and whether it gets headroom.
const METRICS := [
	["perception", "perception average ms", "average ([0-9.]+) ms, p99", Budgets.PERCEPTION_AVG_MS, true],
	["perception", "perception p99 ms", "p99 ([0-9.]+) ms \\(budget", Budgets.PERCEPTION_P99_MS, true],
	["rings", "rings LIGHT average ms", "LIGHT average ([0-9.]+) ms", Budgets.LIGHT_AVG_MS, true],
	["rings", "rings OFF_SCREEN average ms", "OFF_SCREEN average ([0-9.]+) ms", Budgets.OFFSCREEN_AVG_MS, true],
	["population", "population FULL average ms", "FULL average ([0-9.]+) ms", Budgets.FULL_AVG_MS, true],
	["population", "population FULL p99 ms", "FULL average [0-9.]+ ms p99 ([0-9.]+) ms", Budgets.FULL_P99_MS, true],
	["population", "population LIGHT average ms", "LIGHT average ([0-9.]+) ms", Budgets.LIGHT_AVG_MS, true],
	["population", "population OFF_SCREEN average ms", "OFF_SCREEN average ([0-9.]+) ms", Budgets.OFFSCREEN_AVG_MS, true],
	["population", "population save B per agent", "save ([0-9]+) B an agent", float(Budgets.SAVE_BYTES_PER_AGENT), false],
	["population", "population stuck spells", "stuck spells ([0-9]+)", 0.0, false],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: godot --headless --path . -s res://bench/perf_gate.gd -- DIR")
		quit(2)
		return
	var lines := {}
	for bench: String in BENCHES:
		lines[bench] = FileAccess.get_file_as_string(args[0].path_join(bench + ".txt"))
	var result := judge(lines, Budgets.CI_HEADROOM)
	print(machine())
	for line: String in result["report"]:
		print(line)
	quit(0 if result["ok"] else 1)


## Judges the benches' output ([param lines]: bench name → its printed text) against the budgets,
## failing a timing above [param headroom] times its budget. Returns [code]ok[/code] (bool) and
## [code]report[/code] (one line per number, then the verdict).
static func judge(lines: Dictionary, headroom: float) -> Dictionary:
	var report := PackedStringArray()
	var ok := true
	var summary := {}
	for bench: String in BENCHES:
		summary[bench] = ""
		for line: String in str(lines.get(bench, "")).replace("\r", "").split("\n"):
			var head := bench + " bench: "
			if line.begins_with(head) and line.length() > head.length() and line[head.length()].is_valid_int():
				summary[bench] = line
		if summary[bench] == "":
			report.append("FAIL %s: no summary line from the %s bench (it crashed or printed nothing)" % [bench, bench])
			ok = false
		elif not summary[bench].begins_with(BENCHES[bench]):
			report.append("FAIL %s: not the budget configuration (it must start \"%s\")" % [bench, BENCHES[bench]])
			summary[bench] = ""
			ok = false
	for metric: Array in METRICS:
		var line: String = summary[metric[0]]
		if line == "":
			continue
		var found := RegEx.create_from_string(metric[2]).search(line)
		if found == null:
			report.append("FAIL %s: not found in the %s bench's line" % [metric[1], metric[0]])
			ok = false
			continue
		var value := found.get_string(1).to_float()
		var budget: float = metric[3]
		var limit: float = budget * headroom if metric[4] else budget
		var note := ""
		if value > limit:
			note = ": over the gate"
			ok = false
		elif value > budget:
			note = ": over budget, within the gate"
		var shown := "%.3f" if metric[4] else "%d"
		report.append(("%s %s: " + shown + " (budget " + shown + ", gate " + shown + ")%s") % [
			"FAIL" if value > limit else "ok", metric[1], value, budget, limit, note])
	report.append("perf gate (timings at %.1fx budget): %s" % [headroom, "OK" if ok else "FAILED"])
	return {"ok": ok, "report": report}


## The machine the gate runs on, as Godot reports it.
static func machine() -> String:
	return "machine: %s %s, %s, %d logical processors, Godot %s" % [OS.get_name(), OS.get_version(),
		OS.get_processor_name(), OS.get_processor_count(), Engine.get_version_info()["string"]]

