# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The skills module: levels from XP, decay above the floor only, determinism, the zero default
## when the module is off, and save and load. The skills are a tiny generic test set.

const DAY := BustleClockPort.MINUTES_PER_DAY


func _def(id: StringName, floor_level: float = 0.0, per_day: float = 0.0, curve: Array[float] = [100.0]) -> BustleSkillDef:
	var def := BustleSkillDef.new()
	def.id = id
	def.decay_floor = floor_level
	def.decay_per_day = per_day
	def.xp_curve = curve
	return def


func _skills() -> BustleSkills:
	var defs: Array[BustleSkillDef] = [
		_def(&"cooking", 5.0, 0.5),
		_def(&"farming", 0.0, 0.25, [50.0, 100.0, 200.0]),
		_def(&"crafts"),
	]
	return BustleSkills.new(defs)


func test_level_comes_from_xp_through_the_curve() -> void:
	var skills := _skills()
	assert_true(skills.add_xp(&"baker", &"farming", 50.0))
	assert_almost_eq(skills.level(&"baker", &"farming"), 1.0, 1e-9)
	skills.add_xp(&"baker", &"farming", 50.0)
	assert_almost_eq(skills.level(&"baker", &"farming"), 1.5, 1e-9)
	skills.add_xp(&"baker", &"farming", 350.0)
	assert_almost_eq(skills.level(&"baker", &"farming"), 3.5, 1e-9, "the last cost repeats")
	assert_eq(skills.level(&"baker", &"cooking"), 0.0, "no practice")
	assert_eq(skills.level(&"smith", &"farming"), 0.0, "unknown agent")


func test_xp_stops_at_the_top_level() -> void:
	var skills := _skills()
	skills.add_xp(&"baker", &"crafts", 1.0e6)
	assert_eq(skills.level(&"baker", &"crafts"), 20.0)
	assert_eq(skills.xp_of(&"baker", &"crafts"), 2000.0)


func test_set_level_round_trips() -> void:
	var skills := _skills()
	assert_true(skills.set_level(&"baker", &"farming", 2.25))
	assert_almost_eq(skills.level(&"baker", &"farming"), 2.25, 1e-9)
	assert_almost_eq(skills.xp_of(&"baker", &"farming"), 200.0, 1e-9)
	skills.set_level(&"baker", &"farming", 99.0)
	assert_eq(skills.level(&"baker", &"farming"), 20.0, "clamped to the top")


func test_bad_input_is_refused_without_change() -> void:
	var skills := _skills()
	skills.add_xp(&"baker", &"crafts", 120.0)
	var before := skills.export_state()
	assert_false(skills.add_xp(&"baker", &"crafts", -1.0))
	assert_false(skills.add_xp(&"baker", &"crafts", NAN))
	assert_false(skills.add_xp(&"baker", &"weaving", 10.0), "unknown skill")
	assert_false(skills.add_xp(&"", &"crafts", 10.0))
	assert_false(skills.set_level(&"baker", &"crafts", INF))
	assert_false(skills.set_level(&"baker", &"weaving", 3.0))
	assert_false(skills.advance(&"baker", -1))
	assert_eq(skills.export_state(), before)
	assert_eq(skills.level(&"baker", &"weaving"), 0.0, "an unknown skill reads as 0")


func test_invalid_or_repeated_defs_are_refused() -> void:
	var skills := _skills()
	assert_false(skills.add_def(_def(&"cooking")), "id taken")
	assert_false(skills.add_def(_def(&"")))
	assert_false(skills.add_def(_def(&"sewing", -1.0)))
	assert_false(skills.add_def(_def(&"sewing", 0.0, -0.5)))
	assert_false(skills.add_def(_def(&"sewing", 0.0, 0.0, [100.0, 0.0])))
	assert_false(skills.add_def(null))
	assert_eq(skills.skill_ids(), [&"cooking", &"crafts", &"farming"] as Array[StringName])


# Acceptance (3): decay applies only above the configured floor.
func test_decay_lowers_the_level_but_never_below_the_floor() -> void:
	var skills := _skills()
	skills.set_level(&"baker", &"cooking", 9.0)
	skills.advance(&"baker", DAY * 2)
	assert_almost_eq(skills.level(&"baker", &"cooking"), 8.0, 1e-9)
	skills.advance(&"baker", DAY * 100)
	assert_almost_eq(skills.level(&"baker", &"cooking"), 5.0, 1e-9, "stops at the floor")
	skills.advance(&"baker", DAY * 100)
	assert_almost_eq(skills.level(&"baker", &"cooking"), 5.0, 1e-9)


