# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Conflict: hostility only from dispositions, bold agents fight and timid ones flee or fetch help
## and then all go back to their schedules, scuffles never kill, lethal fights are rare and emit a
## kill event, quarrels, and saving.

const WORK := &"schedule.work"


## A host's combat in which every lethal fight kills.
class KillingCombat:
	extends BustleCombatPort

	func outcome(id: StringName) -> Dictionary:
		var out := super(id)
		if out.get("lethal", false):
			out["killed"] = true
		return out


var _conflict: BustleConflict
var _people: Dictionary[StringName, BustlePersonality] = {}
var _places: Dictionary[StringName, Vector3] = {}
var _groups: Dictionary[StringName, StringName] = {}


func before_each() -> void:
	var table := BustleDispositionTable.new()
	table.set_group_rule(&"village", &"raiders", BustleDispositionPort.Disposition.HOSTILE)
	table.same_group = BustleDispositionPort.Disposition.FRIENDLY
	_conflict = BustleConflict.new(BustleDispositionPort.new(table), BustleCombatPort.new(), BustleConflictConfig.new(), 5)
	_people = {}
	_places = {}
	_groups = {&"raider": &"raiders"}
	_conflict.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_conflict.group_of = func(id: StringName) -> StringName: return _groups.get(id, &"village")
	_conflict.position_of = func(id: StringName) -> Variant: return _places.get(id)


func test_hostility_comes_only_from_the_disposition_table() -> void:
	var store := BustleSocialStore.new()
	store.add_opinion(&"baker", &"smith", -50.0, {}, 3.0)
	assert_eq(store.opinion(&"baker", &"smith"), 0, "the baker can't stand the smith")
	assert_eq(_conflict.notice(&"baker", &"smith", 0), &"", "but a low opinion is no threat")
	assert_eq(_conflict.notice(&"baker", &"raider", 0), BustleConflict.FLEE, "a hostile group is")
	assert_eq(_conflict.threat_of(&"baker"), &"raider")
	assert_eq(_conflict.notice(&"baker", &"raider", 1), &"", "one conflict at a time")
	var inputs: Dictionary[StringName, float] = {WORK: 1.0}
	_conflict.fill_inputs(&"baker", inputs)
	assert_eq(inputs, {WORK: 1.0, &"threat.fight": 0.0, &"threat.flee": 1.0, &"threat.fetch_help": 0.0} as Dictionary[StringName, float])
	_conflict.clear(&"baker")
	_conflict.fill_inputs(&"baker", inputs)
	assert_eq(inputs, {WORK: 1.0} as Dictionary[StringName, float], "the inputs go with the conflict")


func test_bold_agents_fight_timid_ones_flee_or_fetch_help_then_all_go_back_to_work() -> void:
	_person(&"smith", 90.0, 80.0)
	_person(&"baker", 20.0, 30.0)
	_person(&"miller", 20.0, 30.0)
	_places = {&"raider": Vector3(2, 0, 0), &"baker": Vector3.ZERO, &"miller": Vector3(-2, 0, 0), &"smith": Vector3(6, 0, 0)}
	var watch := []
	_conflict.assaulted.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: watch.append([a, v, c["cause"]]))
	var brains: Dictionary[StringName, BustleBrain] = {}
	for id: StringName in [&"smith", &"baker", &"miller"]:
		brains[id] = _brain(id)
	var everyone: Array[StringName] = [&"smith", &"baker", &"miller"]
	assert_eq(_conflict.notice(&"miller", &"raider", 0), BustleConflict.FLEE, "timid with no ally near: flee")
	assert_eq(_conflict.notice(&"baker", &"raider", 0, everyone), BustleConflict.FETCH_HELP, "timid with an ally near: fetch help")
	assert_eq(_conflict.helper_of(&"baker"), &"smith")
	assert_eq(_tick(brains[&"baker"], 0).goal_id, &"fetch_help")
	assert_eq(brains[&"baker"].last_intent.talk_to, &"smith", "runs to the ally")
	_places[&"baker"] = Vector3(5, 0, 0)
	_tick(brains[&"baker"], 1)
	assert_eq(_conflict.stance_of(&"smith"), BustleConflict.FIGHT, "the ally takes up the fight")
	assert_eq(_tick(brains[&"baker"], 2).goal_id, &"work", "and the timid one goes back to work")
	assert_eq(_tick(brains[&"smith"], 2).goal_id, &"fight", "the bold one fights")
	assert_eq(brains[&"smith"].last_intent.attack_target, &"raider")
	assert_eq(watch, [[&"smith", &"raider", "help"]], "the fight is reported")
	assert_eq(_tick(brains[&"smith"], 3).goal_id, &"work", "then goes back to work")
	var intent := _tick(brains[&"miller"], 0)
	assert_eq(intent.goal_id, &"flee")
	assert_gt(intent.move_to.distance_to(_places[&"raider"]), 9.0, "away from the threat")
	_places[&"miller"] = intent.move_to
	_tick(brains[&"miller"], 1)
	assert_eq(_tick(brains[&"miller"], 2).goal_id, &"work", "safe, it goes back to work")
	for id: StringName in everyone:
		assert_eq(_conflict.threat_of(id), &"", "nobody is still in a conflict")


