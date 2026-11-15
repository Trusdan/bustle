# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The golden save fixtures (docs/saves.md): every save each released version wrote loads into the
## current code, field by field, and reads back through the public getters; a newer copy of it is
## refused and leaves the loaded state alone. Fixtures: tests/save_fixtures/<tag>/, written from
## the tags by tools/save_fixtures.sh with tools/save_fixtures/save_builder.gd.

const Builder := preload("res://tools/save_fixtures/save_builder.gd")
const ROOT := "res://tests/save_fixtures/"
const TAGS: Array[String] = ["v0.8.0", "v0.9.0"]
const COUNTS := {"v0.8.0": 22, "v0.9.0": 31}

var _builder := Builder.new()


static func _fixture(tag: String, format: StringName) -> Dictionary:
	var data: Variant = str_to_var(FileAccess.get_file_as_string("%s%s/%s.txt" % [ROOT, tag, format]))
	return data if data is Dictionary else {}


static func _formats(tag: String) -> Array[StringName]:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + tag + "/index.json"))
	var out: Array[StringName] = []
	for file: String in (index as Dictionary)["files"]:
		out.append(StringName(file.get_basename()))
	return out


## Loads [param saved] into a fresh target; returns the target, or null when it was refused.
func _load(format: StringName, saved: Dictionary) -> Object:
	var made: Array = _builder.target(format)
	var before: Variant = (made[0] as Object).export_state()
	var result: Variant = (made[1] as Callable).call(made[0], saved.duplicate(true))
	if result is BustleImportReport:
		return made[0] if (result as BustleImportReport).ok else null
	if result == null:
		return made[0] if (made[0] as Object).export_state() != before else null
	return made[0] if result else null


## Asserts every leaf of [param expected] against [param actual], naming the path.
func _walk(expected: Variant, actual: Variant, where: String) -> void:
	if expected is Dictionary:
		assert_true(actual is Dictionary, where + ": a dictionary")
		if not actual is Dictionary:
			return
		assert_eq((actual as Dictionary).keys().size(), (expected as Dictionary).keys().size(), where + ": the same keys")
		for key: Variant in expected:
			assert_true((actual as Dictionary).has(key), "%s/%s: present" % [where, key])
			if (actual as Dictionary).has(key):
				_walk(expected[key], actual[key], "%s/%s" % [where, key])
	elif expected is Array:
		assert_true(actual is Array, where + ": an array")
		if not actual is Array:
			return
		assert_eq((actual as Array).size(), (expected as Array).size(), where + ": the same length")
		for i: int in mini((expected as Array).size(), (actual as Array).size()):
			_walk(expected[i], actual[i], "%s/%d" % [where, i])
	else:
		assert_eq(typeof(actual), typeof(expected), where + ": the same type")
		assert_eq(actual, expected, where)


func test_each_tag_has_its_fixtures() -> void:
	for tag: String in TAGS:
		var formats := _formats(tag)
		assert_eq(formats.size(), COUNTS[tag], tag)
		for format: StringName in formats:
			assert_true(Builder.FORMATS.has(format), "%s %s is a saved class" % [tag, format])
			assert_false(_fixture(tag, format).is_empty(), "%s %s parses" % [tag, format])
	assert_eq(_formats("v0.8.0").has(&"BustleSociety"), true)


func test_every_fixture_loads_field_by_field() -> void:
	for tag: String in TAGS:
		for format: StringName in _formats(tag):
			var saved := _fixture(tag, format)
			var loaded := _load(format, saved)
			assert_not_null(loaded, "%s %s loads" % [format, tag])
			if loaded != null:
				_walk(saved, loaded.export_state(), "%s %s" % [format, tag])


