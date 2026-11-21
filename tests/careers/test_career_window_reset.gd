# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## A host can reset a career's review window after a break (reset_window). Without it, days off
## pause the window, so working days before and after a break count together. A reset drops the
## window's scores and its pinned period, and nothing else: no review, no signal, the same rank,
## wage, start, last closed day and granted promotion. The next working day starts a new window.
## Saves keep their shape. Performance here: skill 10, mood 90, on time 0.96; missed 0.66.

const DAY := 1440
const START := 480
const END := 960

var _roles: BustleRolesPort
var _jobs: BustleRoleSchedules
var _roster: BustleScheduleRoster
var _ports: BustlePorts
var _skills: BustleSkills
var _careers: BustleCareers


# Reviewed every 3 working days; a "busy" period every 2 and a "long" one every 5.
func _rank(id: StringName, wage: int) -> BustleCareerRank:
	var rank := BustleCareerRank.new()
	rank.id = id
	rank.wage = wage
	rank.review_days = 3
	var busy := BustleCareerPeriod.new()
	busy.review_days = 2
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


func _mood(value: float) -> BustleMood:
	var mood := BustleMood.new()
	mood.mood = value
	return mood


func before_each() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"agent_a", &"clerk_2": &"agent_b"}
	_roles = BustleRolesPort.new(table)
	_jobs = BustleRoleSchedules.new()
	_jobs.schedules = {&"clerk": _routine(), &"clerk_2": _routine()}
	_jobs.employers = {&"clerk": &"office", &"clerk_2": &"office"}
	_roster = BustleScheduleRoster.new(_roles, _jobs)
	_roster.add_agent(&"agent_a")
	_roster.add_agent(&"agent_b")
	var crafts := BustleSkillDef.new()
	crafts.id = &"crafts"
	_skills = BustleSkills.new([crafts] as Array[BustleSkillDef])
	_ports = BustlePorts.new()
	_ports.skills = _skills
	_careers = BustleCareers.new(_defs(), _roster, _ports)
	_skills.set_level(&"agent_a", &"crafts", 10.0)
	assert_true(_careers.assign(&"agent_a", &"office_clerk", &"junior", 0))


# A closed season: weekdays 2 to 6 (days 2-6, 9-13, ...) have no career block, so the working days
# are 0, 1, 7, 8, 14, 15, ...
func _with_break() -> void:
	var routine := _routine()
	for weekday: int in range(2, 7):
		routine.weekdays[weekday] = BustleScheduleDay.new()
	_jobs.schedules[&"clerk"] = routine
	_roster.refresh_all()


