# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Schedules: a brain keeps its routine for three game days headless, rest-day and season
## overrides, blocks across midnight, lateness, inputs and saving.

const DAY := 1440


func test_a_brain_keeps_its_schedule_for_three_days_headless() -> void:
	var schedule := BustleSchedule.new(_routine())
	var brain := _brain()
	for now in range(0, 3 * DAY, 5):
		var senses := BustleSenses.new()
		senses.now_minutes = now
		schedule.fill_inputs(senses.inputs, now)
		var intent := brain.tick(300.0, senses)
		schedule.attend(now, intent.goal_id)
	for day in 3:
		var report := schedule.report(day, 3 * DAY)
		assert_lte(report["missed"], 1, "day %d: %s" % [day, report])
		assert_eq(report["on_time"] + report["late"] + report["missed"], 6, "six blocks a day")
		assert_gte(report["on_time"], 5, "day %d mostly on time: %s" % [day, report])


func test_a_rest_day_override_replaces_the_working_day() -> void:
	var routine := _routine()
	routine.week_offset = 5
	routine.weekdays[6] = _day([[&"sleep", 1320, 480], [&"meal", 600, 660], [&"stroll", 840, 960]])
	var schedule := BustleSchedule.new(routine)
	assert_eq(routine.weekday(1), 6, "day 1 is the rest day")
	var inputs: Dictionary[StringName, float] = {}
	schedule.fill_inputs(inputs, DAY + 600)
	assert_eq(inputs, {&"schedule.meal": 1.0} as Dictionary[StringName, float], "a late breakfast")
	schedule.fill_inputs(inputs, DAY + 9 * 60)
	assert_eq(inputs, {BustleSchedule.FREE_TIME: 1.0} as Dictionary[StringName, float], "no work at nine")
	schedule.fill_inputs(inputs, DAY + 900)
	assert_true(inputs.has(&"schedule.stroll"))
	var activities: Array[StringName] = []
	for occurrence: Dictionary in schedule.occurrences(1):
		activities.append((occurrence["block"] as BustleScheduleBlock).activity)
	assert_false(activities.has(&"work"), "the rest day has no work")
	schedule.fill_inputs(inputs, 2 * DAY + 9 * 60)
	assert_eq(inputs, {&"schedule.work": 1.0} as Dictionary[StringName, float], "back to work the day after")


func test_season_overrides_and_their_precedence() -> void:
	var routine := _routine()
	routine.seasons[&"winter"] = _day([[&"sleep", 1260, 540], [&"work", 600, 900]])
	routine.weekdays[2] = _day([[&"market", 480, 720]])
	var schedule := BustleSchedule.new(routine)
	assert_eq(schedule.block_at(8 * 60 + 30, &"winter")["block"].activity, &"sleep", "a longer winter night")
	assert_eq(schedule.block_at(8 * 60 + 30)["block"].activity, &"work", "the usual day otherwise")
	assert_eq(schedule.block_at(2 * DAY + 600, &"winter")["block"].activity, &"market", "a weekday override beats the season")
	assert_eq(BustleClockPort.new().season(), &"", "the default clock has no seasons")


func test_a_block_across_midnight_belongs_to_the_day_it_starts() -> void:
	var schedule := BustleSchedule.new(_routine())
	var night := schedule.block_at(DAY + 3 * 60)
	assert_eq(night["block"].activity, &"sleep")
	assert_eq([night["day"], night["start"], night["end"]], [0, 1320, DAY + 360])
	assert_eq((night["block"] as BustleScheduleBlock).length(), 480)
	assert_true(schedule.block_at(DAY + 360).is_empty(), "free at six")
	assert_eq(schedule.attend(DAY + 30, &"sleep"), BustleSchedule.LATE, "turning in at half past midnight is late")
	assert_eq(schedule.report(0, DAY + 400)["late"], 1, "and counts for the day it started")


