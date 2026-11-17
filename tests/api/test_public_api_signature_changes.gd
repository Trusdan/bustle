# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## When the public API check accepts a covered signature change (docs/public-api/VERSIONING.md,
## "The check"): by the same rule as a covered removal, only in a major release after the minor
## release that deprecated it. The current release is the current manifest's "version".
## Fixtures: tests/api/fixtures/.

const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const ApiManifest := preload("res://tools/public_api/api_manifest.gd")
const FIXTURES := "res://tests/api/fixtures/"
const SAME_MAJOR := "signature changes need a major release after the minor that deprecated it"
const NO_MINOR := "it was deprecated in a major release, so its warning never shipped in a minor release"
const WAS := "func old_name(id: StringName) -> void"
const NOW := "func old_name(id: StringName, now: int = 0) -> void"
const CALL := "func(id: StringName) -> float"
const NEW_CALL := "func(id: StringName, now: int) -> float"


static func _load(file: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + file))
	return data if data is Dictionary else {}


static func _base() -> Dictionary:
	return _load("manifest_base.json")


## The base manifest with BustleExample.old_name's signature changed, at [param version].
static func _changed(version: String) -> Dictionary:
	var current := _base()
	current["frozen"]["BustleExample"]["methods"]["old_name"] = NOW
	current["version"] = version
	return current


## The hook-calls manifest with score_hook's call set to [param call], at [param version].
static func _hook_call(call: String, version: String) -> Dictionary:
	var manifest := _load("manifest_hook_calls.json")
	manifest["frozen"]["BustleExample"]["hooks"]["score_hook"]["call"] = call
	manifest["version"] = version
	return manifest


static func _hook_flat(call: String) -> String:
	return "var score_hook: Callable" + ApiManifest.CALL_SEPARATOR + call


static func _held_back(version: String, since: String, why: String) -> String:
	return "BustleExample.old_name: signature changed in %s; %s (since %s)\n    was: %s\n    now: %s" % [
		version, why, since, WAS, NOW]


func _assert_fails(result: Dictionary, line: String) -> void:
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], [line])
	assert_eq(result["deprecated"], [])


func _assert_passes(result: Dictionary, line: String) -> void:
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["deprecated"], [line])


func test_the_fixtures_hold_the_signatures_these_tests_change() -> void:
	assert_eq(_base()["frozen"]["BustleExample"]["methods"]["old_name"], WAS)
	assert_eq(_load("manifest_hook_calls.json")["frozen"]["BustleExample"]["hooks"]["score_hook"].get("call", ""), CALL)


func test_a_covered_change_in_the_same_major_fails() -> void:
	for version: String in ["1.3.0", "1.3.1", "1.4.0"]:
		_assert_fails(ApiDiff.compare(_base(), _changed(version), _load("deprecations_since_minor.json")),
			_held_back(version, "1.3.0", SAME_MAJOR))


func test_a_covered_change_whose_deprecation_was_a_major_release_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _changed("3.0.0"), _load("deprecations_since_major.json")),
		_held_back("3.0.0", "2.0.0", NO_MINOR))


func test_a_covered_change_in_the_next_major_passes() -> void:
	var line := "BustleExample.old_name: signature changed\n    was: %s\n    now: %s (deprecated in 1.3.0)" % [WAS, NOW]
	for version: String in ["2.0.0", "2.1.0", "3.0.0"]:
		_assert_passes(ApiDiff.compare(_base(), _changed(version), _load("deprecations_since_minor.json")), line)


func test_a_deprecation_from_before_1_0_lets_the_change_go_in_1_0() -> void:
	assert_true(ApiDiff.passes(ApiDiff.compare(_base(), _changed("1.0.0"), _load("deprecations_since_pre_one.json"))))


func test_a_covered_change_with_no_usable_current_version_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _changed(""), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: signature changed, but the current version (\"\") isn't x.y.z, so the signature change can't be checked (since 1.3.0)\n    was: %s\n    now: %s" % [WAS, NOW])


func test_a_class_entry_holds_a_member_change_to_the_same_rule() -> void:
	var current := _base()
	current["frozen"]["BustleExamplePort"]["methods"]["lookup"] = "func lookup(id: StringName, strict: bool) -> int"
	current["version"] = "1.4.0"
	var result := ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json"))
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"].size(), 1)
	assert_string_starts_with(str(result["breaking"][0]), "BustleExamplePort.lookup: signature changed in 1.4.0; %s (since 1.3.0)" % SAME_MAJOR)
	current["version"] = "2.0.0"
	assert_true(ApiDiff.passes(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json"))))


func test_a_covered_hook_call_change_follows_the_same_rule() -> void:
	var base := _hook_call(CALL, "1.0.0")
	var deprecations := _load("deprecations_hook_call.json")
	_assert_fails(ApiDiff.compare(base, _hook_call(NEW_CALL, "1.4.0"), deprecations),
		"BustleExample.score_hook: signature changed in 1.4.0; %s (since 1.3.0)\n    was: %s\n    now: %s" % [
			SAME_MAJOR, _hook_flat(CALL), _hook_flat(NEW_CALL)])
	_assert_passes(ApiDiff.compare(base, _hook_call(NEW_CALL, "2.0.0"), deprecations),
		"BustleExample.score_hook: signature changed\n    was: %s\n    now: %s (deprecated in 1.3.0)" % [
			_hook_flat(CALL), _hook_flat(NEW_CALL)])


func test_an_uncovered_change_still_fails_as_before_in_a_major() -> void:
	_assert_fails(ApiDiff.compare(_base(), _changed("2.0.0"), null),
		"BustleExample.old_name: signature changed\n    was: %s\n    now: %s" % [WAS, NOW])


func test_a_raised_save_version_is_still_a_note_with_an_entry() -> void:
	var current := _base()
	var old_line: String = current["frozen"]["BustleExample"]["constants"]["STATE_VERSION"]
	current["frozen"]["BustleExample"]["constants"]["STATE_VERSION"] = old_line.replace("= 2", "= 3")
	current["version"] = "1.4.0"
	var result := ApiDiff.compare(_base(), current, _load("deprecations_hook_class.json"))
	assert_true(ApiDiff.passes(result))
	assert_eq(result["notes"].size(), 1)
