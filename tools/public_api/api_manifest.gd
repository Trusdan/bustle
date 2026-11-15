# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## Builds the public API manifest from Godot's doctool XML, renders it as PUBLIC_API.md, and flattens
## it into one entry per symbol for [code]api_diff.gd[/code]. Used by [code]tools/public_api.sh[/code].
##
## A class is frozen unless its class doc carries [code]@experimental[/code]. In a frozen class, a
## member tagged [code]@experimental[/code] is left out of the frozen surface. Names starting with
## [code]_[/code] and scripts without a [code]class_name[/code] are internal and never listed.

const FORMAT: int = 1
const SAVE_CALLS: Array[String] = ["export_state", "import_state"]
const PORTS_DIR: String = "addons/bustle/ports/"


## Reads one doctool XML file into a class record: name, inherits, experimental reason (null when
## not experimental), brief, and its public members by kind.
static func parse_class(path: String) -> Dictionary:
	var record: Dictionary = {"name": "", "inherits": "", "experimental": null, "deprecated": null, "brief": "",
		"method": [], "signal": [], "constant": [], "member": []}
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		return record
	var item: Dictionary = {}
	var text_target: String = ""
	while xml.read() == OK:
		var node: String = xml.get_node_name()
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				match node:
					"class":
						record["name"] = xml.get_named_attribute_value_safe("name")
						record["inherits"] = xml.get_named_attribute_value_safe("inherits")
						record["experimental"] = _flag(xml, "experimental")
						record["deprecated"] = _flag(xml, "deprecated")
					"method", "signal", "constant", "member":
						item = {"kind": node, "name": xml.get_named_attribute_value_safe("name"), "params": [],
							"type": xml.get_named_attribute_value_safe("type"),
							"value": xml.get_named_attribute_value_safe("value"),
							"enum": xml.get_named_attribute_value_safe("enum"), "return": "void", "text": "",
							"qualifiers": xml.get_named_attribute_value_safe("qualifiers"),
							"experimental": _flag(xml, "experimental"), "deprecated": _flag(xml, "deprecated")}
						if node == "member" or node == "constant":
							text_target = "text"
					"return":
						item["return"] = xml.get_named_attribute_value_safe("type")
					"param":
						var param: String = "%s: %s" % [xml.get_named_attribute_value_safe("name"),
							xml.get_named_attribute_value_safe("type")]
						if xml.has_attribute("default"):
							param += " = " + xml.get_named_attribute_value("default")
						(item["params"] as Array).append(param)
					"brief_description":
						text_target = "brief"
					"description":
						text_target = "text" if not item.is_empty() else ""
			XMLParser.NODE_TEXT:
				var text: String = _clean(xml.get_node_data())
				if text == "" or text_target == "":
					continue
				if text_target == "text":
					item["text"] = text
				else:
					record[text_target] = text
			XMLParser.NODE_ELEMENT_END:
				if node in ["method", "signal", "constant", "member"]:
					if not str(item.get("name", "_")).begins_with("_"):
						(record[node] as Array).append(item)
					item = {}
				if node in ["brief_description", "description", "member", "constant"]:
					text_target = ""
	return record