func test_no_decay_at_or_below_the_floor() -> void:
	var skills := _skills()
	skills.set_level(&"baker", &"cooking", 5.0)
	skills.set_level(&"smith", &"cooking", 3.5)
	skills.advance(&"baker", DAY * 30)
	skills.advance(&"smith", DAY * 30)
	assert_almost_eq(skills.level(&"baker", &"cooking"), 5.0, 1e-9)
	assert_almost_eq(skills.level(&"smith", &"cooking"), 3.5, 1e-9)


func test_a_skill_without_a_decay_rate_keeps_its_level() -> void:
	var skills := _skills()
	skills.set_level(&"baker", &"crafts", 12.0)
	skills.advance(&"baker", DAY * 365)
	assert_almost_eq(skills.level(&"baker", &"crafts"), 12.0, 1e-9)


func test_one_long_advance_equals_many_short_ones() -> void:
	var long_run := _skills()
	var short_run := _skills()
	for skills: BustleSkills in [long_run, short_run]:
		skills.set_level(&"baker", &"cooking", 11.3)
		skills.set_level(&"baker", &"farming", 4.7)
	long_run.advance(&"baker", DAY * 7)
	for step: int in 7 * 24:
		short_run.advance(&"baker", 60)
	for skill: StringName in [&"cooking", &"farming"]:
		assert_almost_eq(short_run.level(&"baker", skill), long_run.level(&"baker", skill), 1e-6, skill)


# Acceptance (4): the same practice and time give the same levels.
func test_same_practice_and_time_give_the_same_levels() -> void:
	var runs: Array[Dictionary] = []
	for run: int in 2:
		var skills := _skills()
		for day: int in 20:
			skills.add_xp(&"baker", &"cooking", 37.5)
			skills.add_xp(&"smith", &"farming", 12.25 * (day % 3))
			skills.advance(&"baker", DAY)
			skills.advance(&"smith", DAY)
		runs.append(skills.export_state())
	assert_eq(runs[0], runs[1])
	assert_false(runs[0]["xp"].is_empty())


# Acceptance (5): with the module off, level() stays 0 and nothing errors.
func test_module_off_keeps_the_zero_default() -> void:
	var society := BustleSociety.new()
	assert_eq(society.ports.skills.get_script(), BustleSkillSet)
	assert_eq(society.ports.skills.level(&"baker", &"cooking"), 0.0)
	assert_eq(society.ports.skills.level(&"", &""), 0.0)
	assert_push_error_count(0)


func test_module_installs_as_the_skill_set() -> void:
	var society := BustleSociety.new()
	var skills := _skills()
	assert_true(society.set_port(&"skills", skills))
	skills.set_level(&"baker", &"crafts", 3.0)
	assert_almost_eq(society.ports.skills.level(&"baker", &"crafts"), 3.0, 1e-9)


func test_save_round_trip() -> void:
	var skills := _skills()
	skills.add_xp(&"baker", &"cooking", 640.0)
	skills.add_xp(&"baker", &"farming", 75.0)
	skills.set_level(&"smith", &"crafts", 20.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(skills.export_state()))
	var copy := _skills()
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), skills.export_state())
	for skill: StringName in copy.skill_ids():
		assert_eq(copy.level(&"baker", skill), skills.level(&"baker", skill), skill)
	assert_eq(copy.agent_ids(), [&"baker", &"smith"] as Array[StringName])


# Acceptance (6): import refuses unknown skills or malformed data and changes nothing.
func test_import_refuses_bad_data_and_changes_nothing() -> void:
	var skills := _skills()
	skills.add_xp(&"baker", &"cooking", 300.0)
	var before := skills.export_state()
	var bad: Array = [
		null,
		[],
		{},
		{"xp": []},
		{"xp": {"baker": {"weaving": 10.0}}},
		{"xp": {"baker": {"cooking": -1.0}}},
		{"xp": {"baker": {"cooking": "ten"}}},
		{"xp": {"baker": {"cooking": INF}}},
		{"xp": {"baker": {"cooking": 1.0e9}}},
		{"xp": {"baker": 5}},
		{"xp": {"": {"cooking": 1.0}}},
		{"xp": {"baker": {"cooking": 10.0}, "smith": {"weaving": 1.0}}},
	]
	for saved: Variant in bad:
		assert_false(skills.import_state(saved), str(saved))
		assert_eq(skills.export_state(), before, str(saved))
	assert_almost_eq(skills.level(&"baker", &"cooking"), 3.0, 1e-9)


func test_forget_drops_an_agent() -> void:
	var skills := _skills()
	skills.add_xp(&"baker", &"cooking", 100.0)
	skills.forget(&"baker")
	assert_eq(skills.level(&"baker", &"cooking"), 0.0)
	assert_true(skills.agent_ids().is_empty())
