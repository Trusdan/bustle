# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Conflict: hostility only from dispositions; bold agents fight and timid ones flee or fetch help,
## then all go back to their schedules; nothing left to chance (every fight has a cause, every
## intent to kill a reason); escalation mid-fight; quarrels against a threshold; kill events with
## their cause; and saving.

const WORK := &"schedule.work"
const CONFLICT_DIR := "res://addons/bustle/core/conflict/"


## A host's combat in which a fight to kill kills, and with [member always] any fight does.
class KillingCombat:
	extends BustleCombatPort
	var always := false

	func outcome(id: StringName) -> Dictionary:
		var out := super(id)
		if not out.is_empty() and (always or out["intent"] == BustleConflict.KILL):
			out["killed"] = true
		return out


## A host's combat whose fights last until [member done], recording each engage.
class SlowCombat:
	extends BustleCombatPort
	var done := false
	var engaged: Array = []

	func engage(id: StringName, target: StringName, intent: StringName = &"subdue") -> void:
		super(id, target, intent)
		engaged.append([id, target, intent])

	func status(id: StringName) -> Status:
		var s := super(id)
		return s if done or s == Status.NONE else Status.ENGAGED


## A host's health in which [member threatened] lives are in danger.
class Health:
	extends BustleHealthPort
	var threatened: Array[StringName] = []

	func is_life_threatened(id: StringName) -> bool:
		return threatened.has(id)


class FakeMood:
	extends RefCounted
	var mood: float = 50.0


var _conflict: BustleConflict
var _health: Health
var _people: Dictionary[StringName, BustlePersonality] = {}
var _places: Dictionary[StringName, Vector3] = {}
var _groups: Dictionary[StringName, StringName] = {}
var _moods: Dictionary[StringName, FakeMood] = {}


func before_each() -> void:
	var table := BustleDispositionTable.new()
	table.set_group_rule(&"village", &"raiders", BustleDispositionPort.Disposition.HOSTILE)
	table.same_group = BustleDispositionPort.Disposition.FRIENDLY
	_health = Health.new()
	_conflict = BustleConflict.new(BustleDispositionPort.new(table), BustleCombatPort.new(), BustleConflictConfig.new(), _health)
	_people = {}
	_places = {}
	_moods = {}
	_groups = {&"raider": &"raiders"}
	_conflict.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_conflict.group_of = func(id: StringName) -> StringName: return _groups.get(id, &"village")
	_conflict.position_of = func(id: StringName) -> Variant: return _places.get(id)
	_conflict.mood_of = func(id: StringName) -> Object: return _moods.get(id)


func test_nothing_in_conflict_is_left_to_chance() -> void:
	var dir := DirAccess.open(CONFLICT_DIR)
	var checked := 0
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(CONFLICT_DIR + file)
		for word: String in ["RandomNumberGenerator", "randf", "randi"]:
			assert_false(text.contains(word), "%s uses %s" % [file, word])
		checked += 1
	assert_eq(checked, 5, "every conflict script was read")


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
	assert_eq(watch, [[&"smith", &"raider", "help"]], "the fight is reported, with its cause")
	assert_eq(_tick(brains[&"smith"], 3).goal_id, &"work", "then goes back to work")
	var intent := _tick(brains[&"miller"], 0)
	assert_eq(intent.goal_id, &"flee")
	assert_gt(intent.move_to.distance_to(_places[&"raider"]), 10.0, "away from the threat, past the safe distance")
	_places[&"miller"] = intent.move_to
	_tick(brains[&"miller"], 1)
	assert_eq(_tick(brains[&"miller"], 2).goal_id, &"work", "safe, it goes back to work")
	for id: StringName in everyone:
		assert_eq(_conflict.threat_of(id), &"", "nobody is still in a conflict")


