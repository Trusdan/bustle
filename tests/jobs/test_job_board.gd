# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The job board: picking the most wanted job, capability gates, exclusive claims, the work port
## without a board, determinism, and saving. Work types are a tiny generic set.

var _ports: BustlePorts
var _board: BustleJobBoard


func _type(id: StringName, sliders: Dictionary = {}, needs: Dictionary = {}) -> BustleWorkType:
	var def := BustleWorkType.new()
	def.id = id
	for slider: StringName in sliders:
		def.priority_weights[slider] = sliders[slider]
	for input: StringName in needs:
		def.need_weights[input] = needs[input]
	return def


func _seeker(id: StringName, sliders: Dictionary = {}, inputs: Dictionary = {}, tags: Array[StringName] = []) -> BustleJobSeeker:
	var personality := BustlePersonality.new()
	for slider: StringName in sliders:
		personality.set_slider(slider, sliders[slider])
	var typed: Dictionary[StringName, float] = {}
	for input: StringName in inputs:
		typed[input] = inputs[input]
	return BustleJobSeeker.new(id, personality, typed, tags)


func before_each() -> void:
	_ports = BustlePorts.new()
	var skill := BustleSkillDef.new()
	skill.id = &"farming"
	var skills := BustleSkills.new([skill] as Array[BustleSkillDef])
	_ports.skills = skills
	var harvest := _type(&"harvest", {&"diligence": 1.0})
	var errand := _type(&"errand", {}, {&"money": 1.0})
	var mending := _type(&"mending", {&"curiosity": 1.0})
	mending.required_tags = [&"tools"]
	var pruning := _type(&"pruning", {&"diligence": 1.0})
	pruning.skill = &"farming"
	pruning.min_skill = 4.0
	var watch := _type(&"night_watch", {&"boldness": 1.0})
	watch.required_role = &"warden"
	_board = BustleJobBoard.new([harvest, errand, mending, pruning, watch] as Array[BustleWorkType], _ports)


# Acceptance (1): an agent picks the highest-priority job it can do.
func test_an_agent_claims_the_job_it_wants_most() -> void:
	var harvest := _board.post(&"harvest", &"farm", 0)
	var errand := _board.post(&"errand", &"shop", 0)
	var keen := _seeker(&"baker", {&"diligence": 80.0}, {&"money": 0.1})
	assert_eq(_board.best_for(keen), harvest)
	var broke := _seeker(&"baker", {&"diligence": 80.0}, {&"money": 0.9})
	assert_eq(_board.best_for(broke), errand, "a stronger money need swaps the pick")
	var idle := _seeker(&"baker", {&"diligence": 20.0}, {&"money": 0.1})
	assert_eq(_board.best_for(idle), errand, "a low diligence swaps it too")
	assert_eq(_board.assign([keen] as Array[BustleJobSeeker], 5), {&"baker": harvest} as Dictionary[StringName, StringName])
	assert_eq(_board.posting(harvest).claimed_at, 5)


func test_equal_scores_go_to_the_earlier_posting() -> void:
	var ids: Array[StringName] = []
	for i: int in 11:
		ids.append(_board.post(&"harvest", &"farm", 0))
	assert_eq(_board.job_ids()[1], &"job_2", "natural order")
	assert_eq(_board.best_for(_seeker(&"baker")), &"job_1")
	_board.cancel(&"job_1")
	assert_eq(_board.best_for(_seeker(&"baker")), &"job_2", "job_2 before job_10")


# Acceptance (2): incapable agents never claim gated jobs (role, skill or tag).
func test_gates_keep_out_agents_who_cannot_do_the_work() -> void:
	var pruning := _board.post(&"pruning", &"farm", 0)
	var watch := _board.post(&"night_watch", &"town", 0)
	var mending := _board.post(&"mending", &"farm", 0)
	var novice := _seeker(&"baker", {&"diligence": 100.0, &"boldness": 100.0, &"curiosity": 100.0})
	for job: StringName in [pruning, watch, mending]:
		assert_false(_board.can_do(novice, job), job)
		assert_false(_board.claim(novice, job, 0), job)
	assert_eq(_board.best_for(novice), &"")
	assert_true(_board.assign([novice] as Array[BustleJobSeeker], 0).is_empty())
	(_ports.skills as BustleSkills).set_level(&"baker", &"farming", 4.0)
	_ports.roles.set_holder(&"warden", &"baker")
	var able := _seeker(&"baker", {}, {}, [&"tools"] as Array[StringName])
	for job: StringName in [pruning, watch, mending]:
		assert_true(_board.can_do(able, job), job)
	assert_true(_board.claim(able, watch, 0))


func test_a_skill_gate_without_skills_keeps_everyone_out() -> void:
	var board := BustleJobBoard.new([_board.type_of(&"pruning"), _board.type_of(&"harvest")] as Array[BustleWorkType])
	var pruning := board.post(&"pruning", &"farm", 0)
	var harvest := board.post(&"harvest", &"farm", 0)
	assert_false(board.can_do(_seeker(&"baker"), pruning))
	assert_true(board.can_do(_seeker(&"baker"), harvest), "ungated work needs no ports")


# Acceptance (3): two agents never claim one job, even when both pick it in the same tick.
func test_one_posting_goes_to_the_higher_score() -> void:
	var harvest := _board.post(&"harvest", &"farm", 0)
	var keen := _seeker(&"smith", {&"diligence": 90.0})
	var lazy := _seeker(&"baker", {&"diligence": 60.0})
	var claims := _board.assign([lazy, keen] as Array[BustleJobSeeker], 0)
	assert_eq(claims, {&"smith": harvest} as Dictionary[StringName, StringName])
	assert_eq(_board.posting(harvest).claimed_by, &"smith")
	assert_false(_board.claim(lazy, harvest, 0), "not later in the same tick either")
	assert_true(_board.assign([lazy, keen] as Array[BustleJobSeeker], 0).is_empty())


func test_a_tie_goes_to_the_lower_agent_id() -> void:
	var harvest := _board.post(&"harvest", &"farm", 0)
	var claims := _board.assign([_seeker(&"smith"), _seeker(&"baker")] as Array[BustleJobSeeker], 0)
	assert_eq(claims, {&"baker": harvest} as Dictionary[StringName, StringName])


func test_the_loser_takes_the_next_job() -> void:
	var harvest := _board.post(&"harvest", &"farm", 0)
	var errand := _board.post(&"errand", &"shop", 0)
	var keen := _seeker(&"smith", {&"diligence": 90.0})
	var lazy := _seeker(&"baker", {&"diligence": 60.0})
	var claims := _board.assign([keen, lazy] as Array[BustleJobSeeker], 0)
	assert_eq(claims, {&"smith": harvest, &"baker": errand} as Dictionary[StringName, StringName])


func test_one_claim_per_agent_until_it_is_done() -> void:
	var first := _board.post(&"harvest", &"farm", 0)
	var second := _board.post(&"harvest", &"farm", 0)
	var baker := _seeker(&"baker")
	assert_true(_board.claim(baker, first, 0))
	assert_false(_board.claim(baker, second, 0))
	assert_eq(_board.best_for(baker), &"")
	assert_eq(_board.claimed_of(&"baker"), first)
	assert_true(_board.release(first))
	assert_true(_board.posting(first).is_open())
	assert_true(_board.claim(baker, second, 1))
	assert_true(_board.complete(second))
	assert_null(_board.posting(second))
	assert_eq(_board.claimed_of(&"baker"), &"")
	assert_false(_board.complete(first), "an open posting can't be completed")
	assert_false(_board.release(first), "nor released")


func test_postings_expire_and_cancel() -> void:
	var soon := _board.post(&"harvest", &"farm", 0, 60)
	var later := _board.post(&"harvest", &"farm", 0, 120)
	var never := _board.post(&"errand", &"shop", 0)
	assert_eq(_board.post(&"harvest", &"farm", 100, 50), &"", "due before it's posted")
	assert_eq(_board.post(&"weaving", &"farm", 0), &"", "unknown type")
	_board.claim(_seeker(&"baker"), soon, 10)
	assert_eq(_board.expire(59), [] as Array[StringName])
	assert_eq(_board.expire(60), [soon] as Array[StringName], "claimed or not")
	assert_eq(_board.claimed_of(&"baker"), &"")
	assert_true(_board.cancel(later))
	assert_eq(_board.job_ids(), [never] as Array[StringName])


