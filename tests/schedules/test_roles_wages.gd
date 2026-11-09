# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Jobs as roles and wages: a role's routine follows its holder, a change of holder swaps the
## routine at once, wages are paid once at the end of an attended shift, and saving.

const DAY := 1440

var _roles: BustleRolesPort
var _jobs: BustleRoleSchedules
var _roster: BustleScheduleRoster
var _trade: BustleTradePort


func before_each() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"baker": &"agent_a"}
	_roles = BustleRolesPort.new(table)
	_jobs = BustleRoleSchedules.new()
	_jobs.schedules = {&"baker": _routine(&"bake", 240, 600, 8), &"smith": _routine(&"forge", 480, 960, 12)}
	_jobs.employers = {&"baker": &"guild", &"smith": &"guild"}
	_roster = BustleScheduleRoster.new(_roles, _jobs)
	_roster.add_agent(&"agent_a", _routine(&"wander", 600, 720, 0))
	_roster.add_agent(&"agent_b", _routine(&"wander", 600, 720, 0))
	_trade = BustleTradePort.new()
	_trade.set_balance(&"guild", 100)


func test_a_job_is_a_role_with_a_routine() -> void:
	assert_eq(_roster.job_of(&"agent_a"), &"baker")
	assert_eq(_roster.job_of(&"agent_b"), &"", "no role, no job")
	assert_eq(BustleWorkPort.new(_roster).job_of(&"agent_a"), &"baker", "the work port's default reads it")
	assert_eq(BustleWorkPort.new().job_of(&"agent_a"), &"", "and has none without one")
	assert_eq(_roster.schedule_of(&"agent_a").def, _jobs.schedules[&"baker"])
	assert_eq(_roster.schedule_of(&"agent_b").block_at(660)["block"].activity, &"wander", "its own routine")
	_roles.set_holder(&"chair", &"agent_b")
	assert_eq(_roster.job_of(&"agent_b"), &"", "a role with no routine isn't a job")


func test_a_change_of_holder_swaps_the_routine_at_once() -> void:
	watch_signals(_roster)
	var inputs: Dictionary[StringName, float] = {&"need.rest": 0.3}
	_roster.schedule_of(&"agent_a").fill_inputs(inputs, 300)
	assert_eq(inputs[&"schedule.bake"], 1.0)
	_roles.set_holder(&"baker", &"agent_b")
	assert_signal_emit_count(_roster, "schedule_changed", 2, "both holders' routines changed")
	assert_eq(_roster.job_of(&"agent_b"), &"baker")
	assert_eq(_roster.schedule_of(&"agent_b").def, _jobs.schedules[&"baker"], "the new holder bakes")
	assert_eq(_roster.schedule_of(&"agent_a").block_at(660)["block"].activity, &"wander", "the old one goes back to its own")
	_roster.schedule_of(&"agent_a").fill_inputs(inputs, 300)
	assert_false(inputs.has(&"schedule.bake"), "the old job's input doesn't linger")
	assert_eq(inputs, {&"need.rest": 0.3, BustleSchedule.FREE_TIME: 1.0} as Dictionary[StringName, float])
	_roles.set_holder(&"smith", &"agent_a")
	assert_eq(_roster.job_of(&"agent_a"), &"smith", "and can take another job")
	_roster.schedule_of(&"agent_a").fill_inputs(inputs, 600)
	assert_eq(inputs[&"schedule.forge"], 1.0)


func test_wages_are_paid_once_at_the_end_of_an_attended_shift() -> void:
	var schedule := _roster.schedule_of(&"agent_a")
	assert_eq(schedule.attend(250, &"bake"), BustleSchedule.ON_TIME)
	assert_eq(_roster.settle(500, _trade), [] as Array[Dictionary], "not before the shift ends")
	var paid := _roster.settle(600, _trade)
	assert_eq(paid, [{"agent": &"agent_a", "start": 240, "activity": &"bake", "amount": 8, "payer": &"guild", "paid": true}] as Array[Dictionary])
	assert_eq([_trade.balance(&"agent_a"), _trade.balance(&"guild")], [8, 92])
	assert_eq(_roster.settle(700, _trade), [] as Array[Dictionary], "only once")
	assert_eq(_roster.settle(DAY + 600, _trade), [] as Array[Dictionary], "a missed shift pays nothing")
	assert_eq(schedule.report(1, DAY + 600)["missed"], 1)


func test_a_wage_the_payer_cannot_pay_stays_owed() -> void:
	_trade.set_balance(&"guild", 5)
	_roster.schedule_of(&"agent_a").attend(260, &"bake")
	assert_false(_roster.settle(600, _trade)[0]["paid"], "the guild has 5, the wage is 8")
	assert_eq(_trade.balance(&"agent_a"), 0)
	_trade.set_balance(&"guild", 20)
	assert_true(_roster.settle(610, _trade)[0]["paid"], "tried again and paid")
	assert_eq(_trade.balance(&"agent_a"), 8)


