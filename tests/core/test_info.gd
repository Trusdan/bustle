# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The addon's version and folders.

const ADDON := "res://addons/bustle"


func test_the_version_is_the_same_in_all_three_places() -> void:
	var file := FileAccess.get_file_as_string(ADDON.path_join("VERSION")).strip_edges()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(ADDON.path_join("plugin.cfg")), OK)
	assert_eq(file, BustleInfo.VERSION, "VERSION")
	assert_eq(str(cfg.get_value("plugin", "version")), BustleInfo.VERSION, "plugin.cfg")
	assert_eq(BustleInfo.version_parts(), PackedInt32Array([0, 2, 1]))


func test_every_folder_exists_and_is_described() -> void:
	for folder: String in BustleInfo.FOLDERS:
		assert_true(DirAccess.dir_exists_absolute(ADDON.path_join(folder)), folder)
		assert_true(FileAccess.file_exists(ADDON.path_join(folder).path_join("README.md")), "%s has a README" % folder)
		assert_false(String(BustleInfo.FOLDERS[folder]).is_empty())
