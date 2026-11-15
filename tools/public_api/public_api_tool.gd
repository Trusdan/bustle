# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The headless side of [code]tools/public_api.sh[/code]. After [code]--[/code]:
## [codeblock]
## build <out.json> <out.md> <version> <xml dir>...   manifest and page from doctool XML
## render <manifest.json> <out.md>                     the page for a manifest
## compare <baseline.json> <current.json> <deprecations.json> <label>
## [/codeblock]
## compare exits 1 on a breaking change without a deprecation entry, or a malformed
## deprecations file.

const ApiManifest := preload("res://tools/public_api/api_manifest.gd")
const ApiDiff := preload("res://tools/public_api/api_diff.gd")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var code: int = 2
	match args[0] if args.size() > 0 else "":
		"build":
			code = _build(args)
		"render":
			code = _render(args)
		"compare":
			code = _compare(args)
		_:
			printerr("usage: build | render | compare (see tools/public_api/public_api_tool.gd)")
	quit(code)


func _build(args: PackedStringArray) -> int:
	if args.size() < 5:
		printerr("build <out.json> <out.md> <version> <xml dir>...")
		return 2
	var paths: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		paths[String(entry["class"])] = String(entry["path"])
	var records: Array[Dictionary] = []
	var addons: Array[String] = []
	for index: int in range(4, args.size()):
		var dir: String = args[index]
		addons.append(dir.get_file())
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		for file: String in files:
			if file.ends_with(".xml") and not file.contains("--") and not file.get_basename().contains("."):
				records.append(ApiManifest.parse_class(dir.path_join(file)))
	var manifest: Dictionary = ApiManifest.build(records, paths, args[3], addons)
	if not _write(args[1], JSON.stringify(manifest, "\t", true) + "\n"):
		return 1
	return 0 if _write(args[2], ApiManifest.render(manifest)) else 1


func _render(args: PackedStringArray) -> int:
	if args.size() < 3:
		printerr("render <manifest.json> <out.md>")
		return 2
	var manifest: Variant = _read(args[1])
	if not manifest is Dictionary:
		return 1
	return 0 if _write(args[2], ApiManifest.render(manifest)) else 1


func _compare(args: PackedStringArray) -> int:
	if args.size() < 5:
		printerr("compare <baseline.json> <current.json> <deprecations.json> <label>")
		return 2
	var baseline: Variant = _read(args[1])
	var current: Variant = _read(args[2])
	if not baseline is Dictionary or not current is Dictionary:
		return 1
	var deprecations: Variant = _read(args[3]) if FileAccess.file_exists(args[3]) else null
	var result: Dictionary = ApiDiff.compare(baseline, current, deprecations)
	print(ApiDiff.report(result, args[4]))
	return 0 if ApiDiff.passes(result) else 1


func _read(path: String) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		printerr("%s is missing or not valid JSON" % path)
	return data


func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("can't write %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true
