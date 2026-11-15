# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSaveFormat
extends RefCounted

## Which save versions this version of Bustle reads, and why it refuses one. Every class with
## [code]export_state()[/code] has a save format named after the class, such as
## [code]&"BustleDirector"[/code]. Its version is the payload's [code]"version"[/code] (the
## society's is [code]"schema"[/code]). [method check] says whether a payload's version can be read,
## before or after [code]import_state()[/code] refuses it: an older version is migrated one step at
## a time to the current one, and a newer one is always refused, with a reason. A class that has
## never written a version reads a missing one as version 1. See [code]docs/saves.md[/code].

## The classes whose saves have never carried a version: a missing [code]"version"[/code] is 1.
const _UNVERSIONED: Array[StringName] = [&"BustleAffordance", &"BustleAffordanceSet", &"BustleAmbitions",
	&"BustleAspirations", &"BustleAwareness", &"BustleCareers", &"BustleConflict", &"BustleCrimeWatch",
	&"BustleDetectionMeter", &"BustleEnvironmentPort", &"BustleJobBoard", &"BustleLeisure", &"BustleMemory",
	&"BustleMentalBehaviour", &"BustleMentalState", &"BustleMood", &"BustleNeedSet", &"BustlePersonality",
	&"BustlePropertyPort", &"BustleRomance", &"BustleRoomThoughts", &"BustleSchedule", &"BustleScheduleRoster",
	&"BustleSequenceRunner", &"BustleSkills", &"BustleSocialInteractions", &"BustleSocialStore", &"BustleTradePort"]
## The classes with a version constant; each has a static [code]_save_format()[/code] next to its
## [code]import_state()[/code] giving its key, current version and steps.
const _VERSIONED: Array[StringName] = [&"BustleBrain", &"BustleDirector", &"BustleLifeStages", &"BustleSociety"]
const _UNVERSIONED_FORMAT: Dictionary = {"key": "version", "current": 1, "missing": 1, "steps": {}}

static var _formats: Dictionary = {}


## Whether this version of Bustle reads [param saved]'s version for [param format] (a class name
## such as [code]&"BustleDirector"[/code]). The report's [member BustleImportReport.schema] is the
## version the payload claims, or -1. On a refusal its errors give the reason: the version is newer
## than this version reads, there's no migration from it, or it's missing or not a whole number.
## Only the version is checked; [code]import_state()[/code] still checks the rest.
static func check(format: StringName, saved: Variant) -> BustleImportReport:
	var report := BustleImportReport.new()
	var info := _format(format)
	if info.is_empty():
		report.fail("%s has no save format" % format)
		return report
	var read := _read(format, saved, info)
	report.schema = read["version"]
	report.ok = read["ok"]
	if not report.ok:
		report.fail(read["reason"])
	return report


## The version of [param format] this version of Bustle writes, or -1 for a class with no save format.
static func current(format: StringName) -> int:
	var info := _format(format)
	return int(info["current"]) if not info.is_empty() else -1


## For the classes in [constant _UNVERSIONED]: false when [param saved] is a Dictionary whose
## [code]"version"[/code] is anything but 1. A Dictionary under that key is data (an id), not a version.
static func _readable(saved: Variant) -> bool:
	return not saved is Dictionary or _read(&"", saved, _UNVERSIONED_FORMAT)["ok"]


## Reads [param saved]'s version under [param info] ([code]key[/code], [code]current[/code],
## [code]steps[/code] from version N to N + 1, and optionally [code]missing[/code], the version a
## missing key means) and migrates a deep copy to the current version. Returns [code]ok[/code],
## [code]reason[/code], [code]version[/code] (as claimed, or -1) and [code]data[/code] (the
## migrated copy, or [param saved] itself when it's already current). Never mutates [param saved].
static func _read(label: StringName, saved: Variant, info: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "version": -1, "data": saved}
	if not saved is Dictionary:
		out["reason"] = "the payload isn't a dictionary"
		return out
	var key: String = info["key"]
	var what: String = key if key == "schema" else "%s %s" % [label, key] if label != &"" else key
	var raw: Variant = (saved as Dictionary).get(key)
	var version: int
	if raw == null or (key == "version" and raw is Dictionary):
		if int(info.get("missing", -1)) < 0:
			out["reason"] = "no %s" % ("schema version" if key == "schema" else what)
			return out
		version = int(info["missing"])
	else:
		var whole: Variant = _whole(raw)
		if whole == null:
			out["reason"] = "no schema version" if key == "schema" else "%s isn't a whole number" % what
			return out
		version = whole
	out["version"] = version
	var current_version: int = info["current"]
	if version > current_version:
		out["reason"] = "%s %d is newer than this version reads (%d)" % [what, version, current_version]
		return out
	var data: Dictionary = saved
	var steps: Dictionary = info["steps"]
	while version < current_version:
		if not steps.has(version):
			out["reason"] = "no migration from %s %d" % [what, version]
			return out
		data = (steps[version] as Callable).call(data.duplicate(true))
		version += 1
	out["ok"] = true
	out["data"] = data
	return out


static func _format(format: StringName) -> Dictionary:
	if _UNVERSIONED.has(format):
		return _UNVERSIONED_FORMAT
	if not _VERSIONED.has(format):
		return {}
	if not _formats.has(format):
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			if StringName(entry["class"]) == format:
				_formats[format] = (load(String(entry["path"])) as Script).call("_save_format")
	return _formats.get(format, {})


static func _whole(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value) and absf(value) < 1e9:
		return int(value) # JSON reads whole numbers back as floats
	return null
