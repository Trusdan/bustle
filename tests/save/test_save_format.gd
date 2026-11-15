# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Save versions (docs/saves.md): the step runner, BustleSaveFormat.check() and current(), and every
## exporter refusing a newer save without changing anything.

const VERSIONED := {&"BustleBrain": 1, &"BustleDirector": 1, &"BustleLifeStages": 2, &"BustleSociety": 1}


## Each exporter: a fresh instance, and how to import a payload into it.
static func _exporters() -> Dictionary:
	var plain := func(target: Object, saved: Dictionary) -> Variant: return target.import_state(saved)
	var traits: Array[BustleTraitDef] = []
	var thoughts: Array[BustleThoughtDef] = []
	return {
		&"BustleAffordance": [BustleAffordance.new(&"well"), plain],
		&"BustleAffordanceSet": [BustleAffordanceSet.new(), plain],
		&"BustleAmbitions": [BustleAmbitions.new(&"baker"), plain],
		&"BustleAspirations": [BustleAspirations.new(&"baker"), plain],
		&"BustleAwareness": [BustleAwareness.new(), func(t: Object, s: Dictionary) -> Variant: return t.import_state(s, null)],
		&"BustleBrain": [BustleBrain.new(&"baker"), plain],
		&"BustleCareers": [BustleCareers.new(), plain],
		&"BustleConflict": [BustleConflict.new(), plain],
		&"BustleCrimeWatch": [BustleCrimeWatch.new(), plain],
		&"BustleDetectionMeter": [BustleDetectionMeter.new(), plain],
		&"BustleDirector": [BustleDirector.new(), plain],
		&"BustleEnvironmentPort": [BustleEnvironmentPort.new(), plain],
		&"BustleJobBoard": [BustleJobBoard.new(), plain],
		&"BustleLeisure": [BustleLeisure.new(), plain],
		&"BustleLifeStages": [BustleLifeStages.new(BustleLifeStageRules.new()), plain],
		&"BustleMemory": [BustleMemory.new(), plain],
		&"BustleMentalBehaviour": [BustleMentalBehaviour.new(), plain],
		&"BustleMentalState": [BustleMentalState.new(&"baker"), plain],
		&"BustleMood": [BustleMood.new(), func(t: Object, s: Dictionary) -> Variant: return t.import_state(s, thoughts)],
		&"BustleNeedSet": [BustleNeedSet.new(), plain],
		&"BustlePersonality": [BustlePersonality.new(), func(t: Object, s: Dictionary) -> Variant: return t.import_state(s, traits)],
		&"BustlePropertyPort": [BustlePropertyPort.new(), plain],
		&"BustleRomance": [BustleRomance.new(), plain],
		&"BustleRoomThoughts": [BustleRoomThoughts.new(), plain],
		&"BustleSchedule": [BustleSchedule.new(), plain],
		&"BustleScheduleRoster": [BustleScheduleRoster.new(), plain],
		&"BustleSequenceRunner": [BustleSequenceRunner.new(), func(t: Object, s: Dictionary) -> Variant: return t.import_state(null, s)],
		&"BustleSkills": [BustleSkills.new(), plain],
		&"BustleSocialInteractions": [BustleSocialInteractions.new(), plain],
		&"BustleSocialStore": [BustleSocialStore.new(), plain],
		&"BustleSociety": [BustleSociety.new(7), plain],
		&"BustleTradePort": [BustleTradePort.new(), plain],
	}


static func _key(format: StringName) -> String:
	return "schema" if format == &"BustleSociety" else "version"


static func _read(saved: Variant, steps: Dictionary, current: int = 3) -> Dictionary:
	return BustleSaveFormat._read(&"Example", saved, {"key": "version", "current": current, "steps": steps})


static func _step(name: String) -> Callable:
	return func(data: Dictionary) -> Dictionary:
		(data["trail"] as Array).append(name)
		data["version"] = int(data["version"]) + 1
		return data


func test_there_are_32_exporters_and_each_has_a_format() -> void:
	assert_eq(_exporters().size(), 32)
	for format: StringName in _exporters():
		assert_eq(BustleSaveFormat.current(format), VERSIONED.get(format, 1), format)


func test_the_runner_applies_each_step_in_order_on_a_copy() -> void:
	var saved := {"version": 1, "trail": []}
	var read := _read(saved, {1: _step("1 to 2"), 2: _step("2 to 3")})
	assert_true(read["ok"])
	assert_eq(read["version"], 1, "the claimed version")
	assert_eq(read["data"], {"version": 3, "trail": ["1 to 2", "2 to 3"]})
	assert_eq(saved, {"version": 1, "trail": []}, "the input isn't mutated")


func test_the_runner_refuses_a_version_with_no_step() -> void:
	var saved := {"version": 1, "trail": []}
	var read := _read(saved, {2: _step("2 to 3")})
	assert_false(read["ok"])
	assert_eq(read["reason"], "no migration from Example version 1")
	assert_eq(saved, {"version": 1, "trail": []})


