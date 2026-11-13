# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Careers, part 1: a track on a standing job, the off-site career block paid at the rank's wage,
## losing the role, jobs without a career unchanged, and saving.

const DAY := 1440
const START := 480
const END := 960

var _roles: BustleRolesPort
var _roster: BustleScheduleRoster
var _trade: BustleTradePort
var _ports: BustlePorts
var _skills: BustleSkills
var _careers: BustleCareers


func _rank(id: StringName, wage: int, min_skill: float = 0.0) -> BustleCareerRank:
	var rank := BustleCareerRank.new()
	rank.id = id
	rank.wage = wage
	rank.min_skill = min_skill
	return rank


func _track() -> BustleCareerDef:
	var def := BustleCareerDef.new()
	def.id = &"office"
	def.role = &"clerk"
	def.skill = &"crafts"
	def.activity = &"work"
	def.ranks = [_rank(&"junior", 8), _rank(&"senior", 15, 5.0)]
	return def


func before_each() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"agent_a"}
	_roles = BustleRolesPort.new(table)
	var block := BustleScheduleBlock.new()
	block.activity = &"work"
	block.start_minute = START
	block.end_minute = END
	block.place = &"office"
	block.wage = 5
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.day = day
	var jobs := BustleRoleSchedules.new()
	jobs.schedules = {&"clerk": routine}
	jobs.employers = {&"clerk": &"firm"}
	_roster = BustleScheduleRoster.new(_roles, jobs)
	_roster.add_agent(&"agent_a")
	_roster.add_agent(&"agent_b")
	_trade = BustleTradePort.new()
	_trade.set_balance(&"firm", 1000)
	_ports = BustlePorts.new()
	var crafts := BustleSkillDef.new()
	crafts.id = &"crafts"
	_skills = BustleSkills.new([crafts] as Array[BustleSkillDef])
	_ports.skills = _skills
	_careers = BustleCareers.new([_track()] as Array[BustleCareerDef], _roster, _ports)


# Attends day [param day]'s block at [param late] minutes past its start, then settles at its end.
func _work_day(day: int, late: int = 5) -> Array[Dictionary]:
	_roster.schedule_of(&"agent_a").attend(day * DAY + START + late, &"work")
	return _roster.settle(day * DAY + END, _trade)


# Acceptance (1): a career block takes the agent off site and pays at its end if attended.
func test_a_career_block_is_off_site_and_paid_at_its_end() -> void:
	assert_true(_careers.assign(&"agent_a", &"office", &"junior", 0))
	var schedule := _roster.schedule_of(&"agent_a")
	assert_false(_careers.is_away(&"agent_a", START - 10), "before the block")
	assert_false(_careers.is_away(&"agent_a", START + 1), "the block started but it hasn't gone")
	schedule.attend(START + 5, &"work")
	assert_true(_careers.is_away(&"agent_a", START + 5))
	assert_true(_careers.is_away(&"agent_a", END - 1))
	assert_false(_careers.is_away(&"agent_a", END), "back when the block ends")
	assert_true(_roster.settle(END - 1, _trade).is_empty(), "not paid before the end")
	var paid := _roster.settle(END, _trade)
	assert_eq(paid.size(), 1)
	assert_eq(paid[0]["amount"], 8, "the rank's wage, not the block's")
	assert_true(_roster.settle(END + 60, _trade).is_empty(), "paid once")
	assert_true(_roster.settle(DAY + END, _trade).is_empty(), "a missed block pays nothing")
	assert_false(_careers.is_away(&"agent_a", DAY + START + 30), "nor is it away")
	assert_eq(_trade.balance(&"agent_a"), 8)


func test_a_track_that_is_not_off_site_keeps_the_agent_here() -> void:
	_careers.def_of(&"office").off_site = false
	_careers.assign(&"agent_a", &"office", &"junior", 0)
	_roster.schedule_of(&"agent_a").attend(START, &"work")
	assert_false(_careers.is_away(&"agent_a", START + 30))
	assert_eq(_roster.settle(END, _trade)[0]["amount"], 8)


func test_a_new_rank_pays_from_the_next_block_attended() -> void:
	_careers.assign(&"agent_a", &"office", &"junior", 0)
	_skills.set_level(&"agent_a", &"crafts", 5.0)
	_roster.schedule_of(&"agent_a").attend(START, &"work")
	assert_true(_careers.assign(&"agent_a", &"office", &"senior", START + 60))
	assert_eq(_roster.settle(END, _trade)[0]["amount"], 8, "fixed when attended")
	assert_eq(_work_day(1)[0]["amount"], 15)
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")
	assert_eq(_careers.since_of(&"agent_a"), START + 60)


