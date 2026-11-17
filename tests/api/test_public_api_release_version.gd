# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## A release bumps BustleInfo.VERSION. The public API check reports that as a note, not a break:
## the release's own version string is not an API change. Any other constant still breaks.
## Fixtures: tests/api/fixtures/.

const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const FIXTURES := "res://tests/api/fixtures/"


static func _base() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "manifest_base.json"))
	var manifest: Dictionary = data if data is Dictionary else {}
	manifest["frozen"]["BustleInfo"] = {"addon": "bustle", "path": "addons/bustle/core/bustle_info.gd",
		"kind": "class", "extends": "RefCounted", "purpose": "The addon's version.",
		"methods": {}, "properties": {}, "hooks": {}, "signals": {}, "save": {},
		"constants": {"VERSION": "const VERSION = \"0.9.0\"", "OTHER": "const OTHER = 1"}}
	return manifest


## The base manifest with BustleInfo's constant [param name] set to [param line].
static func _with(name: String, line: String, version: String = "1.0.0") -> Dictionary:
	var current := _base()
	current["frozen"]["BustleInfo"]["constants"][name] = line
	current["version"] = version
	return current


func test_a_new_release_version_is_a_note() -> void:
	var result := ApiDiff.compare(_base(), _with("VERSION", "const VERSION = \"1.0.0\""), null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["notes"], ["BustleInfo.VERSION: release version changed (0.9.0 -> 1.0.0)"])


func test_any_new_release_version_is_a_note_minor_and_patch_included() -> void:
	for value: String in ["0.9.1", "0.10.0", "1.1.0", "2.0.0"]:
		var result := ApiDiff.compare(_base(), _with("VERSION", "const VERSION = \"%s\"" % value, value), null)
		assert_true(ApiDiff.passes(result), value)
		assert_eq(result["notes"], ["BustleInfo.VERSION: release version changed (0.9.0 -> %s)" % value])


func test_a_release_version_that_isnt_x_y_z_still_breaks() -> void:
	for line: String in ["const VERSION = \"1.0\"", "const VERSION = \"one\"", "const VERSION = 1", "const VERSION = \"1.0.0\" # x"]:
		var result := ApiDiff.compare(_base(), _with("VERSION", line), null)
		assert_false(ApiDiff.passes(result), line)
		assert_eq(result["notes"], [], line)


func test_another_constant_of_the_same_class_still_breaks() -> void:
	var result := ApiDiff.compare(_base(), _with("OTHER", "const OTHER = 2"), null)
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], ["BustleInfo.OTHER: signature changed\n    was: const OTHER = 1\n    now: const OTHER = 2"])


func test_a_version_constant_of_another_class_still_breaks() -> void:
	var baseline := _base()
	baseline["frozen"]["BustleExample"]["constants"]["VERSION"] = "const VERSION = \"0.9.0\""
	var current := _base()
	current["frozen"]["BustleExample"]["constants"]["VERSION"] = "const VERSION = \"1.0.0\""
	current["version"] = "1.0.0"
	var result := ApiDiff.compare(baseline, current, null)
	assert_false(ApiDiff.passes(result))
	assert_eq((result["breaking"] as Array).size(), 1)


func test_a_removed_release_version_still_breaks() -> void:
	var current := _base()
	(current["frozen"]["BustleInfo"]["constants"] as Dictionary).erase("VERSION")
	var result := ApiDiff.compare(_base(), current, null)
	assert_false(ApiDiff.passes(result))
	assert_string_starts_with(str(result["breaking"][0]), "BustleInfo.VERSION: removed")