func test_a_fetcher_whose_ally_is_busy_flees_instead() -> void:
	_person(&"baker", 20.0, 30.0)
	_person(&"smith", 20.0, 30.0)
	_places = {&"raider": Vector3(2, 0, 0), &"baker": Vector3.ZERO, &"smith": Vector3(6, 0, 0), &"wolf": Vector3(9, 0, 0)}
	_groups[&"wolf"] = &"raiders"
	var brain := _brain(&"baker")
	assert_eq(_conflict.notice(&"baker", &"raider", 0, [&"smith"] as Array[StringName]), BustleConflict.FETCH_HELP)
	assert_eq(_tick(brain, 0).goal_id, &"fetch_help")
	_conflict.notice(&"smith", &"wolf", 1)
	_tick(brain, 1)
	assert_eq(_conflict.stance_of(&"baker"), BustleConflict.FLEE, "the ally has trouble of its own")
	assert_eq(_conflict.threat_of(&"baker"), &"raider", "and the threat is still there")
	assert_eq(_tick(brain, 2).goal_id, &"flee", "so it flees, not back to work beside the threat")


func test_fleeing_ends_when_the_body_stops_a_little_short() -> void:
	_places = {&"raider": Vector3.ZERO, &"baker": Vector3(1, 0, 0)}
	_conflict.notice(&"baker", &"raider", 0)
	var runner := _runner()
	runner.start(_sequence(&"flee"), &"baker", 0)
	assert_eq(runner.tick(0.1, 0), BustleSequenceRunner.State.RUNNING)
	var target: Vector3 = runner.context.output["move_to"]
	assert_almost_eq(target.x, 12.0, 1e-4, "aimed past the 10 m safe distance")
	_places[&"baker"] = target - Vector3(1, 0, 0)
	assert_eq(runner.tick(0.1, 1), BustleSequenceRunner.State.SUCCEEDED, "a body that stops 1 m short is safe")
	assert_eq(_conflict.threat_of(&"baker"), &"")


func test_with_no_reason_to_kill_nobody_is_killed() -> void:
	assert_eq(_conflict.filter_damage(30.0, 10.0, BustleConflict.SUBDUE), 9.0, "subduing leaves its victim standing")
	assert_eq(_conflict.filter_damage(30.0, 0.5, BustleConflict.SUBDUE), 0.0)
	assert_eq(_conflict.filter_damage(30.0, 10.0, BustleConflict.KILL), 30.0, "a fight to kill doesn't")
	assert_eq(_conflict.filter_damage(-3.0, 10.0, BustleConflict.KILL), 0.0)
	_conflict.combat = KillingCombat.new()
	var killings := []
	var fights := [0]
	_conflict.killed.connect(func(_a: StringName, _v: StringName, c: Dictionary) -> void: killings.append(c))
	_conflict.assaulted.connect(func(_a: StringName, _v: StringName, c: Dictionary) -> void:
		fights[0] += 1
		assert_eq([c["intent"], c["intent_reason"]], ["subdue", "none"]))
	for i in 200:
		var attacker := StringName("raider_%d" % i)
		_groups[attacker] = &"raiders"
		_person(attacker, 100.0, 100.0)
		assert_eq(_conflict.notice(attacker, &"baker", i), BustleConflict.FIGHT)
		var runner := _runner()
		runner.start(_sequence(&"fight"), attacker, i)
		runner.tick(0.1, i)
	assert_eq(fights[0], 200, "200 fights")
	assert_eq(killings, [], "and with no reason to kill, no kills")


func test_defending_ones_life_is_a_reason_to_kill() -> void:
	_person(&"smith", 90.0, 90.0)
	_conflict.lethal_reason_of = func(agent: StringName, _threat: StringName, _cause: StringName) -> StringName:
		return &"raid" if agent == &"raider" else &""
	_groups[&"smith"] = &"village"
	_conflict.notice(&"raider", &"smith", 0)
	assert_eq([_conflict.intent_of(&"raider"), _conflict.intent_reason_of(&"raider")], [BustleConflict.KILL, &"raid"])
	_conflict.notice(&"smith", &"raider", 0)
	assert_eq([_conflict.intent_of(&"smith"), _conflict.intent_reason_of(&"smith")], [BustleConflict.SUBDUE, BustleConflict.NO_REASON], "a threat to kill alone isn't enough")
	_health.threatened = [&"smith"]
	assert_eq(_conflict.update_intent(&"smith"), BustleConflict.KILL, "with its life in danger, it is")
	assert_eq(_conflict.intent_reason_of(&"smith"), BustleConflict.DEFEND_LIFE)
	_health.threatened = []
	_conflict.update_intent(&"smith")
	_conflict.cornered_of = func(agent: StringName, threat: StringName) -> bool: return agent == &"smith" and threat == &"raider"
	assert_eq(_conflict.update_intent(&"smith"), BustleConflict.KILL, "and so is being cornered")
	assert_eq(_conflict.intent_reason_of(&"smith"), BustleConflict.DEFEND_LIFE)