func test_a_shift_worked_before_a_change_of_job_is_still_paid() -> void:
	var block: BustleScheduleBlock = _jobs.schedules[&"baker"].day.blocks[0]
	block.payer = &"bakery"
	_trade.set_balance(&"bakery", 10)
	_roster.schedule_of(&"agent_a").attend(300, &"bake")
	_roles.set_holder(&"baker", &"")
	var paid := _roster.settle(600, _trade)
	assert_eq(paid.size(), 1)
	assert_eq([paid[0]["payer"], paid[0]["paid"]], [&"bakery", true], "paid by the block's own payer")
	assert_eq(_trade.balance(&"agent_a"), 8)


func test_attendance_and_owed_wages_save() -> void:
	_trade.set_balance(&"guild", 0)
	_roster.schedule_of(&"agent_a").attend(240, &"bake")
	_roster.settle(600, _trade)
	var saved := _roster.export_state()
	var other := BustleScheduleRoster.new(_roles, _jobs)
	other.add_agent(&"agent_a")
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.export_state()["schedules"]["agent_a"], saved["schedules"]["agent_a"])
	_trade.set_balance(&"guild", 50)
	assert_true(other.settle(700, _trade)[0]["paid"], "the owed wage came back with the save")
	assert_false(other.import_state({"schedules": {"agent_a": {"attended": {"240": {"activity": "bake", "arrived": 240, "wage": -3}}}}}))
	assert_false(other.import_state({"schedules": {7: {}}}))


func test_definitions_refuse_reserved_names_negative_wages_and_empty_weeks() -> void:
	var block := BustleScheduleBlock.new()
	block.start_minute = 60
	block.end_minute = 120
	block.activity = &"free_time"
	assert_false(block.is_valid(), "free_time means no block")
	block.activity = &"bake"
	block.wage = -1
	assert_false(block.is_valid())
	var routine := BustleScheduleDef.new()
	routine.week_length = 0
	assert_false(routine.is_valid())
	assert_true(BustleScheduleDef.new().is_valid())


func test_an_empty_payer_is_the_employer_of_the_job_held_when_the_shift_was_worked() -> void:
	_jobs.employers[&"smith"] = &"forge_owner"
	_trade.set_balance(&"forge_owner", 100)
	_roster.schedule_of(&"agent_a").attend(300, &"bake")
	_roles.set_holder(&"baker", &"")
	_roles.set_holder(&"smith", &"agent_a")
	var paid := _roster.settle(600, _trade)
	assert_eq([paid[0]["payer"], paid[0]["paid"]], [&"guild", true], "the baker's employer pays the baker's shift")
	assert_eq([_trade.balance(&"guild"), _trade.balance(&"forge_owner")], [92, 100], "the new employer pays nothing for it")
	_roster.schedule_of(&"agent_b").attend(300, &"wander")
	_roles.set_holder(&"baker", &"agent_b")
	assert_eq(_roster.settle(800, _trade).size(), 0, "an unpaid block owes nothing, whoever holds a job later")


func test_an_owed_wage_is_kept_past_the_attendance_window_until_paid() -> void:
	_trade.set_balance(&"guild", 0)
	var schedule := _roster.schedule_of(&"agent_a")
	schedule.attend(250, &"bake")
	_roster.settle(600, _trade)
	for day in range(1, 10):
		schedule.attend(day * DAY + 250, &"bake")
	assert_true(schedule.export_state()["attended"].has("240"), "day 0's owed wage is still there on day 9")
	var unpaid_job := _roster.schedule_of(&"agent_b")
	unpaid_job.attend(650, &"wander")
	unpaid_job.attend(9 * DAY + 650, &"wander")
	assert_false(unpaid_job.export_state()["attended"].has("600"), "history with nothing owed is still trimmed")
	_trade.set_balance(&"guild", 1000)
	var paid := _roster.settle(9 * DAY + 600, _trade)
	assert_eq(paid[0]["start"], 240, "and it is paid first, once there is money")
	assert_eq(paid.size(), 10, "with every other owed shift")
	assert_eq(_trade.balance(&"agent_a"), 80)


func test_no_change_means_no_signal_and_jobs_can_be_edited_later() -> void:
	_roster.add_agent(&"agent_c")
	watch_signals(_roster)
	_roles.set_holder(&"chair", &"agent_c")
	_roles.set_holder(&"chair", &"")
	assert_signal_emit_count(_roster, "schedule_changed", 0, "no job and no routine before or after")
	_jobs.schedules[&"chair"] = _routine(&"preside", 600, 660, 3)
	_jobs.employers[&"chair"] = &"guild"
	_roles.set_holder(&"chair", &"agent_c")
	assert_eq(_roster.job_of(&"agent_c"), &"chair")
	_jobs.schedules[&"chair"] = _routine(&"preside", 540, 660, 3)
	_roster.refresh_all()
	assert_eq(_roster.schedule_of(&"agent_c").block_at(560)["block"].activity, &"preside", "edited routines apply after refresh_all")


func _routine(activity: StringName, start: int, end: int, wage: int) -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = activity
	block.start_minute = start
	block.end_minute = end
	block.wage = wage
	var routine := BustleScheduleDef.new()
	routine.id = activity
	routine.day = BustleScheduleDay.new()
	routine.day.blocks.append(block)
	return routine