# Acceptance (6): with no board, job_of still works and nothing errors.
func test_the_work_port_without_a_board() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"baker": &"agent_a"}
	var jobs := BustleRoleSchedules.new()
	jobs.schedules = {&"baker": BustleScheduleDef.new()}
	var roster := BustleScheduleRoster.new(BustleRolesPort.new(table), jobs)
	roster.add_agent(&"agent_a", BustleScheduleDef.new())
	var port := BustleWorkPort.new(roster)
	assert_eq(port.job_of(&"agent_a"), &"baker")
	assert_false(port.can_do(&"agent_a", &"job_1"))
	assert_eq(port.claimed_of(&"agent_a"), &"")
	assert_eq(BustlePorts.new().work.claimed_of(&"agent_a"), &"")
	assert_push_error_count(0)
	port.board = _board
	assert_eq(port.job_of(&"agent_a"), &"baker", "a board leaves standing jobs alone")
	var job := _board.post(&"harvest", &"farm", 0)
	assert_true(port.can_do(&"agent_a", job))
	_board.claim(_seeker(&"agent_a"), job, 0)
	assert_eq(port.claimed_of(&"agent_a"), job)


# Acceptance (7): the same postings, agents and clock give the same claims.
func test_same_inputs_give_the_same_claims() -> void:
	var runs: Array = []
	for run: int in 2:
		before_each()
		for i: int in 6:
			_board.post([&"harvest", &"errand"][i % 2], &"farm", i * 10, 500)
		var seekers: Array[BustleJobSeeker] = []
		for i: int in 8:
			seekers.append(_seeker(StringName("agent_%d" % i), {&"diligence": 40.0 + 7.0 * i}, {&"money": 0.1 * (i % 4)}))
		var claims := _board.assign(seekers, 60)
		runs.append([claims, _board.export_state()])
	assert_eq(runs[0], runs[1])
	assert_eq(runs[0][0].size(), 6, "six postings, six claims")


func test_save_round_trip() -> void:
	var a := _board.post(&"harvest", &"farm", 0, 300, &"field")
	_board.post(&"errand", &"shop", 10)
	_board.claim(_seeker(&"baker"), a, 20)
	var saved: Variant = JSON.parse_string(JSON.stringify(_board.export_state()))
	var copy := BustleJobBoard.new([_board.type_of(&"harvest"), _board.type_of(&"errand")] as Array[BustleWorkType])
	assert_true(copy.import_state(saved))
	assert_eq(copy.export_state(), _board.export_state())
	assert_eq(copy.claimed_of(&"baker"), a)
	assert_eq(copy.posting(a).place, &"field")
	assert_eq(copy.post(&"harvest", &"farm", 30), &"job_3", "ids carry on")


func test_import_refuses_bad_data_and_changes_nothing() -> void:
	var job := _board.post(&"harvest", &"farm", 0)
	_board.claim(_seeker(&"baker"), job, 0)
	var before := _board.export_state()
	var row: Dictionary = before["postings"][0]
	var bad: Array = [null, {}, {"next": 2}, {"next": "2", "postings": []}, {"next": 0, "postings": []},
		{"next": 1, "postings": [row]}, {"next": 5, "postings": [row, row]},
		{"next": 5, "postings": [_with(row, "type", "weaving")]},
		{"next": 5, "postings": [_with(row, "opened", "noon")]},
		{"next": 5, "postings": [_with(row, "claimed_at", -1)]},
		{"next": 5, "postings": [row, _with(row, "id", "job_3")]},
		{"next": 5, "postings": ["job_1"]}]
	for saved: Variant in bad:
		assert_false(_board.import_state(saved), str(saved))
		assert_eq(_board.export_state(), before, str(saved))


func test_invalid_types_are_refused() -> void:
	assert_false(_board.add_type(_type(&"harvest")), "id taken")
	var bad := _type(&"sorting", {&"charm": 1.0})
	assert_false(_board.add_type(bad))
	var gated := _type(&"sorting")
	gated.min_skill = 2.0
	assert_false(_board.add_type(gated), "a skill minimum needs a skill")
	assert_false(_board.add_type(null))


static func _with(row: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := row.duplicate()
	out[key] = value
	return out
