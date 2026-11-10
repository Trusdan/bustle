# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## How an ambition sways choices: boosts multiply named goals' scores and never change a band, never
## touch theft or fights, stop while locked or once the template is disabled. Courting and feuds
## aim at the right person. Over seven days, each template's goals are chosen more often than
## without it.

const DAY := 1440
const PEOPLE: Array[StringName] = [&"someone", &"other"]

var _society: BustleSociety
var _store: BustleSocialStore
var _targets: BustleAmbitionTargets


func before_each() -> void:
	_society = BustleSociety.new(3)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_store = BustleSocialStore.new()
	_society.set_port(&"social", _store)
	_targets = BustleAmbitionTargets.new(_society)
	for row: Array in [[&"agent", &"town"], [&"liked", &"town"], [&"kin", &"town"], [&"faraway", &"farm"], [&"lukewarm", &"town"], [&"foe", &"town"]]:
		_society.add_agent(row[0], &"villager").area = row[1]
	for row: Array in [[&"liked", 25.0], [&"kin", 40.0], [&"faraway", 45.0], [&"lukewarm", 5.0], [&"foe", -30.0]]:
		_store.add_opinion(&"agent", row[0], row[1], {}, 1000.0)
	_store.set_kind(&"agent", &"kin", &"family")
	_store.set_kind(&"agent", &"foe", &"rival")


func test_boosts_multiply_scores_and_never_change_a_band() -> void:
	var a := BustleAmbitions.new(&"agent")
	a.update(0, _person({&"greed": 90.0}), {"wallet": 0.0})
	a.config.find(&"save_money").boosts[&"steal"] = 5.0
	var with := _scores(a.boost)
	var without := _scores(Callable())
	assert_eq(with[&"work"], [1.5, BustleBands.PERSONAL], "work counts half as much again, in its own band")
	assert_eq(with[&"trade"], [1.3, BustleBands.PERSONAL])
	assert_eq(with[&"rest"], without[&"rest"], "goals it doesn't name are untouched")
	assert_eq(with[&"steal"], without[&"steal"], "theft is never boosted, whatever the table says")
	assert_eq(with[&"duty"], without[&"duty"])
	var library := _library()
	var context := BustleScoreContext.new()
	context.inputs = {&"fact.on": 1.0}
	context.score_boost = a.boost
	var scorer := BustleUtilityScorer.new()
	assert_eq(scorer.choose(scorer.evaluate(library, context, BustleScoringConfig.new()), BustleScoringConfig.new(), _rng()).goal_id, &"steal",
		"a higher band still wins, boost or not")
	context.score_boost = func(_g: StringName, _o: StringName) -> float: return NAN
	assert_false(scorer.evaluate(library, context, BustleScoringConfig.new())[0].eligible, "a bad boost makes a candidate ineligible")


func test_boosts_stop_while_locked_or_once_the_template_is_disabled() -> void:
	var a := BustleAmbitions.new(&"agent")
	var greedy := _person({&"greed": 90.0})
	a.update(0, greedy, {"wallet": 0.0, "locked": true})
	assert_eq([a.active()["id"], a.boost(&"work")], ["save_money", 1.0], "locked: assigned, but no boost")
	a.update(1, greedy, {"wallet": 500.0})
	assert_eq(a.boost(&"work"), 1.5, "the lock ends, the boost is back")
	a.update(2, greedy, {"wallet": 2000.0, "locked": true})
	assert_eq(a.active()["id"], "leave_settlement", "completing still works while locked")
	a.config.find(&"leave_settlement").enabled = false
	a.update(3, greedy, {})
	assert_eq([a.active()["id"], a.boost(&"explore")], ["leave_settlement", 1.0], "disabled after it was assigned: no boost ever")
	var ends := []
	a.ended_moot.connect(func(_a: StringName, id: StringName, fact: StringName) -> void: ends.append([id, fact]))
	a.config.templates = a.config.templates.filter(func(d: BustleAmbitionDef) -> bool: return d.id != &"leave_settlement")
	a.update(4, greedy, {})
	assert_eq(ends, [[&"leave_settlement", &"unknown_template"]], "a template taken out of the library ends with an event")
	var host := BustleAmbitionConfig.new()
	host.find(&"leave_settlement").enabled = false
	for curiosity in range(0, 101, 25):
		var b := BustleAmbitions.new(&"b", host)
		var aim := b.update(0, _person({&"curiosity": float(curiosity), &"boldness": 100.0, &"greed": 0.0}))
		assert_ne(aim.get("id", ""), "leave_settlement", "a host that turns leaving off never sees it")
		assert_eq(b.boost(&"explore"), 1.0)