func test_a_host_reason_to_kill_is_carried_into_the_kill_event() -> void:
	_conflict.combat = KillingCombat.new()
	_person(&"smith", 90.0, 90.0)
	_conflict.lethal_reason_of = func(_agent: StringName, threat: StringName, cause: StringName) -> StringName:
		return &"protect_home" if threat == &"raider" and cause == &"hostile" else &""
	var events := []
	_conflict.assaulted.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: events.append(["assaulted", a, v, c]))
	_conflict.killed.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: events.append(["killed", a, v, c]))
	assert_eq(_conflict.notice(&"smith", &"raider", 42), BustleConflict.FIGHT)
	assert_eq([_conflict.intent_of(&"smith"), _conflict.intent_reason_of(&"smith")], [BustleConflict.KILL, &"protect_home"])
	var runner := _runner()
	runner.start(_sequence(&"fight"), &"smith", 42)
	assert_eq(runner.tick(0.1, 43), BustleSequenceRunner.State.SUCCEEDED)
	var circumstances := {"act": BustleConflict.act_id(&"smith", &"raider", 42), "cause": "hostile",
		"cause_detail": {"disposition": "hostile"}, "intent": "kill", "intent_reason": "protect_home", "killed": true, "at": 43}
	assert_eq(events, [["assaulted", &"smith", &"raider", circumstances], ["killed", &"smith", &"raider", circumstances]])
	assert_eq(_conflict.combat.status(&"smith"), BustleCombatPort.Status.NONE, "disengaged")


func test_a_subdue_fight_escalates_when_life_is_threatened_mid_fight() -> void:
	var combat := SlowCombat.new()
	_conflict.combat = combat
	_person(&"smith", 90.0, 90.0)
	_conflict.lethal_reason_of = func(agent: StringName, _threat: StringName, _cause: StringName) -> StringName:
		return &"raid" if agent == &"raider" else &""
	_conflict.notice(&"raider", &"smith", 0)
	_conflict.notice(&"smith", &"raider", 0)
	var changes := []
	_conflict.intent_changed.connect(func(a: StringName, t: StringName, i: StringName, r: StringName) -> void: changes.append([a, t, i, r]))
	var runner := _runner()
	runner.start(_sequence(&"fight"), &"smith", 0)
	assert_eq(runner.tick(0.1, 0), BustleSequenceRunner.State.RUNNING)
	assert_eq(combat.engaged, [[&"smith", &"raider", BustleConflict.SUBDUE]], "it starts out to subdue")
	_health.threatened = [&"smith"]
	assert_eq(runner.tick(0.1, 1), BustleSequenceRunner.State.RUNNING)
	assert_eq(changes, [[&"smith", &"raider", BustleConflict.KILL, BustleConflict.DEFEND_LIFE]], "the change and its reason")
	assert_eq(combat.engaged.back(), [&"smith", &"raider", BustleConflict.KILL], "and the combat port is told")
	combat.done = true
	var reported := []
	_conflict.assaulted.connect(func(_a: StringName, _v: StringName, c: Dictionary) -> void: reported.append(c["intent_reason"]))
	runner.tick(0.1, 2)
	assert_eq(reported, ["defend_life"])


func test_a_subdue_fight_that_kills_is_still_reported() -> void:
	var combat := KillingCombat.new()
	combat.always = true
	_conflict.combat = combat
	_person(&"smith", 90.0, 90.0)
	var killed := []
	_conflict.killed.connect(func(a: StringName, v: StringName, c: Dictionary) -> void: killed.append([a, v, c["intent"], c["intent_reason"]]))
	_conflict.notice(&"smith", &"raider", 5)
	_conflict.notice(&"miller", &"raider", 5)
	var runner := _runner()
	runner.start(_sequence(&"fight"), &"smith", 5)
	runner.tick(0.1, 5)
	assert_eq(killed, [[&"smith", &"raider", "subdue", "none"]], "a death without intent to kill, for the host to judge")
	assert_eq(_conflict.threat_of(&"miller"), &"", "conflicts with the dead end")


