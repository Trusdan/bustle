# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Callable hook calls in the public API check (docs/public-api/VERSIONING.md): a hook's call is
## the [code]func(...) -> T[/code] that opens its doc comment. A changed or dropped call is a
## signature change; a call recorded for the first time is a note. Fixtures: tests/api/fixtures/.

const ApiManifest := preload("res://tools/public_api/api_manifest.gd")
const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const FIXTURES := "res://tests/api/fixtures/"
const SIGNATURE := "var score_hook: Callable"
const CALL := "func(id: StringName) -> float"


static func _load(file: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + file))
	return data if data is Dictionary else {}


## The manifest whose BustleExample.score_hook has the call [constant CALL].
static func _with_call() -> Dictionary:
	return _load("manifest_hook_calls.json")


## That manifest with the hook's call replaced by [param call] ("" drops it), at [param version].
static func _call_changed(call: String, version: String = "1.0.0") -> Dictionary:
	var current := _with_call()
	var hook: Dictionary = current["frozen"]["BustleExample"]["hooks"]["score_hook"]
	if call == "":
		hook.erase("call")
	else:
		hook["call"] = call
	current["version"] = version
	return current


static func _flat(call: String) -> String:
	return SIGNATURE + ApiManifest.CALL_SEPARATOR + call if call != "" else SIGNATURE


static func _changed_line(from: String, to: String) -> String:
	return "BustleExample.score_hook: signature changed\n    was: %s\n    now: %s" % [_flat(from), _flat(to)]


func test_the_fixtures_load() -> void:
	assert_eq(_with_call()["frozen"]["BustleExample"]["hooks"]["score_hook"]["call"], CALL)
	assert_eq(_load("deprecations_hook_call.json")["deprecations"].size(), 1)
	assert_eq(_load("deprecations_hook_class.json")["deprecations"].size(), 1)


func test_a_changed_call_fails() -> void:
	var calls: Array[String] = [
		"func(id: StringName, now: int) -> float",
		"func() -> float",
		"func(id: String) -> float",
		"func(id: StringName) -> int",
	]
	for call: String in calls:
		var result := ApiDiff.compare(_with_call(), _call_changed(call), null)
		assert_false(ApiDiff.passes(result), call)
		assert_eq(result["breaking"], [_changed_line(CALL, call)], call)


func test_a_changed_call_with_an_entry_for_the_hook_passes_in_the_next_major() -> void:
	var call := "func(id: StringName, now: int) -> float"
	var result := ApiDiff.compare(_with_call(), _call_changed(call, "2.0.0"), _load("deprecations_hook_call.json"))
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["deprecated"], [_changed_line(CALL, call) + " (deprecated in 1.3.0)"])


func test_a_changed_call_with_an_entry_for_its_class_passes_in_the_next_major() -> void:
	var call := "func(id: StringName) -> int"
	var result := ApiDiff.compare(_with_call(), _call_changed(call, "2.0.0"), _load("deprecations_hook_class.json"))
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["deprecated"], [_changed_line(CALL, call) + " (deprecated in 1.3.0)"])


func test_a_call_recorded_for_the_first_time_is_a_note() -> void:
	var result := ApiDiff.compare(_load("manifest_base.json"), _with_call(), null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["added"], [])
	assert_eq(result["notes"], ["BustleExample.score_hook: call recorded: " + CALL])


func test_a_dropped_call_fails() -> void:
	var result := ApiDiff.compare(_with_call(), _call_changed(""), null)
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], [_changed_line(CALL, "")])


func test_an_unchanged_call_passes() -> void:
	var result := ApiDiff.compare(_with_call(), _with_call(), null)
	assert_true(ApiDiff.passes(result))
	for key: String in ["breaking", "deprecated", "added", "notes", "errors"]:
		assert_eq(result[key], [], key)


func test_a_hook_flattens_to_its_signature_plus_its_call() -> void:
	assert_eq(ApiManifest.flatten(_load("manifest_base.json"))["BustleExample.score_hook"], SIGNATURE,
		"no call: exactly the signature")
	assert_eq(ApiManifest.flatten(_with_call())["BustleExample.score_hook"], SIGNATURE + " called as " + CALL)


func test_call_of_reads_the_first_func_span() -> void:
	assert_eq(ApiManifest.call_of("[code]func(agent_id: StringName, goal_tags: Array[StringName]) -> bool[/code]: a gate."),
		"func(agent_id: StringName, goal_tags: Array[StringName]) -> bool")
	assert_eq(ApiManifest.call_of("[code]func() -> Array[StringName][/code]: every agent. See [code]func(x) -> int[/code]."),
		"func() -> Array[StringName]", "the first span wins")
	assert_eq(ApiManifest.call_of("(id) → a score. Unset: [code]1.0[/code]."), "", "no func span, no call")
	assert_eq(ApiManifest.call_of("[code]func(agent, amount, reason)[/code], with no return type."), "",
		"a span without a return type isn't a call")


func test_parse_and_build_record_the_call_from_doctool_xml() -> void:
	var record := ApiManifest.parse_class(FIXTURES + "hook_calls_class.xml")
	var records: Array[Dictionary] = [record]
	var addons: Array[String] = ["bustle"]
	var manifest := ApiManifest.build(records, {"BustleExample": "res://addons/bustle/example.gd"}, "1.0.0", addons)
	var hooks: Dictionary = manifest["frozen"]["BustleExample"]["hooks"]
	assert_eq(hooks.keys().size(), 2, "both Callable members are hooks")
	assert_eq(hooks["gate_hook"]["call"], "func(agent_id: StringName, goal_tags: Array[StringName], weight: float) -> bool")
	assert_eq(hooks["gate_hook"]["signature"], "var gate_hook: Callable")
	assert_eq(hooks["gate_hook"]["purpose"], "true lets the agent through.", "the call isn't repeated in the purpose")
	assert_false((hooks["plain_hook"] as Dictionary).has("call"), "no func span, no call")
	assert_false(manifest["frozen"]["BustleExample"]["properties"].has("gate_hook"))


func test_the_page_shows_each_call_verbatim() -> void:
	var page := ApiManifest.render(_with_call())
	assert_string_contains(page, "| Hook | Call | File | Purpose |")
	assert_string_contains(page, "| `BustleExample.score_hook` | `%s` |" % CALL)


func test_every_frozen_hook_in_the_committed_manifest_has_a_call() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/public-api/public_api.json"))
	assert_true(data is Dictionary, "public_api.json parses")
	var missing: Array[String] = []
	var count: int = 0
	for name: String in (data as Dictionary)["frozen"]:
		var hooks: Dictionary = data["frozen"][name]["hooks"]
		for hook: String in hooks:
			count += 1
			if str((hooks[hook] as Dictionary).get("call", "")) == "":
				missing.append("%s.%s" % [name, hook])
	assert_gt(count, 0, "the manifest has frozen hooks")
	assert_eq(missing, [] as Array[String], "every frozen hook's doc comment opens with [code]func(...) -> T[/code]")
