# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Temperaments from data alone: with the same needs and the same two rooms (a busy hall and a quiet
## nook), only the trait data differs. A loner avoids the busy hall, an outgoing agent seeks it, and
## a low-spirited agent's scores stay low and close together. Every thought lists its reason.

const LONER := preload("res://demo/traits/loner.tres")
const OUTGOING := preload("res://demo/traits/outgoing.tres")
const LOW_SPIRITED := preload("res://demo/traits/low_spirited.tres")
const HALL := &"busy_hall"
const NOOK := &"quiet_nook"


func test_a_loner_avoids_the_busy_hall_and_an_outgoing_agent_seeks_it() -> void:
	assert_eq(_choose([LONER]).last_intent.option_id, NOOK, "the loner takes the quiet nook")
	assert_eq(_choose([OUTGOING]).last_intent.option_id, HALL, "the outgoing agent takes the busy hall")
	assert_eq(_choose([]).last_intent.option_id, HALL, "with no trait, the hall's bigger relief wins")


func test_a_low_spirited_agents_scores_stay_low_and_close_together() -> void:
	var plain := _scores(_choose([]))
	var low := _scores(_choose([LOW_SPIRITED]))
	assert_eq(plain.size(), 2)
	assert_eq(low.size(), 2)
	assert_lt(low.max(), plain.max(), "lower: best %.3f against %.3f" % [low.max(), plain.max()])
	assert_lt(low.max() - low.min(), (plain.max() - plain.min()) / 2.0,
		"closer: spread %.3f against %.3f" % [low.max() - low.min(), plain.max() - plain.min()])


func test_every_thought_lists_its_reason() -> void:
	var brain := _choose([LOW_SPIRITED, OUTGOING])
	var mood: BustleMood = brain.get_meta(&"mood")
	var reasons := mood.reasons()
	assert_false(reasons.is_empty())
	for entry: Dictionary in reasons:
		assert_eq((entry["reason"] as Dictionary).get("kind"), "trait", "%s says why: %s" % [entry["thought"], entry["reason"]])


# An agent with [param traits], company and solitude both half pressing, a settled mood, and the
# hall and the nook to choose from, after one tick.
func _choose(traits: Array[BustleTraitDef]) -> BustleBrain:
	var config := BustleScoringConfig.new()
	for tag: StringName in [&"social", &"quiet"]:
		config.mood_curves[tag] = _by_mood()
	var library := BustleGoalLibrary.new()
	var goal := BustleGoalDef.new()
	goal.id = &"use_object"
	goal.band = BustleBands.PERSONAL
	goal.uses_advertisements = true
	library.goals.append(goal)
	var brain := BustleBrain.new(&"someone", library, config, 1)
	var needs := BustleNeedSet.new()
	for id: StringName in [&"company", &"solitude"]:
		var def := BustleNeedDef.new()
		def.id = id
		needs.add_need(def)
		needs.set_pressure(id, 0.5)
	var mood := BustleMood.new(BustleMoodConfig.new(), brain.modifiers)
	mood.start(0)
	var personality := BustlePersonality.new()
	for def: BustleTraitDef in traits:
		personality.add_trait(def)
	personality.apply(brain.modifiers, needs, library, mood)
	mood.mood = mood.target()
	var rooms := BustleAffordanceSet.new()
	rooms.add(_room(HALL, {&"company": 0.8}, &"social"))
	rooms.add(_room(NOOK, {&"solitude": 0.4}, &"quiet"))
	var senses := BustleSenses.new()
	needs.fill_inputs(senses.inputs)
	personality.fill_inputs(senses.inputs)
	mood.fill_inputs(senses.inputs)
	senses.advertisements = rooms.advertisements(&"someone", 0)
	brain.tick(1.0, senses)
	brain.set_meta(&"mood", mood)
	return brain


func _scores(brain: BustleBrain) -> Array[float]:
	var out: Array[float] = []
	for candidate: BustleCandidate in brain.last_candidates:
		if candidate.goal_id == &"use_object":
			out.append(candidate.raw_score)
	return out


func _room(id: StringName, relief: Dictionary[StringName, float], tag: StringName) -> BustleAffordance:
	var def := BustleAffordanceDef.new()
	def.id = id
	def.relief = relief
	def.tags = [tag] as Array[StringName]
	def.capacity = 8
	return BustleAffordance.new(id, def, &"house")


# A tag's weight by mood: 0 at mood 0, rising straight to 1 at mood 100.
func _by_mood() -> Curve:
	var curve := Curve.new()
	curve.min_domain = 0.0
	curve.max_domain = 100.0
	curve.add_point(Vector2(0.0, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(100.0, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve
