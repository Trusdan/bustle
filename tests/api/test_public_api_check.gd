# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The public API check's rules, on fixture manifests (docs/public-api/VERSIONING.md): a frozen
## symbol removed, renamed or changed fails unless deprecations.json covers it; new symbols pass.

const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const FIXTURES := "res://tests/api/fixtures/"


static func _load(file: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + file))
	return data if data is Dictionary else {}


static func _base() -> Dictionary:
	return _load("manifest_base.json")


static func _example(manifest: Dictionary) -> Dictionary:
	return manifest["frozen"]["BustleExample"]


func test_the_fixtures_load() -> void:
	assert_eq(_base()["frozen"].size(), 2)
	assert_eq(_load("deprecations_method.json")["deprecations"].size(), 1)


func test_an_unchanged_surface_passes() -> void:
	var result := ApiDiff.compare(_base(), _base(), null)
	assert_true(ApiDiff.passes(result))
	for key: String in ["breaking", "deprecated", "added", "notes", "errors"]:
		assert_eq(result[key], [], key)


func test_a_removed_method_fails() -> void:
	var current := _base()
	_example(current)["methods"].erase("old_name")
	var result := ApiDiff.compare(_base(), current, _load("deprecations_class.json"))
	assert_false(ApiDiff.passes(result), "an entry for another symbol doesn't cover it")
	assert_eq(result["breaking"], ["BustleExample.old_name: removed or renamed"])


func test_a_removed_method_with_a_deprecation_entry_passes() -> void:
	var current := _base()
	_example(current)["methods"].erase("old_name")
	current["version"] = "2.0.0"
	var result := ApiDiff.compare(_base(), current, _load("deprecations_method.json"))
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["deprecated"], ["BustleExample.old_name: removed or renamed (deprecated in 1.1.0)"])


func test_a_rename_fails_as_a_removal_and_reports_the_new_name() -> void:
	var current := _base()
	var methods: Dictionary = _example(current)["methods"]
	methods.erase("old_name")
	methods["new_name"] = "func new_name(id: StringName) -> void"
	var result := ApiDiff.compare(_base(), current, null)
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], ["BustleExample.old_name: removed or renamed"])
	assert_eq(result["added"], ["BustleExample.new_name: func new_name(id: StringName) -> void"])


func test_changed_signatures_fail() -> void:
	var cases: Array = [
		["methods", "old_name", "func old_name(id: StringName, now: int = 0) -> void"],
		["properties", "weight", "var weight: int"],
		["constants", "STATE_VERSION", "const STATE_VERSION = 1"],
	]
	for change: Array in cases:
		var current := _base()
		_example(current)[change[0]][change[1]] = change[2]
		var result := ApiDiff.compare(_base(), current, null)
		assert_false(ApiDiff.passes(result), str(change))
		assert_eq(result["breaking"].size(), 1, str(change))
		assert_string_contains(str(result["breaking"]), "signature changed")


func test_changed_signal_arguments_and_hook_type_fail() -> void:
	var current := _base()
	_example(current)["signals"]["changed"]["signature"] = "signal changed(id: StringName)"
	_example(current)["hooks"]["score_hook"]["signature"] = "var score_hook: Variant"
	var result := ApiDiff.compare(_base(), current, null)
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"].size(), 2)


func test_a_changed_purpose_alone_passes() -> void:
	var current := _base()
	_example(current)["purpose"] = "Reworded."
	_example(current)["signals"]["changed"]["purpose"] = "Reworded too."
	assert_true(ApiDiff.passes(ApiDiff.compare(_base(), current, null)))


