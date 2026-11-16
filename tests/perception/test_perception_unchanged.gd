# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Perception decides exactly what it did before its performance work: the same state changes,
## rays, senses, meter states and public meter results, bit for bit. perception_trace.gd records
## a seeded scenario; perception_trace.txt holds the hashes the code gave before that work
## (main 9ddebe80). Never re-record the fixture to make a performance change pass: a mismatch
## means the change altered behaviour.

const Trace := preload("res://tests/perception/perception_trace.gd")
const FIXTURE := "res://tests/perception/perception_trace.txt"


func _expected(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in FileAccess.get_file_as_string(FIXTURE).split("\n", false):
		if line.begins_with(prefix + " "):
			out.append(line)
	return out


func _assert_same(actual: PackedStringArray, prefix: String) -> void:
	var expected := _expected(prefix)
	assert_eq(actual.size(), expected.size(), "%s: block count" % prefix)
	for i in mini(actual.size(), expected.size()):
		if actual[i] != expected[i]:
			fail_test("%s: first difference in block %d: got \"%s\", expected \"%s\"" % [prefix, i, actual[i], expected[i]])
			return
	pass_test("%s: %d blocks identical" % [prefix, expected.size()])


func test_the_world_decides_as_before() -> void:
	_assert_same(Trace.world_lines(), "world")


func test_the_public_meter_calls_give_what_they_did() -> void:
	_assert_same(Trace.meter_lines(), "meter")


func test_the_system_syncs_and_decides_as_before() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	_assert_same(Trace.system_lines(host), "system")


func test_the_trace_is_deterministic() -> void:
	assert_eq(Trace.meter_lines(), Trace.meter_lines())
