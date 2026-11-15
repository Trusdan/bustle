# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## A raised save version is a note, not a break (docs/saves.md): STATE_VERSION and the society's
## SCHEMA alike. Lowering one, or changing any other constant, still fails.

const ApiDiff := preload("res://tools/public_api/api_diff.gd")


static func _with_schema(value: int) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/api/fixtures/manifest_base.json"))
	var manifest: Dictionary = data
	manifest["frozen"]["BustleExample"]["constants"]["SCHEMA"] = "const SCHEMA = %d" % value
	return manifest


func test_a_raised_schema_is_noted_not_failed() -> void:
	var result := ApiDiff.compare(_with_schema(1), _with_schema(2), null)
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["notes"], ["BustleExample.SCHEMA: save format raised (const SCHEMA = 1 -> const SCHEMA = 2); import_state() must still read the older shape"])


func test_a_lowered_schema_fails() -> void:
	var result := ApiDiff.compare(_with_schema(2), _with_schema(1), null)
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], ["BustleExample.SCHEMA: signature changed\n    was: const SCHEMA = 2\n    now: const SCHEMA = 1"])


func test_both_save_version_names_are_listed() -> void:
	assert_eq(ApiDiff.SAVE_VERSIONS, ["STATE_VERSION", "SCHEMA"] as Array[String])