func test_new_symbols_pass() -> void:
	var current := _base()
	_example(current)["methods"]["extra"] = "func extra() -> void"
	_example(current)["signals"]["also"] = {"signature": "signal also()", "purpose": ""}
	current["frozen"]["BustleNewThing"] = {"addon": "bustle", "path": "addons/bustle/new_thing.gd", "kind": "class",
		"extends": "RefCounted", "purpose": "", "methods": {}, "properties": {}, "hooks": {}, "signals": {},
		"constants": {}, "save": {}}
	var result := ApiDiff.compare(_base(), current, null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["added"].size(), 3)


func test_a_removed_class_fails_once_and_a_class_entry_covers_it() -> void:
	var current := _base()
	current["frozen"].erase("BustleExamplePort")
	current["version"] = "2.0.0"
	var result := ApiDiff.compare(_base(), current, null)
	assert_eq(result["breaking"], ["BustleExamplePort: removed or renamed"], "its members aren't listed again")
	var covered := ApiDiff.compare(_base(), current, _load("deprecations_class.json"))
	assert_true(ApiDiff.passes(covered))
	assert_eq(covered["deprecated"].size(), 1)


func test_a_class_entry_covers_its_members() -> void:
	var current := _base()
	current["frozen"]["BustleExamplePort"]["methods"].erase("lookup")
	current["version"] = "2.0.0"
	assert_true(ApiDiff.passes(ApiDiff.compare(_base(), current, _load("deprecations_class.json"))))


func test_moving_a_frozen_symbol_back_to_experimental_fails() -> void:
	var current := _base()
	_example(current)["properties"].erase("weight")
	current["experimental_members"]["BustleExample.weight"] = "Not settled."
	var whole := _base()
	var entry: Dictionary = whole["frozen"]["BustleExamplePort"]
	whole["frozen"].erase("BustleExamplePort")
	whole["experimental"]["BustleExamplePort"] = {"path": entry["path"], "reason": "Not settled."}
	assert_eq(ApiDiff.compare(_base(), current, null)["breaking"], ["BustleExample.weight: no longer frozen (now @experimental)"])
	assert_eq(ApiDiff.compare(_base(), whole, null)["breaking"], ["BustleExamplePort: no longer frozen (now @experimental)"])


func test_a_raised_save_version_is_noted_not_failed() -> void:
	var current := _base()
	_example(current)["constants"]["STATE_VERSION"] = "const STATE_VERSION = 3"
	var result := ApiDiff.compare(_base(), current, null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["notes"].size(), 1)
	assert_string_contains(str(result["notes"]), "save format raised")


func test_a_malformed_deprecations_file_fails() -> void:
	var result := ApiDiff.compare(_base(), _base(), _load("deprecations_bad.json"))
	assert_false(ApiDiff.passes(result))
	assert_eq(result["errors"].size(), 3, "a bad symbol, a bad version and a duplicate")
	assert_false(ApiDiff.passes(ApiDiff.compare(_base(), _base(), {"deprecations": "none"})))


func test_an_addon_missing_from_the_checkout_is_skipped() -> void:
	var baseline := _base()
	baseline["addons"] = ["bustle", "bustle_wyrd"]
	baseline["frozen"]["BustleBridgeExample"] = {"addon": "bustle_wyrd", "path": "addons/bustle_wyrd/x.gd",
		"kind": "class", "extends": "RefCounted", "purpose": "", "methods": {"m": "func m() -> void"},
		"properties": {}, "hooks": {}, "signals": {}, "constants": {}, "save": {}}
	var result := ApiDiff.compare(baseline, _base(), null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["notes"], ["bustle_wyrd is not in this checkout; its symbols were not compared"])


func test_the_report_puts_breaking_changes_first() -> void:
	var current := _base()
	_example(current)["methods"].erase("old_name")
	_example(current)["methods"]["extra"] = "func extra() -> void"
	var text := ApiDiff.report(ApiDiff.compare(_base(), current, null), "the fixture")
	assert_lt(text.find("Breaking changes"), text.find("New public symbols"))
	assert_string_contains(ApiDiff.report(ApiDiff.compare(_base(), _base(), null), "x"), "No changes")
