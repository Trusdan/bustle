# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Careers in host-defined periods: update_in_period() judges a review window by the period's rules
## (BustleCareerRank.periods), or the rank's own when it lists none; update() is the same with no
## period. A window keeps the period it started in until it is reviewed. The pin saves and loads,
## older saves load without one, and bad saves and bad period rules are refused.
## Performance here is 0.6 + 0.4 × mood ÷ 100 (skill 10 and on time every day): mood 50 gives 0.8,
## over the rank's own promotion line (0.75) but under the busy period's (0.95).

const DAY := 1440
const START := 480
const END := 960

var _roles: BustleRolesPort
var _jobs: BustleRoleSchedules
var _roster: BustleScheduleRoster
var _skills: BustleSkills
var _ports: BustlePorts
var _careers: BustleCareers


# A rank reviewed every 3 working days, with a busy period (2 days, a 0.95 promotion line) and a
# long period (5 days, the rank's own lines).
func _rank(id: StringName, wage: int) -> BustleCareerRank:
	var rank := BustleCareerRank.new()
	rank.id = id
	rank.wage = wage
	rank.review_days = 3
	var busy := BustleCareerPeriod.new()
	busy.review_days = 2
	busy.promote_if = 0.95
	busy.demote_if = 0.1
	var long := BustleCareerPeriod.new()
	long.review_days = 5
	rank.periods = {&"busy": busy, &"long": long}
	return rank


func _routine() -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = &"work"
	block.start_minute = START
	block.end_minute = END
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.day = day
	return routine


func _mood(value: float) -> BustleMood:
	var mood := BustleMood.new()
	mood.mood = value
	return mood


func _defs() -> Array[BustleCareerDef]:
	var defs: Array[BustleCareerDef] = []
	for role: StringName in [&"clerk", &"clerk_2"]:
		var def := BustleCareerDef.new()
		def.id = StringName("office_" + String(role))
		def.role = role
		def.skill = &"crafts"
		def.activity = &"work"
		def.ranks = [_rank(&"junior", 8), _rank(&"senior", 15)]
		defs.append(def)
	return defs


func before_each() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"agent_a", &"clerk_2": &"agent_b"}
	_roles = BustleRolesPort.new(table)
	_jobs = BustleRoleSchedules.new()
	_jobs.schedules = {&"clerk": _routine(), &"clerk_2": _routine()}
	_jobs.employers = {&"clerk": &"firm", &"clerk_2": &"firm"}
	_roster = BustleScheduleRoster.new(_roles, _jobs)
	_roster.add_agent(&"agent_a")
	_roster.add_agent(&"agent_b")
	_ports = BustlePorts.new()
	var crafts := BustleSkillDef.new()
	crafts.id = &"crafts"
	_skills = BustleSkills.new([crafts] as Array[BustleSkillDef])
	_ports.skills = _skills
	_careers = BustleCareers.new(_defs(), _roster, _ports)
	for id: StringName in [&"agent_a", &"agent_b"]:
		_skills.set_level(id, &"crafts", 10.0)
		assert_true(_careers.assign(id, StringName("office_" + String(_roster.job_of(id))), &"junior", 0))


# Works days [param from] to [param from] + [param count] − 1 on time, updating at the end of each
# day in [param period] (null: through update(), with no period).
func _days(id: StringName, from: int, count: int, period: Variant, mood_value: float = 50.0,
		careers: BustleCareers = null) -> Array[Dictionary]:
	var target := careers if careers != null else _careers
	var out: Array[Dictionary] = []
	for day: int in range(from, from + count):
		_roster.schedule_of(id).attend(day * DAY + START, &"work")
		if period == null:
			out.append_array(target.update(id, (day + 1) * DAY, _mood(mood_value)))
		else:
			out.append_array(target.update_in_period(id, (day + 1) * DAY, period, _mood(mood_value)))
	return out


func _outcomes(reviews: Array[Dictionary]) -> Array:
	return reviews.map(func(r: Dictionary) -> Array: return [r["at"] / DAY, r["outcome"]])


func test_update_is_update_in_period_with_no_period() -> void:
	var by_update := _days(&"agent_a", 0, 9, null)
	var by_period := _days(&"agent_b", 0, 9, &"")
	assert_eq(_outcomes(by_update), [[3, BustleCareers.PROMOTED], [6, BustleCareers.GOOD_REVIEW], [9, BustleCareers.GOOD_REVIEW]],
		"the rank's own rules: every 3 days, promoted at 0.8")
	assert_eq(_outcomes(by_period), _outcomes(by_update))
	var a: Dictionary = _careers.export_state()["agent_a"]
	var b: Dictionary = _careers.export_state()["agent_b"]
	a.erase("career")
	b.erase("career")
	assert_eq(a, b, "the same state")
	assert_false(a.has("period"), "and no period saved")


func test_a_period_s_rules_judge_its_windows() -> void:
	assert_eq(_outcomes(_days(&"agent_a", 0, 4, &"busy")), [[2, BustleCareers.STEADY], [4, BustleCareers.STEADY]],
		"busy: every 2 days, and 0.8 is under its 0.95 line")
	assert_eq(_careers.rank_of(&"agent_a"), &"junior")
	assert_eq(_outcomes(_days(&"agent_a", 4, 2, &"busy", 100.0)), [[6, BustleCareers.PROMOTED]], "1.0 clears it")


