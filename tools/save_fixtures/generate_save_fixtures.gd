# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## Writes the golden save fixtures of the release it runs on (docs/saves.md). Run by
## [code]tools/save_fixtures.sh[/code] inside a checkout of a tag, never by hand:
## [codeblock]
## godot --headless --path <checkout> -s res://tools/save_fixtures/generate_save_fixtures.gd -- \
##     --out=<dir> --tag=<tag> --commit=<sha>
## [/codeblock]
## For each saved class the release has, it builds the class with state (save_builder.gd) and
## writes [code]<Class>.txt[/code], its [code]export_state()[/code] as [method @GlobalScope.var_to_str]
## text, so every value keeps its exact Godot type. [code]index.json[/code] lists the tag, commit,
## Godot version and files. Deterministic: two runs on one tag write the same bytes.

const Builder := preload("res://tools/save_fixtures/save_builder.gd")


func _init() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.get_slice("=", 0).trim_prefix("--")] = arg.get_slice("=", 1)
	if not args.has("out") or not args.has("tag") or not args.has("commit"):
		printerr("usage: -- --out=<dir> --tag=<tag> --commit=<sha>")
		quit(2)
		return
	var builder := Builder.new()
	var files: Array = []
	for name: StringName in Builder.FORMATS:
		if not builder.has(name):
			continue
		var file := String(name) + ".txt"
		var out := FileAccess.open(String(args["out"]).path_join(file), FileAccess.WRITE)
		out.store_string(var_to_str(builder.populated(name).export_state()) + "\n")
		out.close()
		files.append(file)
	var version: Dictionary = Engine.get_version_info()
	var index := {"tag": args["tag"], "commit": args["commit"], "files": files,
		"godot": "%d.%d.%d-%s" % [version["major"], version["minor"], version["patch"], version["status"]]}
	var out := FileAccess.open(String(args["out"]).path_join("index.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(index, "\t", true) + "\n")
	out.close()
	print("wrote %d fixtures for %s" % [files.size(), args["tag"]])
	quit(0)
