# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The example project in examples/village/ uses the public API only: every Bustle class it names
## is frozen in docs/public-api/public_api.json, it touches no experimental member, and it reaches
## into no private member. (tools/example.sh runs the example itself, in its own project.)

const EXAMPLE := "res://examples/village"
const MANIFEST := "res://docs/public-api/public_api.json"


## The example's own scripts, not the addon copied in for running it.
static func _scripts(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for sub: String in DirAccess.get_directories_at(dir):
		if sub != "addons" and not sub.begins_with("."):
			out.append_array(_scripts(dir.path_join(sub)))
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	return out


func test_the_example_uses_only_frozen_public_api() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var frozen: Dictionary = manifest["frozen"]
	var experimental: Array = []
	for member: String in (manifest["experimental_members"] as Dictionary):
		experimental.append(member.get_slice(".", 1))
	var scripts := _scripts(EXAMPLE)
	assert_gt(scripts.size(), 4, "the example has its scripts")
	var named := 0
	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for found: RegExMatch in RegEx.create_from_string("\\b(Bustle[A-Z]\\w*)\\b").search_all(source):
			assert_true(frozen.has(found.get_string(1)), "%s: %s is frozen public API" % [path, found.get_string(1)])
			named += 1
		for member: String in experimental:
			assert_false(RegEx.create_from_string("\\.%s\\b" % member).search(source) != null,
					"%s uses no experimental member (%s)" % [path, member])
		assert_null(RegEx.create_from_string("\\w\\._[a-z]").search(source), "%s reaches into no private member" % path)
	assert_gt(named, 20, "the example uses Bustle")