func test_quarrels_come_to_blows_only_past_the_threshold() -> void:
	for row: Array in [[0.0, 1.4], [50.0, 1.0], [100.0, 0.6], [75.0, 0.8]]:
		_person(&"smith", 50.0, row[0])
		assert_almost_eq(_conflict.quarrel_threshold(&"smith"), row[1], 1e-6, "temper %d" % row[0])
	_moods[&"smith"] = FakeMood.new()
	_moods[&"smith"].mood = 0.0
	assert_almost_eq(_conflict.quarrel_threshold(&"smith"), 0.6, 1e-6, "temper 75 at mood 0: 0.8 × 0.75")
	_person(&"smith", 50.0, 100.0)
	assert_almost_eq(_conflict.quarrel_threshold(&"smith"), 0.45, 1e-6, "the lowest it goes")
	assert_false(_conflict.quarrel(&"smith", &"baker", 10, 0.2), "a single insult with no grudge never comes to blows")
	assert_true(_conflict.quarrel(&"smith", &"baker", 10, 0.5), "a hard shove does, for a hot temper in a black mood")
	_conflict.clear(&"smith")
	_conflict.clear(&"baker")
	var store := BustleSocialStore.new()
	store.add_opinion(&"miller", &"baker", -40.0, {"deed": "deed_1"}, 5.0)
	_conflict.social = store
	_person(&"miller", 20.0, 50.0)
	_person(&"baker", 20.0, 20.0)
	assert_almost_eq(_conflict.grudge(&"miller", &"baker"), 0.8, 1e-6)
	assert_false(_conflict.quarrel(&"miller", &"smith", 20, 0.2), "no grudge against the smith")
	assert_true(_conflict.quarrel(&"miller", &"baker", 20, 0.2), "the same insult on top of a grudge does")
	assert_eq([_conflict.stance_of(&"miller"), _conflict.stance_of(&"baker")], [BustleConflict.FIGHT, BustleConflict.FLEE])
	var detail: Dictionary = _conflict.conflict_of(&"miller")["cause_detail"]
	assert_almost_eq(float(detail["provocation"]) + float(detail["grudge"]), 1.0, 1e-6)
	assert_almost_eq(float(detail["threshold"]), 1.0, 1e-6, "the event's reason records all three")
	assert_eq(_conflict.disposition.disposition(&"miller", &"village", &"baker", &"village"), BustleDispositionPort.Disposition.FRIENDLY, "nobody became hostile")


func test_conflicts_save_and_bad_data_changes_nothing() -> void:
	_conflict.notice(&"baker", &"raider", 0)
	var saved: Variant = JSON.parse_string(JSON.stringify(_conflict.export_state()))
	var other := BustleConflict.new()
	assert_true(other.import_state(saved))
	assert_eq(other.export_state(), _conflict.export_state())
	assert_eq([other.threat_of(&"baker"), other.stance_of(&"baker"), other.intent_of(&"baker")], [&"raider", BustleConflict.FLEE, BustleConflict.SUBDUE])
	var row: Dictionary = (saved as Dictionary)["conflicts"]["baker"]
	for change: Dictionary in [{"stance": "dance"}, {"threat": ""}, {"intent": "maim"}, {"cause_detail": "x"}, {"act": 3}]:
		var broken := row.duplicate(true)
		broken.merge(change, true)
		assert_false(other.import_state({"conflicts": {"baker": broken}}), str(change))
	assert_false(other.import_state(null))
	assert_eq(other.threat_of(&"baker"), &"raider", "refused data changes nothing")
	var port := BustleCombatPort.new()
	assert_eq(port.outcome(&"a"), {}, "no outcome before a fight")
	port.engage(&"a", &"b")
	assert_eq(port.outcome(&"a"), {"target": &"b", "intent": &"subdue", "killed": false, "downed": false}, "the default never hurts anyone")


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
