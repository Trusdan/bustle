# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The median of several perf bench runs, as a markdown table: for each gated number (the same
## numbers and budgets bench/perf_gate.gd judges), the median, the lowest and the highest of the
## runs, and whether the median is within its budget. Each run is a folder that
## tools/perf_bench.sh wrote (perception.txt, rings.txt and population.txt). The reference run in
## .github/workflows/perf-windows.yml uses it; see docs/perf.md.
##   godot --headless --path . -s res://bench/perf_median.gd -- --label "default load" DIR [DIR ...]
## Exit code: 0 when every median is within budget, 1 when one isn't, 2 when a run is missing a
## bench line or a number.

const Gate := preload("res://bench/perf_gate.gd")


func _initialize() -> void:
	var label := "perf bench"
	var dirs: Array[String] = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--label" and i + 1 < args.size():
			label = args[i + 1]
			i += 2
			continue
		dirs.append(args[i])
		i += 1
	var runs: Array[Dictionary] = []
	for dir: String in dirs:
		runs.append(read_run(dir))
	var result := summarize(runs)
	print(table(label, result))
	quit(0 if result["ok"] else (2 if not result["complete"] else 1))


## The bench lines in [param dir], by bench (empty when a file is missing).
static func read_run(dir: String) -> Dictionary:
	var lines := {}
	for bench: String in Gate.BENCHES:
		var path := dir.path_join("%s.txt" % bench)
		lines[bench] = FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""
	return lines


## For each gated number in [param runs] (bench lines by bench, one dictionary a run): its label,
## budget, every run's value, the median, the lowest and the highest, and whether the median is
## within budget. "complete" is false when a run lacks a line at the budget configuration or a
## number; "ok" is true when complete and every median is within budget.
static func summarize(runs: Array[Dictionary]) -> Dictionary:
	var rows: Array[Dictionary] = []
	var complete := not runs.is_empty()
	for metric: Array in Gate.METRICS:
		var values: Array[float] = []
		for run: Dictionary in runs:
			var line := String(run.get(metric[0], ""))
			var found := RegEx.create_from_string(metric[2]).search(line)
			if not line.begins_with(Gate.BENCHES[metric[0]]) or found == null:
				complete = false
				continue
			values.append(found.get_string(1).to_float())
		var row := {"label": metric[1], "budget": float(metric[3]), "values": values}
		if not values.is_empty():
			var sorted := values.duplicate()
			sorted.sort()
			var middle := sorted.size() / 2
			row["median"] = sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) / 2.0
			row["min"] = sorted[0]
			row["max"] = sorted[-1]
			row["within"] = row["median"] <= row["budget"]
		rows.append(row)
	var ok := complete
	for row: Dictionary in rows:
		ok = ok and row.get("within", false)
	return {"rows": rows, "runs": runs.size(), "complete": complete, "ok": ok}


## [param result] (from [method summarize]) as a markdown table headed [param label].
static func table(label: String, result: Dictionary) -> String:
	var out: Array[String] = ["### %s: median of %d runs" % [label, result["runs"]], "",
		"| Number | Median | Min | Max | Budget | Median vs budget |", "| --- | --- | --- | --- | --- | --- |"]
	for row: Dictionary in result["rows"]:
		var budget := _number(row["label"], row["budget"])
		if not row.has("median"):
			out.append("| %s | missing | | | %s | missing |" % [row["label"], budget])
			continue
		out.append("| %s | %s | %s | %s | %s | %s |" % [row["label"], _number(row["label"], row["median"]),
			_number(row["label"], row["min"]), _number(row["label"], row["max"]), budget,
			"within" if row["within"] else "**over**"])
	out.append("")
	if not result["complete"]:
		out.append("**Incomplete:** a run is missing a bench line or a number.")
	else:
		out.append("**%s**" % ("Every median is within budget." if result["ok"] else "A median is over budget."))
	return "\n".join(out)


static func _number(label: String, value: float) -> String:
	return "%d" % roundi(value) if label.ends_with("per agent") or label.ends_with("spells") else "%.3f" % value
