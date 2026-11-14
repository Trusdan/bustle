# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The tutorial stays true: every Bustle class and every path it names exists, and its script runs
## and does what the page says. The module guide names only real modules and guides.

const TUTORIAL := "res://docs/tutorial.md"
const GUIDE := "res://docs/modules.md"


static func _classes() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		out.append(String(entry["class"]))
	return out


static func _matches(text: String, pattern: String) -> Array[String]:
	var regex := RegEx.create_from_string(pattern)
	var out: Array[String] = []
	for found: RegExMatch in regex.search_all(text):
		if not out.has(found.get_string(1)):
			out.append(found.get_string(1))
	return out


func _check_names(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text, "", path)
	var classes := _classes()
	var names := _matches(text, "\\b(Bustle[A-Z][A-Za-z]*)\\b")
	assert_gt(names.size(), 3, "%s names Bustle classes" % path)
	for name: String in names:
		assert_true(classes.has(name), "%s: class %s exists" % [path, name])
	var paths := _matches(text, "`((?:addons|demo|docs|tests)/[A-Za-z0-9_./]+?)`")
	assert_gt(paths.size(), 3, "%s names paths" % path)
	for named: String in paths:
		var target := "res://" + named
		var exists := FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target)
		assert_true(exists, "%s: %s exists" % [path, named])


func test_the_tutorial_names_only_real_classes_and_paths() -> void:
	_check_names(TUTORIAL)


func test_the_tutorial_script_runs_as_the_page_says() -> void:
	var text := FileAccess.get_file_as_string(TUTORIAL)
	var blocks := _matches(text, "(?s)```gdscript\\n(extends RefCounted.*?)```")
	assert_eq(blocks.size(), 1, "one whole script")
	var script := GDScript.new()
	script.source_code = blocks[0]
	assert_eq(script.reload(), OK, "it compiles")
	var household: RefCounted = script.new()
	var result: Dictionary = household.call(&"run", 2)
	var chosen: Dictionary = result["chosen"]
	assert_gt(int(chosen.get(&"stove", 0)), 0, "the cook eats at the stove")
	assert_gt(int(chosen.get(&"bed", 0)), 0, "and sleeps in the bed")
	assert_gt(int(result["thoughts"]), 0, "a meal leaves a thought")
	var again: Dictionary = (script.new() as RefCounted).call(&"run", 2)
	assert_eq(again, result, "the same every time")


func test_the_module_guide_names_only_real_modules_and_guides() -> void:
	_check_names(GUIDE)
	var text := FileAccess.get_file_as_string(GUIDE)
	for module: String in DirAccess.get_directories_at("res://addons/bustle/modules"):
		assert_true(text.contains("`%s/`" % module), "the guide lists %s" % module)