func test_courting_aims_at_someone_liked_nearby_and_never_family() -> void:
	assert_eq(_targets.court_target(&"agent"), &"liked", "75 in the same place: not kin (90), not 95 far off, not 55")
	var a := BustleAmbitions.new(&"agent")
	var warm := _person({&"sociability": 100.0})
	assert_eq(_update(a, 0, warm)["target"], "liked")
	assert_eq([a.boost(&"visit", &"liked"), a.boost(&"gift", &"liked"), a.boost(&"visit", &"lukewarm"), a.boost(&"work")], [2.0, 2.0, 1.0, 1.0],
		"only toward the one it courts")
	_store.add_opinion(&"agent", &"lukewarm", 10.0, {}, 1000.0)
	_society.remove_agent(&"liked")
	assert_eq([_update(a, DAY, warm)["id"], a.active()["target"]], ["court_someone", "lukewarm"], "gone, but someone else qualifies: it turns to them")
	_society.remove_agent(&"lukewarm")
	var events := []
	a.ended_moot.connect(func(_a: StringName, id: StringName, fact: StringName) -> void: events.append([id, fact]))
	_update(a, 2 * DAY, warm)
	assert_eq(events, [[&"court_someone", &"court_target_gone"]], "nobody left to court: moot")
	assert_ne(a.active().get("id", ""), "court_someone")
	var b := BustleAmbitions.new(&"agent")
	_update(b, 3 * DAY, warm)
	assert_ne(b.active().get("id", ""), "court_someone", "family never counts, however liked")


func test_settling_a_feud_aims_at_the_rival_and_never_at_violence() -> void:
	var a := BustleAmbitions.new(&"agent")
	a.config.find(&"settle_feud").boosts.merge({&"insult": 3.0, &"quarrel": 3.0, &"fight": 3.0})
	var fair := _person({&"honesty": 100.0})
	assert_eq(_update(a, 0, fair)["target"], "foe")
	assert_eq([a.boost(&"help", &"foe"), a.boost(&"converse", &"foe"), a.boost(&"help", &"liked")], [2.0, 2.0, 1.0])
	for goal: StringName in [&"insult", &"quarrel", &"fight"]:
		assert_eq(a.boost(goal, &"foe"), 1.0, "never %s" % goal)
	_store.add_opinion(&"agent", &"foe", 40.0, {}, 1000.0)
	_store.clear_kind(&"agent", &"foe", &"rival")
	var done := []
	a.ambition_completed.connect(func(_a: StringName, id: StringName, _i: Dictionary) -> void: done.append(id))
	_update(a, DAY, fair)
	assert_eq(done, [&"settle_feud"], "rival kind gone and opinion back to 60: settled")
	_store.set_kind(&"agent", &"foe", &"rival")
	var b := BustleAmbitions.new(&"agent")
	_update(b, 9 * DAY, fair)
	_society.remove_agent(&"foe")
	var moot := []
	b.ended_moot.connect(func(_a: StringName, id: StringName, fact: StringName) -> void: moot.append(fact))
	_update(b, 10 * DAY, fair)
	assert_eq(moot, [&"rival_gone"], "the rival gone for good: moot")


func test_seven_days_each_template_favours_its_goals() -> void:
	var cases := [[&"save_money", {&"greed": 90.0}, {"wallet": 0.0}, &"work", &""],
		[&"get_promoted", {&"diligence": 90.0}, {"has_role": true}, &"work", &""],
		[&"court_someone", {&"sociability": 90.0}, {}, &"visit", &"liked"],
		[&"settle_feud", {&"honesty": 90.0}, {}, &"help", &"foe"],
		[&"leave_settlement", {&"curiosity": 90.0}, {}, &"explore", &""]]
	for row: Array in cases:
		var boosted := _week(row, true)
		var control := _week(row, false)
		gut.p("%s: %s chosen %d times with it, %d without" % [row[0], row[3], boosted["hits"], control["hits"]])
		assert_gt(boosted["hits"], control["hits"] * 2, "%s favours %s" % [row[0], row[3]])
		assert_eq(boosted["locked_boosts"], 0, "%s: no boost while locked" % row[0])
		assert_eq(boosted["aim"], String(row[0]), "%s stays assigned all week" % row[0])
		assert_eq(_week(row, true), boosted, "%s: the same week twice" % row[0])