func test_lateness_on_time_late_missed_and_pending() -> void:
	var routine := _routine()
	routine.day.blocks[2].late_minutes = 0
	var schedule := BustleSchedule.new(routine)
	assert_eq(schedule.attend(7 * 60 + 15, &"meal"), BustleSchedule.ON_TIME, "15 minutes is within tolerance")
	assert_eq(schedule.attend(7 * 60 + 20, &"meal"), BustleSchedule.ON_TIME, "the first arrival counts")
	assert_eq(schedule.attend(8 * 60 + 1, &"work"), BustleSchedule.LATE, "this block allows no lateness")
	assert_eq(schedule.attend(9 * 60, &"meal"), &"", "not the current block")
	assert_eq(schedule.report(0, 13 * 60), {"on_time": 1, "late": 1, "missed": 1, "pending": 3},
		"lunch was missed; the afternoon is still to come")
	var strict := _routine()
	strict.late_minutes = 15
	var other := BustleSchedule.new(strict)
	assert_eq(other.attend(7 * 60 + 16, &"meal"), BustleSchedule.LATE)


func test_inputs_keep_other_keys_and_bad_blocks_are_skipped() -> void:
	var routine := _routine()
	var bad := BustleScheduleBlock.new()
	bad.activity = &"Bad Name"
	bad.start_minute = 0
	bad.end_minute = 1440
	routine.day.blocks.push_front(bad)
	var schedule := BustleSchedule.new(routine)
	var inputs: Dictionary[StringName, float] = {&"need.rest": 0.4, &"schedule.work": 1.0}
	schedule.fill_inputs(inputs, 7 * 60)
	assert_eq(inputs, {&"need.rest": 0.4, &"schedule.meal": 1.0} as Dictionary[StringName, float])
	assert_false(schedule.activities().has(&"Bad Name"))
	assert_true(BustleSchedule.new().block_at(0).is_empty(), "no routine, always free")


func test_attendance_saves_and_bad_data_changes_nothing() -> void:
	var schedule := BustleSchedule.new(_routine())
	schedule.attend(7 * 60, &"meal")
	schedule.attend(8 * 60 + 20, &"work")
	var saved := schedule.export_state()
	var other := BustleSchedule.new(_routine())
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.export_state(), saved)
	assert_eq(other.report(0, 13 * 60), schedule.report(0, 13 * 60))
	assert_false(other.import_state({"attended": {"x": {"activity": "meal", "arrived": 1}}}))
	assert_false(other.import_state({"attended": {"420": {"activity": "meal", "arrived": 1.5}}}))
	assert_eq(other.export_state(), saved, "refused imports change nothing")
	other.attend(9 * DAY + 7 * 60, &"meal")
	assert_eq(other.export_state()["attended"].keys(), ["13380"], "a week later the old days are gone")


func _routine() -> BustleScheduleDef:
	var routine := BustleScheduleDef.new()
	routine.id = &"day_worker"
	routine.day = _day([[&"sleep", 1320, 360], [&"meal", 420, 450], [&"work", 480, 720],
		[&"meal", 720, 780], [&"work", 780, 1020], [&"meal", 1080, 1125]])
	return routine


func _day(spec: Array) -> BustleScheduleDay:
	var day := BustleScheduleDay.new()
	for item: Array in spec:
		var block := BustleScheduleBlock.new()
		block.activity = item[0]
		block.start_minute = item[1]
		block.end_minute = item[2]
		day.blocks.append(block)
	return day


func _brain() -> BustleBrain:
	var library := BustleGoalLibrary.new()
	for activity: StringName in [&"sleep", &"meal", &"work"]:
		library.goals.append(_goal(activity, BustleBands.DUTY, StringName("schedule.%s" % activity)))
	library.goals.append(_goal(&"stroll", BustleBands.PERSONAL, BustleSchedule.FREE_TIME))
	return BustleBrain.new(&"agent_a", library, BustleScoringConfig.new(), 3)


func _goal(id: StringName, band: int, input: StringName) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	var consideration := BustleConsideration.new()
	consideration.input = input
	consideration.curve = Curve.new()
	consideration.curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	consideration.curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	goal.considerations.append(consideration)
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": 5}
	goal.sequence = BustleActionSequence.new()
	goal.sequence.steps.append(step)
	return goal
