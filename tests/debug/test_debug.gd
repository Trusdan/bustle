# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The debug tools: the inspector reads the scorer's own numbers, the console commands, unknown and
## removed agents, malformed input, the overlay costing nothing when off, and the release gate.


var _society: BustleSociety
var _console: BustleDebugConsole


func before_each() -> void:
	BustleDebug.debug_build_override = true
	_society = BustleSociety.new(3)
	var library := BustleGoalLibrary.new()
	for spec: Array in [[&"rest", &"need.sleep", 0.9], [&"eat", &"need.food", 0.8],
			[&"chat", &"need.company", 0.5], [&"walk", &"need.company", 0.2]]:
		library.goals.append(_goal(spec[0], spec[1], spec[2]))
	_society.register_archetype(&"villager", library)
	_society.add_agent(&"ann", &"villager")
	_society.add_agent(&"bo", &"villager")
	_console = BustleDebugConsole.new(_society)
	_console.sequences[&"fetch"] = _sequence(5)


func after_each() -> void:
	BustleDebug.debug_build_override = null


func _sequence(minutes: int) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = &"wait"
	step.params = {"minutes": minutes}
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _goal(id: StringName, input: StringName, weight: float) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.PERSONAL
	goal.base_weight = weight
	var consideration := BustleConsideration.new()
	consideration.input = input
	consideration.curve = Curve.new()
	consideration.curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	consideration.curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	goal.considerations.append(consideration)
	goal.sequence = _sequence(30)
	return goal


func _tick(id: StringName, now: int = 0) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	senses.inputs = {&"need.sleep": 0.2, &"need.food": 0.5, &"need.company": 0.6, &"trait.calm": 0.3}
	return _society.get_agent(id).brain.tick(0.1, senses)


func test_the_snapshot_shows_the_scorers_own_numbers_and_marks_missing_modules() -> void:
	var intent := _tick(&"ann")
	var snap := BustleInspector.new().snapshot(_society, &"ann")
	var brain := _society.get_agent(&"ann").brain
	assert_eq([snap["goal"], snap["band"], snap["missing"]], [intent.goal_id, "PERSONAL", false])
	assert_eq(snap["step"], {"index": 0, "action": &"wait", "state": "RUNNING"})
	var best := brain.last_candidates.filter(func(c: BustleCandidate) -> bool: return c.eligible)
	assert_eq(snap["top"].size(), 3)
	for i in 3:
		assert_eq(snap["top"][i]["goal"], best[i].goal_id)
		assert_eq(snap["top"][i]["raw"], best[i].raw_score, "exactly the scorer's number")
		assert_eq(snap["top"][i]["selection"], best[i].selection_score)
	for field: String in ["ring", "memory", "schedule"]:
		assert_eq(snap[field]["available"], false, "%s is marked unavailable" % field)
	assert_eq(snap["needs"], {"available": false, "module": "needs",
		"inputs": {&"need.company": 0.6, &"need.food": 0.5, &"need.sleep": 0.2}})


func test_the_breakdown_equals_the_candidates_reasons() -> void:
	_tick(&"ann")
	var brain := _society.get_agent(&"ann").brain
	var candidate: BustleCandidate = brain.last_candidates.filter(func(c: BustleCandidate) -> bool: return c.goal_id == &"eat")[0]
	var detail := BustleInspector.breakdown(brain, &"eat")
	assert_eq([detail["raw"], detail["reasons"]], [candidate.raw_score, candidate.reasons])
	assert_almost_eq(detail["raw"], 0.8 * 0.5, 1e-6)
	assert_false(BustleInspector.breakdown(brain, &"swim")["found"])


func test_why_need_and_order_work_headless() -> void:
	_tick(&"ann")
	var why := _console.run("why ann")
	assert_string_starts_with(why, "eat PERSONAL raw 0.4000 selection 0.4000")
	assert_string_contains(_console.run("why ann chat"), "chat PERSONAL: raw 0.3000, selection 0.3000, eligible")
	assert_eq(_console.run("why ann swim"), "no candidate swim on the last tick")
	assert_eq(_console.run("need ann"),
		"needs module not installed; last need inputs: need.company 0.60, need.food 0.50, need.sleep 0.20")
	assert_eq(_console.run("need ann food 1"), "needs can't be set: the needs module isn't installed")
	assert_eq(_console.run("order ann"), "no orders")
	assert_eq(_console.run("order ann fetch"), "queued console_1")
	assert_eq(_console.run("order ann fetch forced"), "queued console_2")
	var intent := _tick(&"ann", 1)
	assert_eq(intent.order_id, &"console_1", "the real queue runs it, first in, first out")
	assert_eq(_console.run("order ann"), "console_1 (active), console_2 forced")
	assert_eq(_console.run("order ann cancel console_2"), "cancelled console_2")
	assert_eq(_console.run("order ann cancel console_2"), "no order console_2")
	assert_eq(_console.run("order ann dance"), "no sequence dance")


func test_unknown_agents_malformed_input_and_removed_agents_are_answered() -> void:
	assert_eq(_console.run("why nobody"), "no agent nobody")
	assert_eq(_console.run("why bo"), "bo hasn't thought yet")
	for line: String in ["", "   ", "why", "why ann a b c", "need", "order", "order ann fetch now", "order ann cancel"]:
		assert_eq(_console.run(line), BustleDebugConsole.USAGE, "usage for '%s'" % line)
	assert_string_starts_with(_console.run("fly ann"), "unknown command: fly")
	assert_eq(_console.run("agents"), "ann, bo")
	var empty := BustleDebugConsole.new(_society)
	assert_eq(empty.run("order ann fetch"), "no sequences registered")
	_tick(&"ann")
	_society.remove_agent(&"ann")
	assert_eq(BustleInspector.new().snapshot(_society, &"ann"), {"agent": &"ann", "missing": true})
	assert_eq(_console.run("why ann"), "no agent ann")


func test_the_overlay_works_only_while_enabled_and_drops_removed_agents() -> void:
	var overlay := BustleDebugOverlay.new()
	overlay.society = _society
	add_child_autofree(overlay)
	var body := Node3D.new()
	add_child_autofree(body)
	_society.get_agent(&"ann").attach_body(body)
	_tick(&"ann")
	assert_false(overlay.is_processing(), "off by default")
	overlay.refresh()
	await wait_process_frames(3)
	assert_eq([overlay.label_count(), overlay.inspector.snapshots_taken], [0, 0], "no work while off")
	overlay.enabled = true
	await wait_process_frames(3)
	assert_true(overlay.is_processing())
	assert_eq(overlay.label_count(), 1)
	assert_gt(overlay.inspector.snapshots_taken, 0)
	_society.remove_agent(&"ann")
	overlay.refresh()
	assert_eq(overlay.label_count(), 0, "a removed agent loses its label")
	overlay.enabled = false
	var taken := overlay.inspector.snapshots_taken
	await wait_process_frames(3)
	assert_false(overlay.is_processing())
	assert_eq(overlay.inspector.snapshots_taken, taken, "inspection stops when disabled")


func test_release_builds_expose_nothing() -> void:
	BustleDebug.debug_build_override = false
	assert_eq(_console.run("why ann"), BustleDebugConsole.NOT_AVAILABLE)
	assert_eq(_console.run("order ann fetch"), BustleDebugConsole.NOT_AVAILABLE)
	assert_eq(_society.get_agent(&"ann").brain.orders.ids(), [], "nothing was queued")
	var overlay := BustleDebugOverlay.new()
	add_child_autofree(overlay)
	overlay.enabled = true
	assert_false(overlay.enabled)
	assert_false(overlay.is_processing())
