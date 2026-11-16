# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## Runs the village headless for two game days and checks that every part shows up: each job
## holder works, villagers eat, rooms give thoughts, and the square sees greetings. Prints a
## summary and quits with 0, or 1 when something is missing. tools/example.sh runs it in CI.

const Village := preload("res://village.gd")


func _init() -> void:
	var village: RefCounted = Village.new()
	var days := 2
	for i in days * 1440 / Village.STEP:
		village.call(&"step")
	var problems: PackedStringArray = []
	for id: StringName in [&"ann", &"bram", &"cora"]:
		if float(village.call(&"skill_level", id)) <= 0.0:
			problems.append("%s gained no skill from work" % id)
	if int(village.get(&"meals")) == 0:
		problems.append("nobody ate")
	if int(village.get(&"room_thoughts_seen")) == 0:
		problems.append("no room thoughts")
	if int(village.get(&"greetings")) == 0:
		problems.append("no greetings")
	var moods: Dictionary = village.get(&"moods")
	var lines: PackedStringArray = []
	for id: StringName in moods:
		lines.append("%s mood %.1f skill %.2f" % [id, (moods[id] as BustleMood).mood, float(village.call(&"skill_level", id))])
	print("village check: %d days, %d meals, %d work steps, %d greetings; %s" % [days, village.get(&"meals"),
			village.get(&"work_steps"), village.get(&"greetings"), ", ".join(lines)])
	if not problems.is_empty():
		printerr("village check failed: " + "; ".join(problems))
	quit(0 if problems.is_empty() else 1)