func test_the_loaded_saves_read_back_through_their_getters() -> void:
	for tag: String in TAGS:
		var formats := _formats(tag)
		var at := func(format: StringName) -> Object: return _load(format, _fixture(tag, format)) if formats.has(format) else null
		var society: Object = at.call(&"BustleSociety")
		assert_eq(society.agent_ids(), [&"baker", &"smith"] as Array[StringName], tag)
		assert_eq(society.get_agent(&"smith").protection, 1, tag)
		assert_eq(society.world_seed, Builder.SEED, tag)
		assert_eq(society.lock_ids(&"baker"), [&"curfew"] as Array[StringName], tag)
		assert_eq(at.call(&"BustleTradePort").balance(&"baker"), 40, tag)
		assert_almost_eq(at.call(&"BustleNeedSet").pressure(&"thirst"), 0.6, 1e-6, tag)
		assert_almost_eq(at.call(&"BustlePersonality").slider(&"diligence"), 75.0, 1e-6, tag)
		assert_eq(at.call(&"BustleMood").count(&"warm_meal"), 1, tag)
		assert_eq(at.call(&"BustleMemory").size(), 2, tag)
		assert_true(at.call(&"BustleSocialStore").opinion(&"smith", &"baker") > 0, tag)
		assert_eq(at.call(&"BustleSocialStore").kinds_between(&"baker", &"smith"), PackedStringArray(["neighbour"]), tag)
		assert_eq(at.call(&"BustleAffordance").holders(600), [&"baker", &"smith"] as Array[StringName], tag)
		assert_eq(at.call(&"BustleCrimeWatch").records().size(), 1, tag)
		assert_eq(at.call(&"BustleMentalState").active()["since"], 600, tag)
		assert_eq(at.call(&"BustleSequenceRunner").failure["action"], &"ring_bell", tag)
		assert_eq(at.call(&"BustlePropertyPort").item(&"anvil")["protected"], true, tag)
		if tag == "v0.8.0":
			continue
		var stages: Object = at.call(&"BustleLifeStages")
		assert_eq(stages.living_ids(), [&"baker", &"smith"] as Array[StringName], tag)
		assert_almost_eq(stages.age_days(&"baker"), 20.0 * 60.0 + 3.0, 1e-6, tag)
		assert_eq(at.call(&"BustleCareers").rank_of(&"baker"), &"apprentice", tag)
		assert_eq(at.call(&"BustleJobBoard").job_ids(), [&"job_1"] as Array[StringName], tag)
		assert_eq(at.call(&"BustleAspirations").points(), 17, tag)
		assert_eq(at.call(&"BustleAmbitions").active()["id"], "train_an_apprentice", tag)
		assert_eq(at.call(&"BustleRomance").bonded_to(&"baker", &"courting"), &"smith", tag)
		assert_true(at.call(&"BustleSkills").level(&"baker", &"baking") >= 0.0, tag)
		assert_eq(at.call(&"BustleEnvironmentPort").scores(&"bakehouse")[&"beauty"], 0.5, tag)


func test_a_newer_copy_of_every_fixture_is_refused_and_changes_nothing() -> void:
	for tag: String in TAGS:
		for format: StringName in _formats(tag):
			var saved := _fixture(tag, format)
			var made: Array = _builder.target(format)
			(made[1] as Callable).call(made[0], saved.duplicate(true))
			var before: Variant = (made[0] as Object).export_state()
			var key := "schema" if format == &"BustleSociety" else "version"
			var current := BustleSaveFormat.current(format)
			var newer := saved.duplicate(true)
			newer[key] = current + 1
			var result: Variant = (made[1] as Callable).call(made[0], newer)
			var where := "%s %s" % [format, tag]
			if result is BustleImportReport:
				assert_false((result as BustleImportReport).ok, where)
			elif result != null:
				assert_false(result, where)
			assert_eq(var_to_str((made[0] as Object).export_state()), var_to_str(before), where + ": unchanged")
			var report := BustleSaveFormat.check(format, newer)
			assert_false(report.ok, where)
			assert_string_contains(report.errors[0], "%d is newer than this version reads (%d)" % [current + 1, current], where)
