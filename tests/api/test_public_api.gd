# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The committed public API manifest and its page agree with each other and with the addons
## (docs/public-api/VERSIONING.md). tools/public_api.sh compares the manifest with the code itself.

const ApiManifest := preload("res://tools/public_api/api_manifest.gd")
const ApiDiff := preload("res://tools/public_api/api_diff.gd")
const DIR := "res://docs/public-api/"


static func _manifest() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "public_api.json"))
	return data if data is Dictionary else {}


static func _class_paths() -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		out[String(entry["class"])] = String(entry["path"]).trim_prefix("res://")
	return out


func test_the_page_is_what_the_manifest_renders() -> void:
	var manifest := _manifest()
	assert_false(manifest.is_empty(), "public_api.json parses")
	assert_eq(FileAccess.get_file_as_string(DIR + "PUBLIC_API.md"), ApiManifest.render(manifest))


func test_it_covers_classes_ports_hooks_signals_and_save_calls() -> void:
	var totals := ApiManifest.totals(_manifest())
	for kind: String in ["classes", "ports", "hooks", "signals", "save_calls"]:
		assert_gt(int(totals[kind]), 0, kind)


func test_its_version_is_the_addons() -> void:
	assert_eq(_manifest()["version"], BustleInfo.VERSION)


func test_the_deprecations_file_is_valid_and_the_manifest_passes_against_itself() -> void:
	var deprecations: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "deprecations.json"))
	assert_eq(ApiDiff.validate_deprecations(deprecations), [])
	assert_true(ApiDiff.passes(ApiDiff.compare(_manifest(), _manifest(), deprecations)))


func test_every_listed_class_is_at_its_path() -> void:
	var paths := _class_paths()
	var manifest := _manifest()
	for group: String in ["frozen", "experimental"]:
		for name: String in manifest[group]:
			var entry: Dictionary = manifest[group][name]
			if not DirAccess.dir_exists_absolute("res://addons/" + str(entry.get("addon", entry["path"].get_slice("/", 1)))):
				continue
			assert_eq(paths.get(name, ""), entry["path"], name)


func test_every_addon_class_is_listed_once() -> void:
	var manifest := _manifest()
	var paths := _class_paths()
	var wrong: Array[String] = []
	for name: String in paths:
		var path: String = paths[name]
		if not path.begins_with("addons/bustle/") and not path.begins_with("addons/bustle_wyrd/"):
			continue
		if int(manifest["frozen"].has(name)) + int(manifest["experimental"].has(name)) != 1:
			wrong.append(name)
	assert_eq(wrong, [] as Array[String], "each addon class is frozen or experimental, once")


func test_frozen_scripts_have_no_class_level_experimental_tag() -> void:
	var manifest := _manifest()
	for name: String in manifest["frozen"]:
		var path: String = "res://" + str(manifest["frozen"][name]["path"])
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		assert_eq(text.count("@experimental:"), _members_of(manifest, name), "%s: only its experimental members are tagged" % name)
		assert_false(text.contains("## @experimental\n"), "%s: every tag gives its reason" % name)


func test_experimental_classes_and_members_give_a_reason() -> void:
	var manifest := _manifest()
	for name: String in manifest["experimental"]:
		assert_ne(manifest["experimental"][name]["reason"], "(no reason given)", name)
	for symbol: String in manifest["experimental_members"]:
		assert_ne(manifest["experimental_members"][symbol], "(no reason given)", symbol)


func test_no_frozen_signature_names_an_experimental_class() -> void:
	var manifest := _manifest()
	var flat := ApiManifest.flatten(manifest)
	var leaks: Array[String] = []
	for name: String in manifest["experimental"]:
		var word := RegEx.create_from_string("\\b%s\\b" % name)
		for symbol: String in flat:
			if word.search(flat[symbol]) != null:
				leaks.append("%s uses %s" % [symbol, name])
	assert_eq(leaks, [] as Array[String])


static func _members_of(manifest: Dictionary, name: String) -> int:
	var count: int = 0
	for symbol: String in manifest["experimental_members"]:
		if symbol.get_slice(".", 0) == name:
			count += 1
	return count