## Builds the manifest from parsed class records. [param paths] maps each class name to its script
## path ([code]res://[/code] prefix optional); classes without a path are skipped. [param addons]
## lists the addon folders the records came from.
static func build(records: Array[Dictionary], paths: Dictionary, version: String, addons: Array[String]) -> Dictionary:
	var frozen: Dictionary = {}
	var experimental: Dictionary = {}
	var experimental_members: Dictionary = {}
	var deprecated: Dictionary = {}
	for record: Dictionary in records:
		var name: String = record["name"]
		if not paths.has(name):
			continue
		var path: String = str(paths[name]).trim_prefix("res://")
		var base: Dictionary = {"addon": path.get_slice("/", 1), "path": path, "kind": _kind(name, path),
			"extends": record["inherits"], "purpose": purpose(record["brief"])}
		if record["experimental"] != null:
			base["reason"] = _reason(record["experimental"])
			experimental[name] = base
			continue
		if record["deprecated"] != null:
			deprecated[name] = _reason(record["deprecated"])
		var methods: Dictionary = {}
		var properties: Dictionary = {}
		var hooks: Dictionary = {}
		var signals: Dictionary = {}
		var constants: Dictionary = {}
		var save: Dictionary = {}
		for kind: String in ["method", "signal", "constant", "member"]:
			for item: Dictionary in record[kind]:
				var symbol: String = "%s.%s" % [name, item["name"]]
				if item["experimental"] != null:
					experimental_members[symbol] = _reason(item["experimental"])
					continue
				if item["deprecated"] != null:
					deprecated[symbol] = _reason(item["deprecated"])
				match kind:
					"method":
						methods[item["name"]] = signature(item)
						if SAVE_CALLS.has(item["name"]):
							save[item["name"]] = purpose(item["text"])
					"signal":
						signals[item["name"]] = {"signature": signature(item), "purpose": purpose(item["text"])}
					"constant":
						constants[item["name"]] = signature(item)
					"member":
						if item["type"] == "Callable":
							hooks[item["name"]] = {"signature": signature(item), "purpose": purpose(item["text"])}
						else:
							properties[item["name"]] = signature(item)
		base.merge({"methods": methods, "properties": properties, "hooks": hooks, "signals": signals,
			"constants": constants, "save": save})
		frozen[name] = base
	var sorted_addons: Array[String] = addons.duplicate()
	sorted_addons.sort()
	return {"format": FORMAT, "version": version, "addons": sorted_addons, "frozen": frozen,
		"experimental": experimental, "experimental_members": experimental_members, "deprecated": deprecated}


