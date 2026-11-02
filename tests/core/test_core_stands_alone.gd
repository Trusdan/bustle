# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The core addon depends only on Godot: no file in addons/bustle/ refers to another addon, the
## optional bridge, the demo or the tests.

const ADDON := "res://addons/bustle"
const BANNED := ["res://addons/wyrd", "res://addons/bustle_wyrd", "res://addons/gut", "res://demo", "res://tests", "BustleWyrdBridge", "Wyrd"]


func test_core_files_refer_to_nothing_outside_the_addon() -> void:
	var files := _files(ADDON)
	assert_gt(files.size(), 3)
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for term: String in BANNED:
			assert_false(text.contains(term), "%s mentions %s" % [path, term])


func _files(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd") or file.ends_with(".md") or file.ends_with(".cfg") or file.ends_with(".tscn"):
			out.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		out.append_array(_files(folder.path_join(sub)))
	return out