func test_the_runner_refuses_a_newer_or_a_missing_or_malformed_version() -> void:
	assert_eq(_read({"version": 4}, {})["reason"], "Example version 4 is newer than this version reads (3)")
	assert_eq(_read({}, {})["reason"], "no Example version")
	for bad: Variant in ["1", 1.5, true, [1], INF]:
		assert_eq(_read({"version": bad}, {})["reason"], "Example version isn't a whole number", str(bad))
	assert_eq(_read("nonsense", {})["reason"], "the payload isn't a dictionary")


func test_the_runner_counts_a_whole_float_as_its_integer() -> void:
	var read := _read({"version": 3.0}, {})
	assert_true(read["ok"], "JSON reads whole numbers back as floats")
	assert_eq(read["version"], 3)


func test_a_missing_version_is_1_for_an_unversioned_exporter_only() -> void:
	for format: StringName in _exporters():
		var report := BustleSaveFormat.check(format, {})
		assert_eq(report.ok, not VERSIONED.has(format), format)
		if VERSIONED.has(format):
			assert_eq(report.errors, PackedStringArray(["no schema version" if format == &"BustleSociety" else "no %s version" % format]))


func test_check_refuses_a_newer_version_for_every_exporter_and_names_both_versions() -> void:
	for format: StringName in _exporters():
		var current := BustleSaveFormat.current(format)
		var what := "schema" if format == &"BustleSociety" else "%s version" % format
		var report := BustleSaveFormat.check(format, {_key(format): current + 1})
		assert_false(report.ok, format)
		assert_eq(report.schema, current + 1, "%s: the claimed version" % format)
		assert_eq(report.errors, PackedStringArray(["%s %d is newer than this version reads (%d)" % [what, current + 1, current]]))
		assert_true(BustleSaveFormat.check(format, {_key(format): current}).ok, "%s reads its current version" % format)


func test_check_names_each_society_case() -> void:
	assert_eq(BustleSaveFormat.check(&"BustleSociety", {"schema": 0}).errors[0], "no migration from schema 0")
	assert_eq(BustleSaveFormat.check(&"BustleSociety", {"schema": "1"}).errors[0], "no schema version")
	assert_eq(BustleSaveFormat.check(&"BustleSociety", {"schema": 0}).schema, 0, "the claimed schema")


func test_check_refuses_an_unknown_format() -> void:
	assert_eq(BustleSaveFormat.check(&"BustleNoSuchThing", {}).errors[0], "BustleNoSuchThing has no save format")
	assert_eq(BustleSaveFormat.current(&"BustleNoSuchThing"), -1)


func test_a_dictionary_under_version_is_data_not_a_version() -> void:
	var careers := {"version": {"career": "bakery", "rank": "apprentice"}}
	assert_true(BustleSaveFormat.check(&"BustleCareers", careers).ok, "an agent whose id is \"version\"")
	assert_true(BustleSaveFormat._readable(careers))
	assert_false(BustleSaveFormat._readable({"version": 2}))
	assert_true(BustleSaveFormat._readable({"version": 1}))


func test_life_stages_reads_version_1_through_its_step() -> void:
	var saved := {"version": 1, "ages": {"baker": 30.0}, "stages": {"baker": "adult"}}
	var report := BustleSaveFormat.check(&"BustleLifeStages", saved)
	assert_true(report.ok)
	assert_eq(report.schema, 1)
	var read := BustleSaveFormat._read(&"BustleLifeStages", saved, BustleLifeStages._save_format())
	assert_eq(read["data"], {"version": 2, "now": 0, "ages": {"baker": 30.0}, "anchors": {"baker": [30.0, 0]},
		"stages": {"baker": "adult"}, "dead": {}})
	assert_eq(saved, {"version": 1, "ages": {"baker": 30.0}, "stages": {"baker": "adult"}}, "the input isn't mutated")
	assert_eq(BustleSaveFormat.check(&"BustleLifeStages", {"version": 0}).errors[0],
		"no migration from BustleLifeStages version 0")


func test_every_import_refuses_a_newer_save_and_changes_nothing() -> void:
	var exporters := _exporters()
	for format: StringName in exporters:
		var target: Object = exporters[format][0]
		var importer: Callable = exporters[format][1]
		var before: Variant = target.export_state()
		var newer: Dictionary = (before as Dictionary).duplicate(true)
		newer[_key(format)] = BustleSaveFormat.current(format) + 1
		var sent := newer.duplicate(true)
		var result: Variant = importer.call(target, newer)
		if result is BustleImportReport:
			assert_false((result as BustleImportReport).ok, format)
			assert_string_contains(str((result as BustleImportReport).errors), "is newer than this version reads", format)
		elif result != null:
			assert_false(result, "%s refuses it" % format)
		assert_eq(target.export_state(), before, "%s changed nothing" % format)
		assert_eq(newer, sent, "%s left the payload alone" % format)
		assert_false(BustleSaveFormat.check(format, newer).ok, "%s: check() gives the reason" % format)