# Days [param from] to [param from] + [param count] − 1, attending each working day's block (unless
# [param missed]) and updating at each day's end.
func _days(from: int, count: int, missed: bool = false, period: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for day: int in range(from, from + count):
		if not missed:
			_roster.schedule_of(&"agent_a").attend(day * DAY + START, &"work")
		out.append_array(_careers.update_in_period(&"agent_a", (day + 1) * DAY, period, _mood(90.0)))
	return out


func _state() -> Dictionary:
	return _careers.export_state()["agent_a"]


func test_without_a_reset_a_break_pauses_the_window() -> void:
	_with_break()
	assert_true(_days(0, 7, true).is_empty(), "two missed working days, then five days off")
	assert_eq((_state()["window"] as Array).size(), 2, "the window waits through the break")
	var reviews := _days(7, 1)
	assert_eq(reviews.size(), 1, "the first working day after the break completes it")
	assert_eq(reviews[0]["at"], 8 * DAY)
	assert_almost_eq(float(reviews[0]["performance"]), (0.66 + 0.66 + 0.96) / 3.0, 1e-9,
		"the days before and after the break are judged together")


func test_a_reset_starts_a_full_new_window() -> void:
	_with_break()
	_days(0, 7, true)
	assert_almost_eq(_careers.performance(&"agent_a"), 0.66, 1e-9)
	assert_true(_careers.reset_window(&"agent_a"))
	assert_true(is_nan(_careers.performance(&"agent_a")), "nothing scored in the new window yet")
	assert_true(_days(7, 2).is_empty(), "two new working days: the two before the reset don't count")
	assert_almost_eq(_careers.performance(&"agent_a"), 0.96, 1e-9, "only the new days")
	assert_true(_days(9, 5).is_empty(), "the next break")
	var reviews := _days(14, 1)
	assert_eq(reviews.size(), 1, "the third working day after the reset")
	assert_eq(reviews[0]["at"], 15 * DAY)
	assert_almost_eq(float(reviews[0]["performance"]), 0.96, 1e-9)
	assert_eq(reviews[0]["outcome"], BustleCareers.PROMOTED)


func test_a_reset_reviews_nothing_and_fires_no_signal() -> void:
	_days(0, 2, true)
	watch_signals(_careers)
	assert_true(_careers.reset_window(&"agent_a"))
	for name: String in ["reviewed", "promotion_due", "demotion_due", "career_changed"]:
		assert_signal_not_emitted(_careers, name)
	assert_eq(_careers.rank_of(&"agent_a"), &"junior", "a poor partial window demotes nobody")


func test_closed_days_are_not_scored_again() -> void:
	for day: int in 3:
		_roster.schedule_of(&"agent_a").attend(day * DAY + START, &"work")
	_careers.update(&"agent_a", 2 * DAY, _mood(90.0))
	assert_eq(_state()["closed"], 1)
	assert_true(_careers.reset_window(&"agent_a"))
	assert_eq(_state()["closed"], 1, "the last closed day is kept")
	assert_true(_careers.update(&"agent_a", 2 * DAY, _mood(90.0)).is_empty())
	assert_eq((_state()["window"] as Array).size(), 0, "a catch-up to the same minute scores nothing")
	_careers.update(&"agent_a", 3 * DAY, _mood(90.0))
	assert_eq(_state()["closed"], 2)
	assert_eq((_state()["window"] as Array).size(), 1, "only day 2, not days 0 and 1 again")


# Only closed days are dropped: a host brings the career up to the break before resetting.
func test_days_not_yet_closed_are_scored_into_the_new_window() -> void:
	for day: int in 2:
		_roster.schedule_of(&"agent_a").attend(day * DAY + START, &"work")
	assert_true(_careers.reset_window(&"agent_a"), "no update yet: nothing closed")
	_careers.update(&"agent_a", 2 * DAY, _mood(90.0))
	assert_eq((_state()["window"] as Array).size(), 2, "both days close into the new window")

func test_a_reset_clears_the_pinned_period() -> void:
	_days(0, 1, false, &"long")
	assert_eq(_careers.window_period(&"agent_a"), &"long")
	assert_true(_careers.reset_window(&"agent_a"))
	assert_eq(_careers.window_period(&"agent_a"), &"", "no window, no period")
	assert_false(_state().has("period"), "and none saved")
	assert_true(_days(1, 1, false, &"busy").is_empty())
	assert_eq(_careers.window_period(&"agent_a"), &"busy", "the next working day starts a window in its call's period")
	var reviews := _days(2, 1, false, &"long")
	assert_eq(reviews.size(), 1, "judged by the busy rules: 2 days, not 5")
	assert_eq(reviews[0]["at"], 3 * DAY)


func test_a_reset_then_a_call_with_no_period_pins_none() -> void:
	_days(0, 1, false, &"busy")
	_careers.reset_window(&"agent_a")
	_days(1, 1)
	assert_eq(_careers.window_period(&"agent_a"), &"", "update() pins no period")
	assert_eq(_days(2, 2).size(), 1, "judged by the rank's own 3 days")


func test_no_career_is_refused_and_changes_nothing() -> void:
	_days(0, 2)
	var before := _careers.export_state()
	assert_false(_careers.reset_window(&"agent_b"), "a clerk with no career")
	assert_false(_careers.reset_window(&""))
	assert_false(_careers.reset_window(&"nobody"))
	assert_eq(_careers.export_state(), before)


func test_an_empty_window_resets_to_an_empty_window() -> void:
	var before := _careers.export_state()
	assert_true(_careers.reset_window(&"agent_a"), "a career with nothing scored yet")
	assert_true(_careers.reset_window(&"agent_a"), "and again")
	assert_eq(_careers.export_state(), before, "still empty; closed and rank as they were")
	_days(0, 1)
	_careers.reset_window(&"agent_a")
	var after_one := _careers.export_state()
	assert_true(_careers.reset_window(&"agent_a"))
	assert_eq(_careers.export_state(), after_one, "a second reset changes nothing")


func test_rank_wage_start_job_and_a_granted_promotion_are_kept() -> void:
	assert_eq(_days(0, 3)[0]["outcome"], BustleCareers.PROMOTED)
	_days(3, 1)
	var since := _careers.since_of(&"agent_a")
	var inputs := {}
	_careers.fill_inputs(&"agent_a", inputs)
	assert_true(inputs.get(BustleCareers.PROMOTION_GRANTED, false), "promoted at the last review")
	var before := _state()
	assert_true(_careers.reset_window(&"agent_a"))
	var after := _state()
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")
	assert_eq(_careers.career_of(&"agent_a"), &"office_clerk")
	assert_eq(_careers.since_of(&"agent_a"), since)
	assert_eq(_roster.job_of(&"agent_a"), &"clerk")
	assert_eq(_roster.schedule_of(&"agent_a").wages[&"work"], 15, "the senior wage stays on the block")
	inputs = {}
	_careers.fill_inputs(&"agent_a", inputs)
	assert_true(inputs.get(BustleCareers.PROMOTION_GRANTED, false), "a reset isn't a review")
	assert_true(after["promoted"])
	before.erase("window")
	after.erase("window")
	assert_eq(after, before, "only the window changed")


func test_one_long_update_after_a_reset_equals_daily_ones() -> void:
	var results: Array = []
	for mode: int in 2:
		before_each()
		_with_break()
		_days(0, 2)
		_careers.reset_window(&"agent_a")
		var reviews: Array[Dictionary] = []
		for day: int in range(2, 9):
			if day == 7 or day == 8:
				_roster.schedule_of(&"agent_a").attend(day * DAY + START + 5, &"work")
			if mode == 1:
				reviews.append_array(_careers.update(&"agent_a", (day + 1) * DAY, _mood(90.0)))
		if mode == 0:
			reviews = _careers.update(&"agent_a", 9 * DAY, _mood(90.0))
		results.append([reviews, _careers.export_state()])
	assert_eq(results[1], results[0])
	assert_eq((results[0][1]["agent_a"]["window"] as Array).size(), 2, "two days in the new window")


func test_a_reset_saves_and_loads_and_carries_on_the_same() -> void:
	var results: Array = []
	for mode: int in 2:
		before_each()
		_days(0, 2)
		_days(2, 1, false, &"long")
		assert_true(_careers.reset_window(&"agent_a"))
		_days(3, 1)
		var saved := _careers.export_state()
		assert_eq(saved["agent_a"].keys(), ["career", "rank", "since", "closed", "window", "promoted"],
			"the same shape as before, with no period")
		if mode == 1:
			_careers = BustleCareers.new(_defs(), _roster, _ports)
			assert_true(_careers.import_state(JSON.parse_string(JSON.stringify(saved))), "through JSON")
			assert_eq(_careers.export_state(), saved)
		results.append(_days(4, 2) + [_careers.export_state()])
	assert_eq(results[1], results[0])
	assert_eq((results[0][0] as Dictionary)["at"], 6 * DAY, "the third working day after the reset")


func test_older_saves_load_and_reset() -> void:
	var without_clock := {"agent_a": {"career": "office_clerk", "rank": "junior", "since": 0}}
	assert_true(_careers.import_state(without_clock), "a save without the review clock")
	assert_true(_careers.reset_window(&"agent_a"))
	assert_eq(_state()["window"], [])
	var with_window := {"agent_a": {"career": "office_clerk", "rank": "junior", "since": 0, "closed": 1,
		"window": [0.5, 0.7], "promoted": false}}
	assert_true(_careers.import_state(with_window), "a save from before periods")
	assert_almost_eq(_careers.performance(&"agent_a"), 0.6, 1e-9)
	assert_true(_careers.reset_window(&"agent_a"))
	assert_eq(_state(), {"career": "office_clerk", "rank": "junior", "since": 0, "closed": 1, "window": [],
		"promoted": false})
