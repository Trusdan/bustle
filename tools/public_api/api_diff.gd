# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## Compares two public API manifests under the rules in docs/public-api/VERSIONING.md.
##
## Every frozen symbol of the baseline must still be frozen, with the same signature, in the
## current manifest. A removed, renamed or changed symbol is breaking unless deprecations.json has
## an entry for it (or for its class). A covered removal (removed, renamed, or moved back to
## [code]@experimental[/code]) also has to come in a major release after the minor release that
## deprecated it: see [method removal_problem]. New symbols never fail. A raised save version
## ([code]STATE_VERSION[/code]) is a save-format change and is reported, not failed: the policy
## requires [code]import_state()[/code] to migrate the older shape.

const ApiManifest := preload("res://tools/public_api/api_manifest.gd")
const SAVE_VERSION: String = "STATE_VERSION"


## The comparison: [code]breaking[/code] (fails the check), [code]deprecated[/code] (breaking
## changes covered by a deprecation entry), [code]added[/code], [code]notes[/code] and
## [code]errors[/code] (a malformed deprecations file, which also fails). Each is a sorted list of
## lines. The current release is [param current]'s [code]version[/code] field, which
## [code]tools/public_api.sh[/code] sets from [code]addons/bustle/VERSION[/code].
static func compare(baseline: Dictionary, current: Dictionary, deprecations: Variant) -> Dictionary:
	var result: Dictionary = {"breaking": [], "deprecated": [], "added": [], "notes": [],
		"errors": validate_deprecations(deprecations)}
	var covered: Dictionary = {}
	if (result["errors"] as Array).is_empty() and deprecations is Dictionary:
		for entry: Dictionary in (deprecations as Dictionary).get("deprecations", []):
			covered[str(entry["symbol"])] = entry
	var present: Array = current.get("addons", [])
	var old: Dictionary = ApiManifest.flatten(baseline)
	var new: Dictionary = ApiManifest.flatten(current)
	var old_frozen: Dictionary = baseline.get("frozen", {})
	var skipped: Dictionary = {}
	var removed_classes: Dictionary = {}
	for symbol: String in old:
		var owner: String = symbol.get_slice(".", 0)
		var addon: String = str((old_frozen.get(owner, {}) as Dictionary).get("addon", ""))
		if not present.is_empty() and not present.has(addon):
			skipped[addon] = true
			continue
		if removed_classes.has(owner):
			continue
		var problem: String = ""
		if not new.has(symbol):
			problem = _gone(symbol, current)
			if symbol == owner:
				removed_classes[owner] = true
		elif new[symbol] != old[symbol]:
			if symbol.ends_with("." + SAVE_VERSION) and _version_of(new[symbol]) > _version_of(old[symbol]):
				(result["notes"] as Array).append("%s: save format raised (%s -> %s); import_state() must still read the older shape" % [
					symbol, old[symbol], new[symbol]])
				continue
			problem = "%s: signature changed\n    was: %s\n    now: %s" % [symbol, old[symbol], new[symbol]]
		if problem == "":
			continue
		var entry: Variant = covered.get(symbol, covered.get(owner, null))
		var too_early: String = ""
		if entry != null and not new.has(symbol):
			var how: String = "no longer frozen" if problem.ends_with("(now @experimental)") else "removed"
			too_early = removal_problem(symbol, str((entry as Dictionary)["since"]), str(current.get("version", "")), how)
		if entry != null and too_early == "":
			(result["deprecated"] as Array).append("%s (deprecated in %s)" % [problem, (entry as Dictionary)["since"]])
		elif too_early != "":
			(result["breaking"] as Array).append(too_early)
		else:
			(result["breaking"] as Array).append(problem)
	for symbol: String in new:
		if not old.has(symbol):
			(result["added"] as Array).append("%s: %s" % [symbol, new[symbol]])
	for addon: String in skipped:
		(result["notes"] as Array).append("%s is not in this checkout; its symbols were not compared" % addon)
	for key: String in result:
		(result[key] as Array).sort()
	return result


