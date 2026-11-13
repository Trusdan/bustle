# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The colony with a job board: settlers weigh postings against their other free-time goals, take
## the one they want most, never take gated work they can't do, and never share one. Wages and
## practice follow completed work, and the same seed gives the same timeline.

const Colony := preload("res://demo/colony/colony.gd")
const A := Colony.SETTLER_A
const B := Colony.SETTLER_B
const C := Colony.SETTLER_C
const D := Colony.SETTLER_D
## 15:00 on the first day, during field duty, so nobody can take a posting before duty ends.
const POST_AT := 900
const DAY := 1440


# A colony with a board and the demo work types. [param sliders]: settler → [diligence, curiosity].
func _colony(sliders: Dictionary, menders: Array[StringName] = [], skills: BustleSkills = null) -> Array:
	var ports := BustlePorts.new()
	ports.trade.set_balance(&"store", 100)
	for id: StringName in menders:
		ports.roles.set_holder(&"mender", id)
	if skills != null:
		ports.skills = skills
	var board := BustleJobBoard.new(Colony.work_types(), ports)
	var run := Colony.build(1, Colony.MODULES, false, board)
	for id: StringName in Colony.SETTLERS:
		var pair: Array = sliders.get(id, [0.0, 0.0])
		run.personality_of(id).set_slider(&"diligence", pair[0])
		run.personality_of(id).set_slider(&"curiosity", pair[1])
	run.run(POST_AT - run.now)
	return [run, board, ports]


# Posting id → who claimed it, from the timeline, in order.
static func _claims(run: RefCounted, what: String = "claimed") -> Array:
	var out: Array = []
	for entry: Dictionary in run.timeline.entries():
		if entry["kind"] == "job" and entry["payload"]["what"] == what:
			out.append([entry["payload"]["job"], entry["agent"]])
	return out


# Acceptance (1) and (4): a settler takes the posting it wants most.
func test_settlers_take_the_job_they_want_most() -> void:
	var made := _colony({A: [90.0, 60.0], B: [0.0, 80.0]})
	var run: RefCounted = made[0]
	var board: BustleJobBoard = made[1]
	var harvest := board.post(&"harvest", &"store", run.now, DAY)
	var errand := board.post(&"errand", &"store", run.now, DAY)
	run.run(DAY - run.now)
	assert_eq(_claims(run), [[String(harvest), String(A)], [String(errand), String(B)]])
	var swapped := _colony({A: [0.0, 80.0], B: [90.0, 60.0]})
	run = swapped[0]
	board = swapped[1]
	harvest = board.post(&"harvest", &"store", run.now, DAY)
	errand = board.post(&"errand", &"store", run.now, DAY)
	run.run(DAY - run.now)
	assert_eq(_claims(run), [[String(harvest), String(B)], [String(errand), String(A)]], "swapping sliders swaps the picks")


func test_settlers_who_dislike_the_work_do_something_else() -> void:
	var made := _colony({})
	var run: RefCounted = made[0]
	var board: BustleJobBoard = made[1]
	board.post(&"harvest", &"store", run.now, DAY)
	run.run(DAY - run.now)
	assert_true(_claims(run).is_empty(), "every slider at 0: it appeals 0, so other goals win")
	assert_eq(board.job_ids(true).size(), 1, "still posted: the board never leaves it out")


# Acceptance (2) and (4): settlers without the role never claim gated work.
func test_gated_work_goes_only_to_a_settler_who_can_do_it() -> void:
	var made := _colony({A: [100.0, 50.0], B: [100.0, 50.0], C: [50.0, 50.0]}, [C] as Array[StringName])
	var run: RefCounted = made[0]
	var board: BustleJobBoard = made[1]
	var mending := board.post(&"mending", &"store", run.now, DAY)
	run.run(DAY - run.now)
	assert_eq(_claims(run), [[String(mending), String(C)]], "the keener settlers without the role never claim it")


# Acceptance (3) and (4): two settlers who pick one posting in the same tick never share it.
func test_one_posting_picked_by_two_goes_to_the_keener() -> void:
	var made := _colony({A: [80.0, 0.0], B: [90.0, 0.0]})
	var run: RefCounted = made[0]
	var board: BustleJobBoard = made[1]
	var harvest := board.post(&"harvest", &"store", run.now, DAY)
	var picked: Array[StringName] = []
	while run.now < DAY:
		var at: int = run.now
		var intents: Dictionary = run.step()
		for id: StringName in [A, B]:
			if intents[id].option_id == harvest and not picked.has(id):
				picked.append(id)
				assert_eq(at, 960, "both pick it as duty ends")
	assert_eq(picked, [A, B] as Array[StringName], "both wanted it")
	assert_eq(_claims(run), [[String(harvest), String(B)]], "one claim, by the higher score")


func test_completed_work_pays_once_and_is_practised() -> void:
	var farming := BustleSkillDef.new()
	farming.id = &"farming"
	var skills := BustleSkills.new([farming] as Array[BustleSkillDef])
	var made := _colony({A: [90.0, 0.0]}, [], skills)
	var run: RefCounted = made[0]
	var board: BustleJobBoard = made[1]
	var ports: BustlePorts = made[2]
	var harvest := board.post(&"harvest", &"store", run.now, DAY)
	run.run(DAY - run.now)
	assert_eq(_claims(run, "paid"), [[String(harvest), String(A)]])
	assert_eq(ports.trade.balance(A), 6)
	assert_eq(ports.trade.balance(&"store"), 94)
	assert_almost_eq(skills.xp_of(A, &"farming"), 15.0, 1e-9, "10 XP an hour for 90 minutes")


# Acceptance (7) in the demo: the same seed and postings give the same timeline.
func test_the_same_run_gives_the_same_timeline() -> void:
	var hashes: Array[String] = []
	for i: int in 2:
		var made := _colony({A: [80.0, 60.0], B: [90.0, 20.0], C: [40.0, 90.0]}, [D] as Array[StringName])
		var run: RefCounted = made[0]
		var board: BustleJobBoard = made[1]
		for type: StringName in [&"harvest", &"errand", &"mending", &"harvest"]:
			board.post(type, &"store", run.now, 2 * DAY)
		run.run(2 * DAY - run.now)
		assert_false(_claims(run).is_empty())
		hashes.append(run.timeline.hash())
	assert_eq(hashes[0], hashes[1])
