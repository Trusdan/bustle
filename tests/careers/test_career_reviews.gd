# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Careers, part 2: performance from mood, skill and attendance, reviews after the configured days,
## promotion and demotion through the host hook, thoughts, catch-up and saving.

const DAY := 1440
const START := 480
const END := 960

var _roles: BustleRolesPort
var _jobs: BustleRoleSchedules
var _roster: BustleScheduleRoster
var _skills: BustleSkills
var _careers: BustleCareers


func _rank(id: StringName, wage: int, min_skill: float = 0.0) -> BustleCareerRank:
	var rank := BustleCareerRank.new()
	rank.id = id
	rank.wage = wage
	rank.min_skill = min_skill
	rank.review_days = 3
	return rank


func _routine(activity: StringName) -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = activity
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


func before_each() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"agent_a", &"clerk_2": &"agent_b"}
	_roles = BustleRolesPort.new(table)
	_jobs = BustleRoleSchedules.new()
	_jobs.schedules = {&"clerk": _routine(&"work"), &"clerk_2": _routine(&"work")}
	_jobs.employers = {&"clerk": &"firm", &"clerk_2": &"firm"}
	_roster = BustleScheduleRoster.new(_roles, _jobs)
	_roster.add_agent(&"agent_a")
	_roster.add_agent(&"agent_b")
	var ports := BustlePorts.new()
	var crafts := BustleSkillDef.new()
	crafts.id = &"crafts"
	_skills = BustleSkills.new([crafts] as Array[BustleSkillDef])
	ports.skills = _skills
	var defs: Array[BustleCareerDef] = []
	for role: StringName in [&"clerk", &"clerk_2"]:
		var def := BustleCareerDef.new()
		def.id = StringName("office_" + String(role))
		def.role = role
		def.skill = &"crafts"
		def.activity = &"work"
		def.ranks = [_rank(&"junior", 8), _rank(&"senior", 15), _rank(&"chief", 25, 8.0)]
		defs.append(def)
	_careers = BustleCareers.new(defs, _roster, ports)


