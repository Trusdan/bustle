# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The rings decide exactly what they did before their performance work: the same thinks in the
## same order, ring changes, catch-up reports, summaries and saves. ring_trace.gd records a seeded
## scenario; ring_trace.txt holds the hashes the code gave before that work (main 9ddebe80).
## Never re-record the fixture to make a performance change pass: a mismatch means the change
## altered behaviour.

const Trace := preload("res://tests/rings/ring_trace.gd")
const FIXTURE := "res://tests/rings/ring_trace.txt"


func test_the_rings_decide_as_before() -> void:
	var expected := FileAccess.get_file_as_string(FIXTURE).split("\n", false)
	var actual := Trace.lines()
	assert_eq(actual.size(), expected.size(), "block count")
	for i in mini(actual.size(), expected.size()):
		if actual[i] != expected[i]:
			fail_test("first difference in block %d (frames %d to %d): got \"%s\", expected \"%s\"" % [
				i, i * Trace.BLOCK, i * Trace.BLOCK + Trace.BLOCK - 1, actual[i], expected[i]])
			return
	pass_test("%d blocks identical" % expected.size())


func test_last_timings_keeps_its_keys() -> void:
	var rings := BustleSimRings.new(BustleSociety.new(1), BustleSimRingConfig.new())
	rings.config.manage_bodies = false
	rings.tick(0.1)
	assert_eq(rings.last_timings.keys(), ["FULL", "LIGHT", "OFF_SCREEN"])
	for key: String in rings.last_timings:
		assert_eq(typeof(rings.last_timings[key]), TYPE_INT, key)
