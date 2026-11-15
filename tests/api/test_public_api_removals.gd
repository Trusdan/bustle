# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## When the public API check accepts a covered removal (docs/public-api/VERSIONING.md, "Deprecating
## and removing"): only in a major release after the minor release that deprecated it. The
## current release is the current manifest's "version". Fixtures: tests/api/fixtures/.

const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const FIXTURES := "res://tests/api/fixtures/"
const SAME_MAJOR := "removals need a major release after the minor that deprecated it"
const NO_MINOR := "it was deprecated in a major release, so its warning never shipped in a minor release"


static func _load(file: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + file))
	return data if data is Dictionary else {}


static func _base() -> Dictionary:
	return _load("manifest_base.json")


## The base manifest without BustleExample.old_name, at [param version].
static func _without_old_name(version: String) -> Dictionary:
	var current := _base()
	current["frozen"]["BustleExample"]["methods"].erase("old_name")
	current["version"] = version
	return current


func _assert_fails(result: Dictionary, line: String) -> void:
	assert_false(ApiDiff.passes(result))
	assert_eq(result["breaking"], [line])
	assert_eq(result["deprecated"], [])


func _assert_passes(result: Dictionary, line: String) -> void:
	assert_true(ApiDiff.passes(result))
	assert_eq(result["breaking"], [])
	assert_eq(result["deprecated"], [line])


func test_the_fixtures_load() -> void:
	assert_eq(_load("deprecations_since_minor.json")["deprecations"].size(), 3)
	assert_eq(_load("deprecations_since_major.json")["deprecations"].size(), 1)
	assert_eq(_load("deprecations_since_pre_one.json")["deprecations"].size(), 1)


func test_a_covered_removal_in_a_minor_release_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name("1.4.0"), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: removed in 1.4.0; %s (since 1.3.0)" % SAME_MAJOR)


func test_a_covered_removal_in_a_patch_of_the_same_minor_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name("1.3.1"), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: removed in 1.3.1; %s (since 1.3.0)" % SAME_MAJOR)


func test_a_covered_removal_in_the_deprecating_release_itself_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name("1.3.0"), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: removed in 1.3.0; %s (since 1.3.0)" % SAME_MAJOR)


func test_a_covered_removal_in_the_next_major_passes() -> void:
	_assert_passes(ApiDiff.compare(_base(), _without_old_name("2.0.0"), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: removed or renamed (deprecated in 1.3.0)")


func test_a_covered_removal_in_a_later_major_or_its_minors_passes() -> void:
	for version: String in ["2.1.0", "3.0.0"]:
		_assert_passes(ApiDiff.compare(_base(), _without_old_name(version), _load("deprecations_since_minor.json")),
			"BustleExample.old_name: removed or renamed (deprecated in 1.3.0)")


func test_a_deprecation_from_before_1_0_can_go_in_1_0() -> void:
	_assert_passes(ApiDiff.compare(_base(), _without_old_name("1.0.0"), _load("deprecations_since_pre_one.json")),
		"BustleExample.old_name: removed or renamed (deprecated in 0.9.0)")


func test_a_covered_removal_whose_deprecation_was_a_major_release_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name("3.0.0"), _load("deprecations_since_major.json")),
		"BustleExample.old_name: removed in 3.0.0; %s (since 2.0.0)" % NO_MINOR)


func test_a_covered_removal_with_no_usable_current_version_fails() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name(""), _load("deprecations_since_minor.json")),
		"BustleExample.old_name: removed, but the current version (\"\") isn't x.y.z, so the removal can't be checked (since 1.3.0)")


func test_a_covered_move_to_experimental_follows_the_same_rule() -> void:
	var current := _base()
	current["frozen"]["BustleExample"]["properties"].erase("weight")
	current["experimental_members"]["BustleExample.weight"] = "Not settled."
	current["version"] = "1.4.0"
	_assert_fails(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json")),
		"BustleExample.weight: no longer frozen in 1.4.0; %s (since 1.3.0)" % SAME_MAJOR)
	current["version"] = "2.0.0"
	_assert_passes(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json")),
		"BustleExample.weight: no longer frozen (now @experimental) (deprecated in 1.3.0)")


func test_a_covered_class_removal_gives_one_line_for_the_class_and_its_members() -> void:
	var current := _base()
	current["frozen"].erase("BustleExamplePort")
	current["version"] = "1.4.0"
	_assert_fails(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json")),
		"BustleExamplePort: removed in 1.4.0; %s (since 1.3.0)" % SAME_MAJOR)
	current["version"] = "2.0.0"
	_assert_passes(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json")),
		"BustleExamplePort: removed or renamed (deprecated in 1.3.0)")


func test_a_class_entry_holds_a_member_removal_to_the_same_rule() -> void:
	var current := _base()
	current["frozen"]["BustleExamplePort"]["methods"].erase("lookup")
	current["version"] = "1.4.0"
	_assert_fails(ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json")),
		"BustleExamplePort.lookup: removed in 1.4.0; %s (since 1.3.0)" % SAME_MAJOR)


func test_a_covered_signature_change_is_unchanged_by_the_version() -> void:
	for version: String in ["1.3.0", "1.4.0", "2.0.0"]:
		var current := _base()
		current["frozen"]["BustleExample"]["methods"]["old_name"] = "func old_name(id: StringName, now: int = 0) -> void"
		current["version"] = version
		var result := ApiDiff.compare(_base(), current, _load("deprecations_since_minor.json"))
		assert_true(ApiDiff.passes(result), version)
		assert_eq(result["deprecated"].size(), 1, version)
		assert_string_contains(str(result["deprecated"]), "signature changed", version)


func test_an_uncovered_removal_still_fails_as_before_in_a_major() -> void:
	_assert_fails(ApiDiff.compare(_base(), _without_old_name("2.0.0"), null), "BustleExample.old_name: removed or renamed")