func test_a_rank_needs_the_job_and_its_skill() -> void:
	watch_signals(_careers)
	assert_false(_careers.assign(&"agent_b", &"office", &"junior", 0), "not its job")
	assert_false(_careers.assign(&"agent_a", &"office", &"senior", 0), "skill 0 < 5")
	assert_false(_careers.assign(&"agent_a", &"office", &"chief", 0), "no such rank")
	assert_false(_careers.assign(&"agent_a", &"clerk", &"junior", 0), "no such track")
	assert_signal_not_emitted(_careers, "career_changed")
	assert_eq(_careers.career_of(&"agent_a"), &"")
	_ports.skills = null
	assert_false(_careers.can_hold(&"agent_a", &"office", &"senior"), "no skill port: every skill is 0")
	assert_true(_careers.can_hold(&"agent_a", &"office", &"junior"))


func test_losing_the_role_ends_the_career() -> void:
	_careers.assign(&"agent_a", &"office", &"junior", 0)
	watch_signals(_careers)
	_roles.set_holder(&"clerk", &"agent_b")
	assert_signal_emitted_with_parameters(_careers, "career_changed", [&"agent_a", &"office", &"junior", &""])
	assert_eq(_careers.career_of(&"agent_a"), &"")
	assert_eq(_careers.career_of(&"agent_b"), &"", "the new holder starts with none")
	assert_true(_roster.schedule_of(&"agent_a").wages.is_empty())
	assert_true(_careers.assign(&"agent_b", &"office", &"junior", 10))


# Acceptance (6): with no career, role jobs and wages are unchanged.
func test_jobs_without_a_career_are_unchanged() -> void:
	assert_eq(_roster.job_of(&"agent_a"), &"clerk")
	assert_eq(_work_day(0)[0]["amount"], 5, "the block's own wage")
	assert_false(_careers.is_away(&"agent_a", DAY + START + 30))
	_careers.assign(&"agent_a", &"office", &"junior", DAY)
	assert_eq(_work_day(1)[0]["amount"], 8)
	assert_true(_careers.end(&"agent_a"))
	assert_eq(_work_day(2)[0]["amount"], 5, "ending the career restores it")
	assert_eq(_roster.job_of(&"agent_a"), &"clerk", "the job stays")
	assert_false(_careers.end(&"agent_a"))
	assert_push_error_count(0)


func test_save_round_trip() -> void:
	_careers.assign(&"agent_a", &"office", &"junior", 120)
	var saved: Variant = JSON.parse_string(JSON.stringify(_careers.export_state()))
	assert_eq(saved, {"agent_a": {"career": "office", "rank": "junior", "since": 120.0}})
	before_each()
	assert_true(_careers.import_state(saved))
	assert_eq(_careers.rank_of(&"agent_a"), &"junior")
	assert_eq(_careers.since_of(&"agent_a"), 120)
	assert_eq(_work_day(0)[0]["amount"], 8, "the rank's wage is back on the block")
	assert_true(_careers.import_state({}))
	assert_eq(_work_day(1)[0]["amount"], 5, "and gone with the career")


func test_import_refuses_bad_data_and_changes_nothing() -> void:
	_careers.assign(&"agent_a", &"office", &"junior", 0)
	var before := _careers.export_state()
	for saved: Variant in [null, [], {"agent_a": "office"}, {"": {"career": "office", "rank": "junior", "since": 0}},
			{"agent_a": {"career": "farm", "rank": "junior", "since": 0}},
			{"agent_a": {"career": "office", "rank": "chief", "since": 0}},
			{"agent_a": {"career": "office", "rank": "junior", "since": "noon"}},
			{"agent_a": {"career": "office", "rank": "junior", "since": 1.5}}]:
		assert_false(_careers.import_state(saved), str(saved))
		assert_eq(_careers.export_state(), before, str(saved))
	assert_eq(_roster.schedule_of(&"agent_a").wages, {&"work": 8} as Dictionary[StringName, int])


func test_invalid_tracks_are_refused() -> void:
	assert_false(_careers.add_def(_track()), "id taken")
	var bad := _track()
	bad.id = &"other"
	bad.skill = &""
	assert_false(bad.is_valid(), "a skill minimum needs a skill")
	bad = _track()
	bad.ranks.append(_rank(&"junior", 1))
	assert_false(bad.is_valid(), "repeated rank")
	bad = _track()
	bad.ranks.clear()
	assert_false(bad.is_valid(), "no ranks")
	assert_false(_careers.add_def(null))