func test_a_period_the_rank_doesnt_list_uses_its_own_rules() -> void:
	assert_eq(_outcomes(_days(&"agent_a", 0, 3, &"festival")), [[3, BustleCareers.PROMOTED]])


func test_a_window_keeps_the_period_it_started_in() -> void:
	assert_eq(_outcomes(_days(&"agent_a", 0, 1, &"busy")), [])
	assert_eq(_careers.window_period(&"agent_a"), &"busy", "its first day closed in busy")
	assert_eq(_outcomes(_days(&"agent_a", 1, 1, null)), [[2, BustleCareers.STEADY]],
		"still judged in busy: 2 days, the 0.95 line")
	assert_eq(_careers.window_period(&"agent_a"), &"", "the review ends the window and its period")
	assert_eq(_outcomes(_days(&"agent_a", 2, 3, null)), [[5, BustleCareers.PROMOTED]],
		"the next window started with no period: the rank's own rules")


func test_a_period_given_mid_window_takes_effect_from_the_next_one() -> void:
	assert_eq(_outcomes(_days(&"agent_a", 0, 1, null)), [])
	assert_eq(_careers.window_period(&"agent_a"), &"")
	assert_eq(_outcomes(_days(&"agent_a", 1, 2, &"busy")), [[3, BustleCareers.PROMOTED]],
		"the window began with none: 3 days and the 0.75 line, though later days were busy")
	assert_eq(_outcomes(_days(&"agent_a", 3, 2, &"busy")), [[5, BustleCareers.STEADY]], "then busy rules")


func test_a_longer_period_window_and_a_change_of_rank() -> void:
	assert_eq(_outcomes(_days(&"agent_a", 0, 4, &"long")), [], "long: 5 days")
	assert_eq(_outcomes(_days(&"agent_a", 4, 1, &"busy")), [[5, BustleCareers.PROMOTED]], "reviewed in long, at 0.8")
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")
	assert_eq(_careers.window_period(&"agent_a"), &"", "a new rank starts a new window")
	assert_eq(_outcomes(_days(&"agent_a", 5, 2, &"busy")), [[7, BustleCareers.STEADY]], "senior's busy rules")


func test_one_long_call_gives_what_daily_calls_give() -> void:
	var daily := _days(&"agent_a", 0, 7, &"busy")
	for day: int in 7:
		_roster.schedule_of(&"agent_b").attend(day * DAY + START, &"work")
	var at_once := _careers.update_in_period(&"agent_b", 7 * DAY, &"busy", _mood(50.0))
	assert_eq(_outcomes(at_once), _outcomes(daily))
	assert_eq(_careers.window_period(&"agent_b"), _careers.window_period(&"agent_a"))


func test_the_pinned_period_saves_and_loads() -> void:
	_days(&"agent_a", 0, 1, &"busy")
	var saved := _careers.export_state()
	assert_eq(saved["agent_a"]["period"], "busy")
	assert_false(saved["agent_b"].has("period"), "only a pinned window saves a period")
	var loaded := BustleCareers.new(_defs(), _roster, _ports)
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.window_period(&"agent_a"), &"busy")
	assert_eq(_outcomes(_days(&"agent_a", 1, 1, null, 50.0, loaded)), [[2, BustleCareers.STEADY]], "still judged in busy")


func test_a_save_without_a_period_loads_with_none() -> void:
	_days(&"agent_a", 0, 1, null)
	var saved := _careers.export_state()
	var loaded := BustleCareers.new(_defs(), _roster, _ports)
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.window_period(&"agent_a"), &"")


func test_a_bad_period_in_a_save_is_refused_and_changes_nothing() -> void:
	_days(&"agent_a", 0, 1, &"busy")
	var good := _careers.export_state()
	var cases := {
		"not a string": func(row: Dictionary) -> void: row["period"] = 3,
		"empty": func(row: Dictionary) -> void: row["period"] = "",
		"on an empty window": func(row: Dictionary) -> void: row["window"] = [],
	}
	for label: String in cases:
		var saved: Dictionary = good.duplicate(true)
		cases[label].call(saved["agent_a"])
		assert_false(_careers.import_state(saved), label)
		assert_eq(_careers.export_state(), good, label + ": nothing changes")


func test_bad_period_rules_make_the_rank_invalid() -> void:
	var bad_cases := {
		"no review days": func(p: BustleCareerPeriod) -> void: p.review_days = 0,
		"demote line not below promote line": func(p: BustleCareerPeriod) -> void: p.demote_if = p.promote_if,
		"not finite": func(p: BustleCareerPeriod) -> void: p.promote_if = INF,
	}
	for label: String in bad_cases:
		var rank := _rank(&"junior", 8)
		bad_cases[label].call(rank.periods[&"busy"])
		assert_false(rank.periods[&"busy"].is_valid(), label)
		assert_false(rank.is_valid(), label)
	var unnamed := _rank(&"junior", 8)
	unnamed.periods[&""] = BustleCareerPeriod.new()
	assert_false(unnamed.is_valid(), "an empty period id")
	var missing := _rank(&"junior", 8)
	missing.periods[&"busy"] = null
	assert_false(missing.is_valid(), "a period with no rules")
	var def := BustleCareerDef.new()
	def.id = &"office"
	def.role = &"clerk"
	def.activity = &"work"
	def.ranks = [missing]
	assert_false(BustleCareers.new([], _roster, _ports).add_def(def), "a track with such a rank is refused")
