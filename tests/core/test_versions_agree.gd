# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Every place a release's version lives agrees: the addon's VERSION, plugin.cfg and
## BustleInfo.VERSION, and, when the optional bridge is present, its VERSION and plugin.cfg. The
## release zips are named from this one version.

const ADDON := "res://addons/bustle"
const BRIDGE := "res://addons/bustle_wyrd"


static func _cfg_version(folder: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(folder.path_join("plugin.cfg")) != OK:
		return "<no plugin.cfg>"
	return str(cfg.get_value("plugin", "version", "<no version>"))


func test_every_version_source_agrees() -> void:
	var version := BustleInfo.VERSION
	assert_true(RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$").search(version) != null, "a plain x.y.z version")
	var sources := {
		"addons/bustle/VERSION": FileAccess.get_file_as_string(ADDON.path_join("VERSION")).strip_edges(),
		"addons/bustle/plugin.cfg": _cfg_version(ADDON),
	}
	if DirAccess.dir_exists_absolute(BRIDGE):
		sources["addons/bustle_wyrd/VERSION"] = FileAccess.get_file_as_string(BRIDGE.path_join("VERSION")).strip_edges()
		sources["addons/bustle_wyrd/plugin.cfg"] = _cfg_version(BRIDGE)
	for source: String in sources:
		assert_eq(sources[source], version, "%s agrees with BustleInfo.VERSION" % source)