# A week every half hour, locked from 9 to 12 each day: how often the scorer picks the template's
# goal (and person), with the ambition or (control) without.
func _week(row: Array, with_ambition: bool) -> Dictionary:
	var a := BustleAmbitions.new(&"agent")
	a.pin = row[0]
	a.enabled = with_ambition
	var scorer := BustleUtilityScorer.new()
	var config := BustleScoringConfig.new()
	config.pick_window = 0.3
	var rng := _rng()
	var library := _social_library()
	var hits := 0
	var locked_boosts := 0
	for minute in range(0, 7 * DAY, 30):
		var hour := floori((minute % DAY) / 60.0)
		var inputs: Dictionary = (row[2] as Dictionary).duplicate()
		_targets.fill(&"agent", a.active(), inputs)
		inputs["locked"] = hour >= 9 and hour < 12
		a.update(minute, _person(row[1]), inputs)
		var context := BustleScoreContext.new()
		context.inputs = {&"fact.on": 1.0, &"need.social": 0.5}
		for person: StringName in [&"liked", &"foe", &"lukewarm"]:
			context.advertisements.append(BustleAdvertisement.new(person, {&"social": 0.5} as Dictionary[StringName, float]))
		context.score_boost = a.boost
		var candidates := scorer.evaluate(library, context, config)
		if inputs["locked"] and candidates.any(func(c: BustleCandidate) -> bool: return c.raw_score > _plain(c) + 1e-9):
			locked_boosts += 1
		var pick := scorer.choose(candidates, config, rng)
		if pick.goal_id == row[3] and (row[4] == &"" or pick.option_id == row[4]):
			hits += 1
	return {"hits": hits, "locked_boosts": locked_boosts, "aim": str(a.active().get("id", "")) if with_ambition else String(row[0])}


func _plain(candidate: BustleCandidate) -> float:
	var context := BustleScoreContext.new()
	context.inputs = {&"fact.on": 1.0, &"need.social": 0.5}
	if candidate.option_id != &"":
		context.advertisements.append(BustleAdvertisement.new(candidate.option_id, {&"social": 0.5} as Dictionary[StringName, float]))
	var library := BustleGoalLibrary.new()
	library.goals = [_social_library().goals.filter(func(g: BustleGoalDef) -> bool: return g.id == candidate.goal_id)[0]] as Array[BustleGoalDef]
	return BustleUtilityScorer.new().evaluate(library, context, BustleScoringConfig.new())[0].raw_score


func _scores(boost: Callable) -> Dictionary:
	var context := BustleScoreContext.new()
	context.inputs = {&"fact.on": 1.0}
	context.score_boost = boost
	var out := {}
	for c: BustleCandidate in BustleUtilityScorer.new().evaluate(_library(), context, BustleScoringConfig.new()):
		out[c.goal_id] = [snappedf(c.raw_score, 0.001), c.band]
	return out


func _library() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	for row: Array in [[&"work", BustleBands.PERSONAL], [&"trade", BustleBands.PERSONAL], [&"rest", BustleBands.PERSONAL],
			[&"duty", BustleBands.DUTY], [&"steal", BustleBands.GUARDED]]:
		library.goals.append(_goal(row[0], row[1], false))
	return library


func _social_library() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	for id: StringName in [&"work", &"trade", &"rest", &"explore"]:
		library.goals.append(_goal(id, BustleBands.PERSONAL, false))
	for id: StringName in [&"visit", &"gift", &"help", &"converse"]:
		library.goals.append(_goal(id, BustleBands.PERSONAL, true))
	return library


func _goal(id: StringName, band: int, ads: bool) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = band
	goal.uses_advertisements = ads
	goal.base_weight = 4.0 if ads else 1.0
	return goal


func _update(a: BustleAmbitions, now: int, personality: BustlePersonality) -> Dictionary:
	var inputs := {}
	_targets.fill(&"agent", a.active(), inputs)
	return a.update(now, personality, inputs)


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


func _person(sliders: Dictionary) -> BustlePersonality:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	return p
