# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The host guides stay true: the port guide has a section for every port and names every method
## and signal of it, every snippet compiles, every port example plugs into a society, the
## walkthrough runs and says what the page says, and every page names only real classes and paths.

const PORTS := "res://docs/ports.md"
const WALKTHROUGH := "res://docs/host-walkthrough.md"
const UPGRADING := "res://docs/upgrading.md"
const PORT_DIR := "res://addons/bustle/ports"


static func _matches(text: String, pattern: String) -> Array[String]:
	var out: Array[String] = []
	for found: RegExMatch in RegEx.create_from_string(pattern).search_all(text):
		if not out.has(found.get_string(1)):
			out.append(found.get_string(1))
	return out


static func _blocks(path: String) -> Array[String]:
	var out: Array[String] = []
	for found: RegExMatch in RegEx.create_from_string("(?s)```gdscript\\n(.*?)```").search_all(FileAccess.get_file_as_string(path)):
		out.append(found.get_string(1))
	return out


static func _compile(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source if source.begins_with("extends ") else "extends RefCounted\n\n" + source
	return script if script.reload() == OK else null


## The port classes in the ports folder, by class name, each with its own public methods and signals.
static func _port_classes() -> Dictionary[String, PackedStringArray]:
	var out: Dictionary[String, PackedStringArray] = {}
	for file: String in DirAccess.get_files_at(PORT_DIR):
		if file.get_extension() != "gd":
			continue
		var source := FileAccess.get_file_as_string(PORT_DIR.path_join(file))
		var name := RegEx.create_from_string("(?m)^class_name (\\w+)").search(source).get_string(1)
		var members := PackedStringArray()
		for member: String in _matches(source, "(?m)^(?:static )?func ([a-z]\\w*)\\("):
			members.append(member)
		for member: String in _matches(source, "(?m)^signal ([a-z]\\w*)\\("):
			members.append(member)
		out[name] = members
	return out


func test_every_page_names_only_real_classes_and_paths() -> void:
	var classes: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes.append(String(entry["class"]))
	for path: String in [PORTS, WALKTHROUGH, UPGRADING]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", path)
		for name: String in _matches(text, "\\b(Bustle[A-Z][A-Za-z]*)\\b"):
			assert_true(classes.has(name), "%s: class %s exists" % [path, name])
		for named: String in _matches(text, "`((?:addons|demo|docs|tests|tools)/[A-Za-z0-9_./]+?)`"):
			var target := "res://" + named
			assert_true(FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target), "%s: %s exists" % [path, named])
		for link: String in _matches(text, "\\]\\(([a-z][\\w./-]*\\.md)(?:#[\\w-]+)?\\)"):
			assert_true(FileAccess.file_exists("res://docs".path_join(link)), "%s: link %s exists" % [path, link])


func test_the_port_guide_covers_every_port_and_member() -> void:
	var text := FileAccess.get_file_as_string(PORTS)
	var ports := _port_classes()
	assert_gt(ports.size(), 15, "the ports folder has its classes")
	for name: String in ports:
		var heading := RegEx.create_from_string("\\n## [^\\n]*\\b%s\\b" % name).search(text)
		assert_not_null(heading, "a section for %s" % name)
		if heading == null:
			continue
		var start := heading.get_start()
		var end := text.find("\n## ", start + 4)
		var section := text.substr(start, (end if end != -1 else text.length()) - start)
		for member: String in ports[name]:
			assert_true(section.contains("`%s(" % member) or section.contains("`%s`" % member)
					or section.contains("signal `%s" % member), "%s's section names %s" % [name, member])


func test_every_snippet_compiles_and_every_port_example_plugs_in() -> void:
	var plugged := 0
	for path: String in [PORTS, WALKTHROUGH]:
		var blocks := _blocks(path)
		assert_gt(blocks.size(), 2, "%s has snippets" % path)
		for block: String in blocks:
			var script := _compile(block)
			assert_not_null(script, "%s: compiles:\n%s" % [path, block.left(120)])
			if script == null or not block.begins_with("extends Bustle"):
				continue
			var society := BustleSociety.new()
			var port: RefCounted = script.new()
			var name := ""
			for candidate: String in BustlePorts.NAMES:
				if is_instance_of(port, (society.ports.get(candidate) as RefCounted).get_script()):
					name = candidate
			assert_true(society.set_port(StringName(name), port), "%s: plugs in as %s" % [block.left(40), name])
			plugged += 1
	assert_eq(plugged, 14, "one example for each port in BustlePorts")


func test_the_walkthrough_runs_as_the_page_says() -> void:
	var blocks := _blocks(WALKTHROUGH)
	var village_source := ""
	var runner_source := ""
	for block: String in blocks:
		if block.contains("func setup()"):
			village_source = block
		elif block.contains("func run("):
			runner_source = block
	var village: RefCounted = _compile(village_source).new()
	var runner: RefCounted = _compile(runner_source).new()
	var report: Dictionary = runner.call(&"run", village)
	assert_eq(report, {
		&"ann": {"ring": "FULL", "job": &"baker", "doing": &"bake"},
		&"bram": {"ring": "LIGHT", "job": &"smith", "doing": &"forge"},
		&"cora": {"ring": "OFF_SCREEN", "job": &"", "doing": &""},
	}, "at 10:00 on day one")
	var society: BustleSociety = village.get(&"society")
	society.ports.roles.set_holder(&"baker", &"cora")
	var after: Dictionary = village.call(&"report")
	assert_eq([after[&"cora"]["job"], after[&"cora"]["doing"]], [&"baker", &"bake"], "cora takes the bakery")
	assert_eq(after[&"ann"]["job"], &"", "and ann has none")
	assert_push_warning_count(0)
	assert_push_error_count(0)