## One symbol per entry: [code]BustleX[/code] for a frozen class, [code]BustleX.name[/code] for each
## frozen member, mapped to its signature. Two manifests with the same frozen surface flatten alike.
static func flatten(manifest: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var frozen: Dictionary = manifest.get("frozen", {})
	for name: String in frozen:
		var entry: Dictionary = frozen[name]
		out[name] = "%s %s extends %s" % [entry.get("kind", "class"), name, entry.get("extends", "")]
		for group: String in ["methods", "properties", "constants"]:
			var members: Dictionary = entry.get(group, {})
			for member: String in members:
				out["%s.%s" % [name, member]] = str(members[member])
		for group: String in ["hooks", "signals"]:
			var members: Dictionary = entry.get(group, {})
			for member: String in members:
				out["%s.%s" % [name, member]] = str((members[member] as Dictionary).get("signature", ""))
	return out


## How many of each kind of entry the manifest freezes.
static func totals(manifest: Dictionary) -> Dictionary:
	var counts: Dictionary = {"classes": 0, "ports": 0, "methods": 0, "properties": 0, "hooks": 0, "signals": 0,
		"constants": 0, "save_calls": 0, "experimental_classes": 0, "experimental_members": 0}
	var frozen: Dictionary = manifest.get("frozen", {})
	for name: String in frozen:
		var entry: Dictionary = frozen[name]
		counts["ports" if entry["kind"] == "port" else "classes"] += 1
		for group: String in ["methods", "properties", "hooks", "signals", "constants"]:
			counts[group] += (entry.get(group, {}) as Dictionary).size()
		counts["save_calls"] += (entry.get("save", {}) as Dictionary).size()
	counts["experimental_classes"] = (manifest.get("experimental", {}) as Dictionary).size()
	counts["experimental_members"] = (manifest.get("experimental_members", {}) as Dictionary).size()
	return counts


## PUBLIC_API.md for a manifest. The page is generated: the doc and the manifest always agree.
static func render(manifest: Dictionary) -> String:
	var frozen: Dictionary = manifest.get("frozen", {})
	var names: Array = frozen.keys()
	names.sort()
	var t: Dictionary = totals(manifest)
	var lines: PackedStringArray = [
		"# Bustle public API",
		"",
		"Generated by `tools/public_api.sh --write` from [`public_api.json`](public_api.json). Do not edit by hand.",
		"The rules for changing anything listed here are in [VERSIONING.md](VERSIONING.md).",
		"",
		"Version %s. Frozen: %d classes, %d ports, %d Callable hooks, %d signals and %d save-state calls, with %d methods, %d properties and %d constants between them." % [
			manifest.get("version", ""), t["classes"], t["ports"], t["hooks"], t["signals"], t["save_calls"],
			t["methods"], t["properties"], t["constants"]],
		"",
		"## What is public",
		"",
		"Everything in the tables below is the frozen public API. For a frozen class that means its name, base class and every public method, property, Callable hook, signal and constant it declares, as listed per symbol in `public_api.json`, except members listed under \"Experimental members\".",
		"",
		"**Everything else is internal**, and may change in any release:",
		"",
		"- names that start with `_`;",
		"- scripts without a `class_name` (such as each addon's `plugin.gd`);",
		"- classes and members whose doc comment carries `@experimental` (listed at the end, with the reason for each);",
		"- the demos, tests and tools, which are not part of either addon.",
		"",
		"Behaviour and tuning defaults are documented in the guides; the frozen surface fixes names and signatures, not numbers.",
	]
	lines.append_array(_table("Classes", ["Class", "File", "Purpose"], names.filter(
		func(n: String) -> bool: return frozen[n]["kind"] == "class"), func(n: String) -> Array:
			return ["`%s`" % n, "`%s`" % frozen[n]["path"], frozen[n]["purpose"]]))
	lines.append_array(_table("Ports", ["Port", "File", "Purpose"], names.filter(
		func(n: String) -> bool: return frozen[n]["kind"] == "port"), func(n: String) -> Array:
			return ["`%s`" % n, "`%s`" % frozen[n]["path"], frozen[n]["purpose"]]))
	lines.append_array(_member_table(frozen, names, "hooks", "Callable hooks", "Hook",
		"A hook is a public `Callable` property the host may set; its doc comment gives the call it expects."))
	lines.append_array(_member_table(frozen, names, "signals", "Signals", "Signal", ""))
	var save_rows: Array = []
	for n: String in names:
		var save: Dictionary = frozen[n]["save"]
		for call: String in SAVE_CALLS:
			if save.has(call):
				save_rows.append(["`%s.%s()`" % [n, call], "`%s`" % frozen[n]["path"], save[call]])
	lines.append_array(_rows("Save-state calls", ["Call", "File", "Purpose"], save_rows,
		"What `export_state()` returns is a save format: changing it without `import_state()` migrating the older shape is a breaking change."))
	var experimental: Dictionary = manifest.get("experimental", {})
	var exp_names: Array = experimental.keys()
	exp_names.sort()
	var exp_rows: Array = []
	for n: String in exp_names:
		exp_rows.append(["`%s`" % n, "`%s`" % experimental[n]["path"], _cell(experimental[n]["reason"])])
	lines.append_array(_rows("Experimental classes", ["Class", "File", "Why it stays experimental"], exp_rows,
		"Usable, but not frozen: they may change in any minor release."))
	var members: Dictionary = manifest.get("experimental_members", {})
	var member_names: Array = members.keys()
	member_names.sort()
	var member_rows: Array = []
	for symbol: String in member_names:
		member_rows.append(["`%s`" % symbol, _cell(members[symbol])])
	lines.append_array(_rows("Experimental members", ["Member", "Why it stays experimental"], member_rows,
		"Members of frozen classes that are not frozen yet."))
	var deprecated: Dictionary = manifest.get("deprecated", {})
	var dep_names: Array = deprecated.keys()
	dep_names.sort()
	var dep_rows: Array = []
	for symbol: String in dep_names:
		dep_rows.append(["`%s`" % symbol, _cell(deprecated[symbol])])
	lines.append_array(_rows("Deprecated", ["Symbol", "Note"], dep_rows,
		"Still frozen until the next major release; see [deprecations.json](deprecations.json)."))
	return "\n".join(lines) + "\n"


## The first sentence of a doc text, as one Markdown table cell.
static func purpose(text: String) -> String:
	var flat: String = text.replace("\n", " ").strip_edges()
	var cut: int = flat.find(". ")
	if cut >= 0:
		flat = flat.substr(0, cut + 1)
	return _cell(_md(flat))


## A member's signature as Godot's docs print it.
static func signature(item: Dictionary) -> String:
	match item["kind"]:
		"method":
			var prefix: String = "static " if str(item["qualifiers"]).contains("static") else ""
			return "%sfunc %s(%s) -> %s" % [prefix, item["name"], ", ".join(item["params"]), item["return"]]
		"signal":
			return "signal %s(%s)" % [item["name"], ", ".join(item["params"])]
		"constant":
			var in_enum: String = " (enum %s)" % item["enum"] if str(item["enum"]) != "" else ""
			return "const %s = %s%s" % [item["name"], item["value"], in_enum]
	return "var %s: %s" % [item["name"], item["type"]]


static func _flag(xml: XMLParser, attribute: String) -> Variant:
	return xml.get_named_attribute_value(attribute) if xml.has_attribute(attribute) else null


static func _reason(value: Variant) -> String:
	var text: String = str(value).strip_edges()
	return _md(text) if text != "" else "(no reason given)"


static func _kind(name: String, path: String) -> String:
	if name.ends_with("Port") and (path.begins_with(PORTS_DIR) or path.begins_with("addons/bustle_wyrd/")):
		return "port"
	return "class"


static func _table(title: String, header: Array, names: Array, row: Callable) -> PackedStringArray:
	var rows: Array = []
	for n: String in names:
		rows.append(row.call(n))
	return _rows(title, header, rows, "")


static func _member_table(frozen: Dictionary, names: Array, group: String, title: String, label: String,
		note: String) -> PackedStringArray:
	var rows: Array = []
	for n: String in names:
		var members: Dictionary = frozen[n][group]
		var keys: Array = members.keys()
		keys.sort()
		for member: String in keys:
			var entry: Dictionary = members[member]
			var shown: String = str(entry["signature"]).trim_prefix("signal ") if group == "signals" else member
			rows.append(["`%s.%s`" % [n, shown], "`%s`" % frozen[n]["path"], entry["purpose"]])
	return _rows(title, [label, "File", "Purpose"], rows, note)


static func _rows(title: String, header: Array, rows: Array, note: String) -> PackedStringArray:
	var out: PackedStringArray = ["", "## %s (%d)" % [title, rows.size()], ""]
	if note != "":
		out.append_array([note, ""])
	if rows.is_empty():
		out.append("None.")
		return out
	out.append("| %s |" % " | ".join(header))
	out.append("|%s" % " --- |".repeat(header.size()))
	for row: Array in rows:
		out.append("| %s |" % " | ".join(row))
	return out


static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("\n", " ").strip_edges()


static func _clean(text: String) -> String:
	var lines: PackedStringArray = []
	for line: String in text.split("\n"):
		lines.append(line.strip_edges())
	return "\n".join(lines).strip_edges()


static func _md(text: String) -> String:
	var out: String = text.replace("[b]", "**").replace("[/b]", "**").replace("[i]", "*").replace("[/i]", "*")
	out = out.replace("[br]", " ")
	out = RegEx.create_from_string("\\[code\\]([\\s\\S]*?)\\[/code\\]").sub(out, "`$1`", true)
	out = RegEx.create_from_string("\\[method ([\\w.]+)\\]").sub(out, "`$1()`", true)
	out = RegEx.create_from_string("\\[(?:param|member|constant|signal|enum) ([\\w.]+)\\]").sub(out, "`$1`", true)
	out = RegEx.create_from_string("\\[([A-Z]\\w*)\\]").sub(out, "`$1`", true)
	return out