func test_scuffles_never_kill_and_lethal_fights_are_rare() -> void:
	assert_eq(_conflict.filter_damage(30.0, 10.0, false), 9.0, "a scuffle leaves its victim standing")
	assert_eq(_conflict.filter_damage(30.0, 0.5, false), 0.0)
	assert_eq(_conflict.filter_damage(30.0, 10.0, true), 30.0, "a lethal fight doesn't")
	assert_eq(_conflict.filter_damage(-3.0, 10.0, true), 0.0)
	_conflict.combat = KillingCombat.new()
	var killings := []
	_conflict.killed.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: killings.append(c))
	var lethal := 0
	for i in 500:
		var attacker := StringName("raider_%d" % i)
		_groups[attacker] = &"raiders"
		_person(attacker, 100.0, 100.0)
		assert_eq(_conflict.notice(attacker, &"baker", i), BustleConflict.FIGHT)
		var runner := _runner()
		runner.start(_sequence(&"fight"), attacker, i)
		runner.tick(0.1, i)
		if _conflict.is_lethal(attacker, &"baker", i):
			lethal += 1
	assert_between(lethal, 1, 25, "about 2 in 100 (default)")
	assert_eq(killings.size(), lethal, "only lethal fights kill")


func test_a_forced_lethal_fight_emits_the_kill_event() -> void:
	_conflict.combat = KillingCombat.new()
	_conflict.config.lethal_chance = 1.0
	_person(&"smith", 90.0, 90.0)
	var events := []
	_conflict.assaulted.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: events.append(["assaulted", a, v, c]))
	_conflict.killed.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: events.append(["killed", a, v, c]))
	assert_eq(_conflict.notice(&"smith", &"raider", 42), BustleConflict.FIGHT)
	var runner := _runner()
	runner.start(_sequence(&"fight"), &"smith", 42)
	assert_eq(runner.tick(0.1, 42), BustleSequenceRunner.State.SUCCEEDED)
	var circumstances := {"cause": "hostile", "lethal": true, "killed": true, "at": 42}
	assert_eq(events, [["assaulted", &"smith", &"raider", circumstances], ["killed", &"smith", &"raider", circumstances]])
	assert_eq(_conflict.combat.status(&"smith"), BustleCombatPort.Status.NONE, "disengaged")


func test_quarrels_become_scuffles_without_hostility() -> void:
	_conflict.config.quarrel_chance = 1.0
	_person(&"smith", 50.0, 100.0)
	_person(&"baker", 20.0, 20.0)
	assert_true(_conflict.quarrel(&"smith", &"baker", 10))
	assert_eq([_conflict.stance_of(&"smith"), _conflict.stance_of(&"baker")], [BustleConflict.FIGHT, BustleConflict.FLEE])
	assert_eq(_conflict.disposition.disposition(&"smith", &"village", &"baker", &"village"), BustleDispositionPort.Disposition.FRIENDLY, "nobody became hostile")
	var events := []
	_conflict.assaulted.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: events.append(c))
	var runner := _runner()
	runner.start(_sequence(&"fight"), &"smith", 10)
	runner.tick(0.1, 10)
	assert_eq(events[0]["cause"], "quarrel")
	assert_false(events[0]["killed"])
	_person(&"miller", 50.0, 0.0)
	assert_false(_conflict.quarrel(&"miller", &"smith", 11), "an even temper never comes to blows")


func test_conflicts_save_and_bad_data_changes_nothing() -> void:
	_conflict.notice(&"baker", &"raider", 0)
	var saved: Variant = JSON.parse_string(JSON.stringify(_conflict.export_state()))
	var other := BustleConflict.new()
	assert_true(other.import_state(saved))
	assert_eq([other.threat_of(&"baker"), other.stance_of(&"baker")], [&"raider", BustleConflict.FLEE])
	for bad: Variant in [null, {}, {"conflicts": {"a": {"threat": "b", "stance": "dance", "cause": "", "helper": ""}}}, {"conflicts": {"a": {"threat": "", "stance": "flee", "cause": "", "helper": ""}}}]:
		assert_false(other.import_state(bad), str(bad))
	assert_eq(other.threat_of(&"baker"), &"raider")
	var port := BustleCombatPort.new()
	assert_eq(port.outcome(&"a"), {}, "no outcome before a fight")
	port.engage(&"a", &"b")
	assert_eq(port.outcome(&"a"), {"target": &"b", "lethal": false, "killed": false}, "the default never hurts anyone")


func _person(id: StringName, boldness: float, temper: float) -> void:
	var p := BustlePersonality.new()
	p.set_slider(&"boldness", boldness)
	p.set_slider(&"temper", temper)
	_people[id] = p


func _sequence(action: StringName) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = action
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence


func _runner() -> BustleSequenceRunner:
	var runner := BustleSequenceRunner.new()
	runner.register(&"fight", BustleFightAction.new(_conflict))
	runner.register(&"flee", BustleFleeAction.new(_conflict))
	runner.register(&"fetch_help", BustleFetchHelpAction.new(_conflict))
	return runner


func _brain(id: StringName) -> BustleBrain:
	var library := BustleGoalLibrary.new()
	library.goals = BustleConflict.goal_defs()
	var work := BustleGoalDef.new()
	work.id = &"work"
	work.band = BustleBands.DUTY
	work.preconditions = [{"kind": "input", "input": String(WORK)}]
	work.sequence = _sequence(&"wait")
	work.sequence.steps[0].params = {"minutes": 60}
	library.goals.append(work)
	var brain := BustleBrain.new(id, library, BustleScoringConfig.new(), 3)
	brain.runner.share_handlers_with(_runner())
	return brain


func _tick(brain: BustleBrain, now: int) -> BustleIntent:
	var senses := BustleSenses.new()
	senses.now_minutes = now
	senses.inputs[WORK] = 1.0
	_conflict.fill_inputs(brain.agent_id, senses.inputs)
	return brain.tick(0.1, senses)