## Why a covered removal of [param symbol] can't happen yet, as one line, or [code]""[/code] when it
## can. It can when [param version] (the current release) has a higher major than [param since]
## (the release that deprecated it), and [param since] is a minor release ([code]MINOR >= 1[/code]),
## so the warning shipped in at least one minor release first. A [param since] of
## [code]X.0.0[/code] was a major release with no minor after it, so it never can. [param how] is
## [code]"removed"[/code] or [code]"no longer frozen"[/code].
static func removal_problem(symbol: String, since: String, version: String, how: String = "removed") -> String:
	var was: PackedInt32Array = _semver(since)
	var now: PackedInt32Array = _semver(version)
	if now.is_empty():
		return "%s: %s, but the current version (\"%s\") isn't x.y.z, so the removal can't be checked (since %s)" % [symbol, how, version, since]
	if was[1] < 1:
		return "%s: %s in %s; it was deprecated in a major release, so its warning never shipped in a minor release (since %s)" % [symbol, how, version, since]
	if now[0] <= was[0]:
		return "%s: %s in %s; removals need a major release after the minor that deprecated it (since %s)" % [symbol, how, version, since]
	return ""


## True when the comparison found nothing that fails the check.
static func passes(result: Dictionary) -> bool:
	return (result["breaking"] as Array).is_empty() and (result["errors"] as Array).is_empty()


## Problems with a deprecations file's contents, or none. It is
## [code]{"format": 1, "deprecations": [{"symbol": ..., "since": "x.y.z", ...}]}[/code]; each
## symbol is a class ([code]BustleX[/code]) or a member ([code]BustleX.name[/code]) and appears once.
static func validate_deprecations(data: Variant) -> Array:
	var errors: Array = []
	if data == null:
		return errors
	if not data is Dictionary or not (data as Dictionary).get("deprecations", null) is Array:
		return ["deprecations.json must be an object with a \"deprecations\" array"]
	var symbol_pattern := RegEx.create_from_string("^Bustle\\w+(\\.\\w+)?$")
	var version_pattern := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	var seen: Dictionary = {}
	for index: int in (data["deprecations"] as Array).size():
		var entry: Variant = data["deprecations"][index]
		if not entry is Dictionary:
			errors.append("deprecations[%d] is not an object" % index)
			continue
		var symbol: String = str((entry as Dictionary).get("symbol", ""))
		if symbol_pattern.search(symbol) == null:
			errors.append("deprecations[%d]: \"symbol\" must be BustleClass or BustleClass.member" % index)
		elif seen.has(symbol):
			errors.append("deprecations[%d]: %s is listed twice" % [index, symbol])
		seen[symbol] = true
		if version_pattern.search(str((entry as Dictionary).get("since", ""))) == null:
			errors.append("deprecations[%d]: \"since\" must be a version such as 1.2.0" % index)
	return errors


## Every comparison line, ready to print: breaking first.
static func report(result: Dictionary, label: String) -> String:
	var out: PackedStringArray = []
	var sections: Array = [["errors", "Deprecations file errors"], ["breaking", "Breaking changes that fail the check"],
		["deprecated", "Breaking changes covered by deprecations.json"], ["notes", "Notes"], ["added", "New public symbols"]]
	for section: Array in sections:
		var lines: Array = result[section[0]]
		if lines.is_empty():
			continue
		out.append("%s, against %s (%d):" % [section[1], label, lines.size()])
		for line: String in lines:
			out.append("  " + line)
	if out.is_empty():
		out.append("No changes to the public API against %s." % label)
	return "\n".join(out)


static func _gone(symbol: String, current: Dictionary) -> String:
	if (current.get("experimental", {}) as Dictionary).has(symbol) \
			or (current.get("experimental_members", {}) as Dictionary).has(symbol):
		return "%s: no longer frozen (now @experimental)" % symbol
	return "%s: removed or renamed" % symbol


static func _version_of(text: String) -> int:
	var found := RegEx.create_from_string("=\\s*(\\d+)").search(text)
	return int(found.get_string(1)) if found != null else -1


static func _semver(text: String) -> PackedInt32Array:
	var found := RegEx.create_from_string("^(\\d+)\\.(\\d+)\\.(\\d+)$").search(text.strip_edges())
	if found == null:
		return PackedInt32Array()
	return PackedInt32Array([int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))])
