# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The optional Wyrd bridge sees the pinned test-only Wyrd. CI deletes this folder, the bridge
## and the vendored Wyrd in its core-only job.

const BRIDGE := "res://addons/bustle_wyrd"


func test_the_bridge_sees_the_pinned_wyrd() -> void:
	assert_eq(BustleWyrdBridge.installed_wyrd_version(), BustleWyrdBridge.WYRD_VERSION)
	assert_true(BustleWyrdBridge.is_supported())


func test_the_bridge_version_matches_its_plugin_cfg() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(BRIDGE.path_join("plugin.cfg")), OK)
	assert_eq(str(cfg.get_value("plugin", "version")), FileAccess.get_file_as_string(BRIDGE.path_join("VERSION")).strip_edges())