# Works days [param from] to [param from] + [param count] − 1, arriving [param late] minutes in
# (−1: missing the block), updating once at the end of each day.
func _days(id: StringName, from: int, count: int, mood: Object, late: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for day: int in range(from, from + count):
		if late >= 0:
			_roster.schedule_of(id).attend(day * DAY + START + late, &"work")
		out.append_array(_careers.update(id, (day + 1) * DAY, mood))
	return out


func _start(id: StringName, rank: StringName, skill: float) -> void:
	_skills.set_level(id, &"crafts", skill)
	assert_true(_careers.assign(id, StringName("office_" + String(_roster.job_of(id))), rank, 0))


# Acceptance (2): performance above the line leads to promotion within the configured days.
func test_good_work_is_promoted_after_the_review_days() -> void:
	_start(&"agent_a", &"junior", 10.0)
	watch_signals(_careers)
	assert_true(_days(&"agent_a", 0, 2, _mood(90.0)).is_empty(), "no review before 3 days")
	assert_almost_eq(_careers.performance(&"agent_a"), 0.96, 1e-9, "0.4 × 0.9 + 0.3 × 1 + 0.3 × 1")
	var reviews := _days(&"agent_a", 2, 1, _mood(90.0))
	assert_eq(reviews.size(), 1)
	assert_eq(reviews[0]["outcome"], BustleCareers.PROMOTED)
	assert_eq(reviews[0]["at"], 3 * DAY)
	assert_signal_emitted_with_parameters(_careers, "promotion_due", [&"agent_a", &"office_clerk", &"junior", &"senior"])
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")
	assert_eq(_careers.since_of(&"agent_a"), 3 * DAY)
	assert_eq(_roster.schedule_of(&"agent_a").wages[&"work"], 15, "the new rank's wage on the career block")
	var facts := {}
	_careers.fill_inputs(&"agent_a", facts)
	assert_eq(facts, {BustleCareers.PROMOTION_GRANTED: true})


func test_a_promotion_completes_the_ambition_to_be_promoted() -> void:
	_start(&"agent_a", &"junior", 10.0)
	var personality := BustlePersonality.new()
	personality.set_slider(&"diligence", 100.0)
	var ambitions := BustleAmbitions.new(&"agent_a", BustleAmbitionConfig.new())
	assert_eq(ambitions.update(0, personality, {"has_role": true})["id"], "get_promoted")
	_days(&"agent_a", 0, 3, _mood(90.0))
	var facts := {"has_role": true}
	_careers.fill_inputs(&"agent_a", facts)
	ambitions.update(3 * DAY, personality, facts)
	assert_true(ambitions.export_state()["completed"].has("get_promoted"))
	_days(&"agent_a", 3, 3, _mood(0.0))
	facts = {}
	_careers.fill_inputs(&"agent_a", facts)
	assert_true(facts.is_empty(), "only until the next review")


func test_a_refusing_hook_keeps_the_rank() -> void:
	_start(&"agent_a", &"junior", 10.0)
	var asked: Array = []
	_careers.review_hook = func(id: StringName, career: StringName, from: StringName, to: StringName, kind: StringName) -> bool:
		asked.append([id, career, from, to, kind])
		return false
	watch_signals(_careers)
	var reviews := _days(&"agent_a", 0, 3, _mood(90.0))
	assert_eq(asked, [[&"agent_a", &"office_clerk", &"junior", &"senior", BustleCareers.PROMOTED]])
	assert_signal_emitted(_careers, "promotion_due")
	assert_eq(reviews[0]["outcome"], BustleCareers.GOOD_REVIEW)
	assert_eq(_careers.rank_of(&"agent_a"), &"junior")
	assert_eq(_roster.schedule_of(&"agent_a").wages[&"work"], 8)
	var facts := {}
	_careers.fill_inputs(&"agent_a", facts)
	assert_true(facts.is_empty())


func test_no_promotion_past_the_top_or_without_the_next_ranks_skill() -> void:
	_start(&"agent_a", &"senior", 7.0)
	watch_signals(_careers)
	assert_eq(_days(&"agent_a", 0, 3, _mood(100.0))[0]["outcome"], BustleCareers.GOOD_REVIEW, "chief needs skill 8")
	assert_signal_not_emitted(_careers, "promotion_due")
	_skills.set_level(&"agent_a", &"crafts", 8.0)
	assert_eq(_days(&"agent_a", 3, 3, _mood(100.0))[0]["outcome"], BustleCareers.PROMOTED)
	assert_eq(_days(&"agent_a", 6, 3, _mood(100.0))[0]["outcome"], BustleCareers.GOOD_REVIEW, "top rank")
	assert_eq(_careers.rank_of(&"agent_a"), &"chief")


# Acceptance (3): low mood lowers performance by the published curve.
func test_low_mood_lowers_performance_by_the_curve() -> void:
	_start(&"agent_a", &"junior", 5.0)
	_start(&"agent_b", &"junior", 5.0)
	_days(&"agent_a", 0, 1, _mood(90.0))
	_days(&"agent_b", 0, 1, _mood(20.0))
	assert_almost_eq(_careers.performance(&"agent_a"), 0.4 * 0.9 + 0.3 * 0.5 + 0.3, 1e-9)
	assert_almost_eq(_careers.performance(&"agent_a") - _careers.performance(&"agent_b"), 0.4 * 0.7, 1e-9)
	assert_almost_eq(_careers.day_performance(0.5), 0.5, 1e-9, "mood only")
	assert_almost_eq(_careers.day_performance(1.0, NAN, 0.0), 0.4 / 0.7, 1e-9, "no skill term")
	_careers.mood_weight = 0.8
	assert_almost_eq(_careers.day_performance(0.0, 1.0, 1.0), 0.6 / 1.4, 1e-9, "configurable")


func test_late_and_missed_blocks_lower_attendance() -> void:
	_start(&"agent_a", &"junior", 0.0)
	_days(&"agent_a", 0, 1, null, 30)
	assert_almost_eq(_careers.performance(&"agent_a"), 0.4 * 0.5 + 0.3 * 0.5, 1e-9, "late counts half; no mood is neutral")
	_days(&"agent_a", 1, 1, null, -1)
	assert_almost_eq(_careers.performance(&"agent_a"), (0.35 + 0.2) / 2.0, 1e-9, "missed counts 0")


# Acceptance (4): low performance for the configured days leads to demotion.
func test_poor_work_is_demoted_after_the_review_days() -> void:
	_start(&"agent_a", &"senior", 0.0)
	watch_signals(_careers)
	var reviews := _days(&"agent_a", 0, 3, _mood(10.0), -1)
	assert_eq(reviews[0]["outcome"], BustleCareers.DEMOTED)
	assert_almost_eq(float(reviews[0]["performance"]), 0.04, 1e-9)
	assert_signal_emitted_with_parameters(_careers, "demotion_due", [&"agent_a", &"office_clerk", &"senior", &"junior"])
	assert_eq(_careers.rank_of(&"agent_a"), &"junior")
	assert_eq(_roster.schedule_of(&"agent_a").wages[&"work"], 8)
	assert_eq(_days(&"agent_a", 3, 3, _mood(10.0), -1)[0]["outcome"], BustleCareers.POOR_REVIEW, "the bottom rank")


func test_a_refusing_hook_keeps_a_poor_worker_in_rank() -> void:
	_start(&"agent_a", &"senior", 0.0)
	_careers.review_hook = func(_id: StringName, _c: StringName, _f: StringName, _t: StringName, kind: StringName) -> bool:
		return kind != BustleCareers.DEMOTED
	assert_eq(_days(&"agent_a", 0, 3, _mood(10.0), -1)[0]["outcome"], BustleCareers.POOR_REVIEW)
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")


func test_reviews_leave_thoughts_only_with_a_mood() -> void:
	for outcome: StringName in [BustleCareers.PROMOTED, BustleCareers.DEMOTED, BustleCareers.GOOD_REVIEW, BustleCareers.POOR_REVIEW]:
		var def := BustleThoughtDef.new()
		def.id = outcome
		def.value = 5.0
		def.duration_hours = 24.0
		_careers.thoughts[outcome] = def
	_start(&"agent_a", &"junior", 10.0)
	var mood := _mood(90.0)
	_days(&"agent_a", 0, 3, mood)
	assert_eq(mood.count(BustleCareers.PROMOTED), 1)
	assert_eq(mood.reasons()[0]["reason"], {"career": "office_clerk", "rank": "senior", "kind": "event"})
	_start(&"agent_b", &"senior", 0.0)
	watch_signals(_careers)
	_days(&"agent_b", 0, 3, null, -1)
	assert_signal_emitted(_careers, "reviewed", "the event fires without a mood")
	assert_eq(_careers.rank_of(&"agent_b"), &"junior")
	assert_push_error_count(0)


# Acceptance (5): no roll; the same mood, skill and attendance give the same reviews, and one long
# update gives the same as stepped ones.
func test_one_long_update_equals_stepped_updates() -> void:
	var results: Array = []
	for mode: int in 3:
		before_each()
		_start(&"agent_a", &"junior", 6.0)
		var mood := _mood(85.0)
		var reviews: Array[Dictionary] = []
		for day: int in 7:
			_roster.schedule_of(&"agent_a").attend(day * DAY + START + (40 if day == 4 else 5), &"work")
			if mode == 1:
				reviews.append_array(_careers.update(&"agent_a", (day + 1) * DAY, mood))
			elif mode == 2:
				for hour: int in 24:
					reviews.append_array(_careers.update(&"agent_a", day * DAY + hour * 60 + 59, mood))
		if mode != 1:
			reviews.append_array(_careers.update(&"agent_a", 7 * DAY, mood))
		results.append([reviews, _careers.export_state()])
	assert_eq(results[1], results[0], "daily")
	assert_eq(results[2], results[0], "hourly")
	assert_eq((results[0][0] as Array).size(), 2, "two windows of three days")


func test_save_mid_window_carries_on_the_same() -> void:
	_start(&"agent_a", &"junior", 10.0)
	_days(&"agent_a", 0, 2, _mood(90.0))
	var saved: Variant = JSON.parse_string(JSON.stringify(_careers.export_state()))
	var roster_saved: Variant = JSON.parse_string(JSON.stringify(_roster.export_state()))
	var before := _careers.export_state()
	var straight := _days(&"agent_a", 2, 1, _mood(90.0))
	before_each()
	_skills.set_level(&"agent_a", &"crafts", 10.0)
	assert_true(_roster.import_state(roster_saved))
	assert_true(_careers.import_state(saved))
	assert_eq(_careers.export_state(), before, "career, rank and the review clock")
	assert_eq(_days(&"agent_a", 2, 1, _mood(90.0)), straight)
	assert_eq(_careers.rank_of(&"agent_a"), &"senior")


func test_import_refuses_a_bad_review_clock() -> void:
	_start(&"agent_a", &"junior", 10.0)
	_days(&"agent_a", 0, 1, _mood(90.0))
	var before := _careers.export_state()
	for change: Array in [["closed", "day"], ["window", [2.0]], ["window", "0.5"], ["promoted", 1]]:
		var row: Dictionary = (before["agent_a"] as Dictionary).duplicate()
		row[change[0]] = change[1]
		assert_false(_careers.import_state({"agent_a": row}), str(change))
		assert_eq(_careers.export_state(), before, str(change))


# A career ends when the agent's job is no longer the track's role, even while it still holds it.
func test_a_new_job_ends_the_career_even_with_the_role_still_held() -> void:
	_start(&"agent_a", &"junior", 0.0)
	_jobs.schedules[&"baker"] = _routine(&"work")
	_jobs.employers[&"baker"] = &"bakery"
	watch_signals(_careers)
	_roles.set_holder(&"baker", &"agent_a")
	assert_eq(_roster.job_of(&"agent_a"), &"baker", "sorts before the track's role")
	assert_eq(_careers.career_of(&"agent_a"), &"")
	assert_signal_emitted_with_parameters(_careers, "career_changed", [&"agent_a", &"office_clerk", &"junior", &""])
	assert_false(_roster.schedule_of(&"agent_a").wages.has(&"work"), "no rank wage on the new job's block")
