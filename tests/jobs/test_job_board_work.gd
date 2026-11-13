# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The job board with a brain and a host: advertisements, requests settled at the end of a tick,
## work with practice, wages on completion, missing ports, and the import checks.

var _ports: BustlePorts
var _skills: BustleSkills
var _board: BustleJobBoard


func _seeker(id: StringName, diligence: float = 50.0) -> BustleJobSeeker:
	var personality := BustlePersonality.new()
	personality.set_slider(&"diligence", diligence)
	return BustleJobSeeker.new(id, personality)


func before_each() -> void:
	_ports = BustlePorts.new()
	var farming := BustleSkillDef.new()
	farming.id = &"farming"
	_skills = BustleSkills.new([farming] as Array[BustleSkillDef])
	_ports.skills = _skills
	_ports.trade.set_balance(&"farm", 20)
	var harvest := BustleWorkType.new()
	harvest.id = &"harvest"
	harvest.skill = &"farming"
	harvest.priority_weights[&"diligence"] = 1.0
	harvest.wage = 8
	harvest.minutes = 90
	var watch := BustleWorkType.new()
	watch.id = &"watch"
	watch.required_role = &"warden"
	_board = BustleJobBoard.new([harvest, watch] as Array[BustleWorkType], _ports)


func test_advertise_offers_what_the_agent_can_claim() -> void:
	var first := _board.post(&"harvest", &"farm", 0)
	var second := _board.post(&"harvest", &"farm", 0)
	_board.post(&"watch", &"town", 0)
	var senses := BustleSenses.new()
	assert_eq(_board.advertise(_seeker(&"baker", 70.0), senses), 2, "not the gated one")
	var ad: BustleAdvertisement = senses.advertisements[0]
	assert_eq(ad.option_id, first)
	assert_almost_eq(ad.relief[BustleJobBoard.NEED], 0.7, 1e-9, "0.5 + 0.2")
	assert_eq(ad.tags, [BustleJobBoard.TAG] as Array[StringName])
	assert_eq(senses.inputs[&"need.job"], 1.0)
	_board.claim(_seeker(&"baker"), second, 0)
	senses = BustleSenses.new()
	assert_eq(_board.advertise(_seeker(&"baker", 70.0), senses), 1)
	assert_eq(senses.advertisements[0].option_id, second, "only the one it holds")


func test_disliked_work_is_ranked_not_left_out() -> void:
	_board.post(&"harvest", &"farm", 0)
	var senses := BustleSenses.new()
	assert_eq(_board.advertise(_seeker(&"baker", 0.0), senses), 1)
	assert_eq(senses.advertisements[0].relief[BustleJobBoard.NEED], 0.0)
	_board.appeal_base = 0.8
	assert_almost_eq(_board.appeal(_seeker(&"baker", 0.0), &"job_1"), 0.3, 1e-9, "configurable")
	assert_eq(_board.appeal(_seeker(&"baker", 100.0), &"job_1"), 1.0, "clamped")


func test_a_brain_weighs_a_job_against_its_other_goals() -> void:
	var library := BustleGoalLibrary.new()
	var take := BustleGoalDef.new()
	take.id = &"take_job"
	take.band = BustleBands.PERSONAL
	take.uses_advertisements = true
	var rest := BustleGoalDef.new()
	rest.id = &"rest"
	rest.band = BustleBands.PERSONAL
	rest.base_weight = 0.4
	library.goals = [take, rest]
	var job := _board.post(&"harvest", &"farm", 0)
	var picks: Array[StringName] = []
	for diligence: float in [80.0, 30.0]:
		var senses := BustleSenses.new()
		_board.advertise(_seeker(&"baker", diligence), senses)
		var brain := BustleBrain.new(&"baker", library, BustleScoringConfig.new(), 1)
		var intent := brain.tick(60.0, senses)
		picks.append(StringName("%s:%s" % [intent.goal_id, intent.option_id]))
	assert_eq(picks, [StringName("take_job:" + String(job)), &"rest:"] as Array[StringName],
			"keen (0.8) beats resting (0.4); reluctant (0.3) doesn't")


func test_settle_gives_a_posting_to_the_highest_score() -> void:
	var job := _board.post(&"harvest", &"farm", 0)
	_board.request(_seeker(&"baker", 60.0), job)
	_board.request(_seeker(&"smith", 90.0), job)
	_board.request(_seeker(&"cook", 90.0), job)
	assert_eq(_board.settle(30), {&"cook": job} as Dictionary[StringName, StringName], "a tie goes to the lower id")
	assert_eq(_board.posting(job).claimed_at, 30)
	assert_true(_board.settle(40).is_empty(), "requests are cleared")
	_board.request(_seeker(&"smith"), job)
	assert_true(_board.settle(50).is_empty(), "already claimed")


func test_settle_ignores_requests_that_fail_the_gates() -> void:
	var watch := _board.post(&"watch", &"town", 0)
	_board.request(_seeker(&"baker"), watch)
	_board.request(_seeker(&"baker"), &"job_99")
	assert_true(_board.settle(0).is_empty())
	assert_eq(_board.claimed_of(&"baker"), &"")


func test_work_adds_progress_and_practice_then_completes_and_pays_once() -> void:
	var job := _board.post(&"harvest", &"farm", 0)
	var baker := _seeker(&"baker")
	assert_false(_board.work(baker, 30), "no claim yet")
	_board.claim(baker, job, 0)
	assert_true(_board.work(baker, 60))
	assert_eq(_board.posting(job).progress, 60)
	assert_almost_eq(_skills.xp_of(&"baker", &"farming"), 10.0, 1e-9)
	assert_false(_board.work(baker, 0))
	watch_signals(_board)
	assert_true(_board.work(baker, 60))
	assert_null(_board.posting(job), "done after 90 minutes")
	assert_almost_eq(_skills.xp_of(&"baker", &"farming"), 15.0, 1e-9, "only the 30 minutes left count")
	assert_eq(_ports.trade.balance(&"baker"), 8)
	assert_eq(_ports.trade.balance(&"farm"), 12)
	assert_signal_emitted_with_parameters(_board, "changed", [job, &"paid", &"baker"])
	assert_false(_board.work(baker, 30), "nothing left to work on")
	assert_eq(_ports.trade.balance(&"baker"), 8, "paid once")


func test_a_wage_the_employer_cannot_pay_is_not_paid() -> void:
	_ports.trade.set_balance(&"farm", 3)
	var job := _board.post(&"harvest", &"farm", 0)
	_board.claim(_seeker(&"baker"), job, 0)
	watch_signals(_board)
	assert_true(_board.complete(job))
	assert_signal_emitted_with_parameters(_board, "changed", [job, &"unpaid", &"baker"])
	assert_eq(_ports.trade.balance(&"baker"), 0)
	assert_eq(_ports.trade.balance(&"farm"), 3)


func test_released_cancelled_or_expired_work_pays_nothing() -> void:
	var released := _board.post(&"harvest", &"farm", 0)
	var cancelled := _board.post(&"harvest", &"farm", 0)
	var expired := _board.post(&"harvest", &"farm", 0, 100)
	_board.claim(_seeker(&"baker"), released, 0)
	_board.work(_seeker(&"baker"), 30)
	_board.release(released)
	assert_eq(_board.posting(released).progress, 30, "work done stays done")
	_board.claim(_seeker(&"smith"), cancelled, 0)
	_board.cancel(cancelled)
	_board.claim(_seeker(&"cook"), expired, 0)
	_board.expire(100)
	for id: StringName in [&"baker", &"smith", &"cook"]:
		assert_eq(_ports.trade.balance(id), 0, id)
		assert_eq(_board.claimed_of(id), &"", id)
	assert_eq(_ports.trade.balance(&"farm"), 20)


func test_work_without_a_skill_port_that_practises() -> void:
	_ports.skills = BustleSkillSet.new()
	var job := _board.post(&"harvest", &"farm", 0)
	_board.claim(_seeker(&"baker"), job, 0)
	assert_true(_board.work(_seeker(&"baker"), 90))
	assert_eq(_ports.trade.balance(&"baker"), 8)
	assert_push_error_count(0)


# Review notes: a null port counts as no port; claims are indexed.
func test_null_ports_count_as_none() -> void:
	var watch := _board.post(&"watch", &"town", 0)
	var harvest := _board.post(&"harvest", &"farm", 0)
	_ports.roles = null
	_ports.skills = null
	_ports.trade = null
	assert_false(_board.can_do(_seeker(&"baker"), watch))
	assert_true(_board.claim(_seeker(&"baker"), harvest, 0))
	assert_true(_board.work(_seeker(&"baker"), 90), "no practice, no wage, no error")
	assert_push_error_count(0)


func test_import_restores_claims_and_progress_and_refuses_bad_times() -> void:
	var job := _board.post(&"harvest", &"farm", 10, 500)
	_board.claim(_seeker(&"baker"), job, 20)
	_board.work(_seeker(&"baker"), 40)
	var saved: Variant = JSON.parse_string(JSON.stringify(_board.export_state()))
	var copy := BustleJobBoard.new([_board.type_of(&"harvest")] as Array[BustleWorkType])
	assert_true(copy.import_state(saved))
	assert_eq(copy.claimed_of(&"baker"), job)
	assert_eq(copy.posting(job).progress, 40)
	var before := copy.export_state()
	var row: Dictionary = before["postings"][0]
	for change: Array in [["due", 5], ["claimed_at", 5], ["progress", -1], ["progress", "lots"]]:
		var bad := row.duplicate()
		bad[change[0]] = change[1]
		assert_false(copy.import_state({"next": 5, "postings": [bad]}), str(change))
		assert_eq(copy.export_state(), before, str(change))


func test_saved_progress_past_the_type_never_goes_backwards() -> void:
	var job := _board.post(&"harvest", &"farm", 0)
	_board.claim(_seeker(&"baker"), job, 0)
	_board.posting(job).progress = 120
	assert_true(_board.work(_seeker(&"baker"), 30))
	assert_null(_board.posting(job), "completed")
	assert_eq(_skills.xp_of(&"baker", &"farming"), 0.0, "no practice, and none taken away")
	assert_eq(_ports.trade.balance(&"baker"), 8)
