# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## The colony demo: four settlers with a bed each, a stove, a field plot and a crate, a day block of
## work in the field, and one cold snap the demo injects as a host event. Everything here is demo
## data, and every number is a starting point, not tuning.
##
## - **Needs:** food (rises while awake, slowly while asleep), sleep (rises while awake) and warmth
##   (still, until the cold snap: then it rises for everyone).
## - **Mood** (the needs_mood module): need thoughts while hungry, tired or cold, a good thought
##   after a hot meal, a night in bed or a harvest, and a bad one when the cold snap starts. A mood
##   low enough starts a mental state, which this demo only records.
## - **Social** (the built-in social store): settlers A and B are friends, and so are C and D. A
##   settler who notices a friend in a low mood or state may comfort them, through the demo's
##   [code]comfort[/code] goal and interaction.
## - **Perception:** who notices whom. Off, a settler notices everyone awake in its area.
## - **Goals:** [code]use_object[/code] (personal), [code]eat_now[/code], [code]sleep_now[/code] and
##   [code]warm_up[/code] (urgent), [code]farm[/code] (duty: work the field during the day
##   block), and [code]unwind[/code] (idle: sit by the hearth when nothing else calls, so a free
##   evening isn't hours of standing still). [code]comfort[/code] joins them with social on.
##
## Each module can be left out of a build ([method build]); the rest still runs.

const Harness := preload("res://demo/harness/demo_harness.gd")
const LONER := preload("res://demo/traits/loner.tres")
const OUTGOING := preload("res://demo/traits/outgoing.tres")
const LOW_SPIRITED := preload("res://demo/traits/low_spirited.tres")
const COMFORT_GOAL := preload("res://demo/social/comfort_goal.tres")
const SOCIAL_DIR := "res://demo/social/%s.tres"
const INTERACTIONS: Array[StringName] = [&"chitchat", &"deep_talk", &"kind_words", &"slight", &"insult", &"comfort"]

## The four settlers.
const SETTLER_A := &"settler_a"
const SETTLER_B := &"settler_b"
const SETTLER_C := &"settler_c"
const SETTLER_D := &"settler_d"
const SETTLERS: Array[StringName] = [SETTLER_A, SETTLER_B, SETTLER_C, SETTLER_D]
## Each settler's own bed.
const BEDS: Dictionary[StringName, StringName] = {SETTLER_A: &"bed_a", SETTLER_B: &"bed_b",
	SETTLER_C: &"bed_c", SETTLER_D: &"bed_d"}
## The modules a build can leave out.
const NEEDS_MOOD := &"needs_mood"
const SOCIAL := &"social"
const PERCEPTION := &"perception"
const MODULES: Array[StringName] = [NEEDS_MOOD, SOCIAL, PERCEPTION]
## The areas.
const HOME := &"home"
const FIELD := &"field"
## The goal and schedule activity for field work.
const FARM := &"farm"
## The field work block, in minutes of the day.
const WORK_START := 480
const WORK_END := 960
## The goal and schedule activity for the night in bed, from 22:00 to 07:00. A settler goes to bed
## in it while sleep presses at least [constant DROWSY], so it gets up once rested.
const REST := &"rest"
const REST_START := 1320
const REST_END := 420
const DROWSY := 0.3
## The goal and object for free time: sitting by the hearth.
const UNWIND := &"unwind"
const HEARTH := &"hearth"
## The cold snap: from 18:00 on the third day, for a day.
const COLD_SNAP := &"cold_snap"
const COLD_START := 2 * 1440 + 1080
const COLD_MINUTES := 1440
## How hard a need must press before it becomes urgent.
const URGENT_FOOD := 0.8
const URGENT_SLEEP := 0.95
const URGENT_WARMTH := 0.7
## Food counts for nothing below this, so a settler eats when peckish rather than all day.
const PECKISH := 0.3
## Sleep counts for nothing below this (about 16 hours up), so a settler doesn't nap.
const SLEEPY := 0.8
## The run starts at 06:00 on the first day, as the settlers wake.
const START := 360


## A colony run seeded [param world_seed] with [param modules] on (all three by default), and the
## cold snap unless [param cold_snap] is false.
static func build(world_seed: int = 1, modules: Array[StringName] = MODULES, cold_snap: bool = true) -> Harness:
	var colony := Harness.new(world_seed)
	colony.now = START
	colony.home_area = HOME
	colony.sleep_object = &""
	colony.sleep_objects = BEDS.values()
	colony.scoring.need_curves[&"food"] = _from(PECKISH)
	colony.scoring.need_curves[&"sleep"] = _from(SLEEPY)
	var x := 0.0
	for id: StringName in SETTLERS:
		var bed := _object(BEDS[id], {&"sleep": 1.0}, [&"rest"], 1, 600, HOME, Vector3(x, 0, 0))
		bed.owner = id
		colony.add_object(bed, 480)
		x += 1.5
	colony.add_object(_object(&"stove", {&"food": 0.6, &"warmth": 0.8}, [&"cook"], 2, 60, HOME, Vector3(1.5, 0, 4)), 30)
	colony.add_object(_object(&"crate", {&"food": 0.35}, [&"stores"], 2, 30, HOME, Vector3(-2, 0, 4)), 10)
	colony.add_object(_object(&"field", {}, [&"work"], 4, 90, FIELD, Vector3(60, 0, 0)), 60)
	colony.add_object(_object(HEARTH, {}, [&"quiet"], 4, 60, HOME, Vector3(0, 0, 6)), 60)
	if modules.has(NEEDS_MOOD):
		colony.enable_mood(need_thoughts())
		colony.use_thoughts = {&"stove": thought(&"hot_meal", 5.0, 6.0, &"content", 1),
			&"field": thought(&"harvest", 3.0, 6.0, &"proud", 2)}
		var rested := thought(&"slept_well", 4.0, 8.0, &"rested", 1)
		for bed: StringName in BEDS.values():
			colony.use_thoughts[bed] = rested
	if modules.has(SOCIAL):
		colony.enable_social(BustleSocialStore.new(), interactions())
	if modules.has(PERCEPTION):
		var profile := BustlePerceptionProfile.new()
		profile.sight_angle_deg = 360.0
		profile.peripheral_angle_deg = 360.0
		colony.enable_perception(profile)
	var days := routine()
	var traits: Array = [[LONER], [OUTGOING], [LOW_SPIRITED], []]
	for i: int in SETTLERS.size():
		var own: Array[BustleTraitDef] = []
		own.assign(traits[i])
		colony.add_agent(SETTLERS[i], goals(BEDS[SETTLERS[i]], modules.has(SOCIAL)), needs(), own, days)
	if colony.store != null:
		for pair: Array in [[SETTLER_A, SETTLER_B], [SETTLER_C, SETTLER_D]]:
			colony.store.set_kind(pair[0], pair[1], &"friend")
			colony.store.set_kind(pair[1], pair[0], &"friend")
	if cold_snap:
		colony.add_event(COLD_SNAP, COLD_START, COLD_MINUTES, &"cold", thought(&"bitter_weather", -6.0, 24.0, &"miserable", 1))
	return colony


## The settlers' needs.
static func needs() -> Array[BustleNeedDef]:
	return [
		_need(&"food", 0.055, [&"awake"], {&"asleep": 0.02}),
		_need(&"sleep", 0.05, [&"awake"], {}),
		_need(&"warmth", 0.0, [], {&"cold": 0.12, &"asleep": -0.12}),
	]


## The need thoughts: hungry, tired and cold, held while the need presses.
static func need_thoughts() -> Array[BustleThoughtDef]:
	var out: Array[BustleThoughtDef] = []
	for row: Array in [[&"hungry", &"food", 0.6, -8.0], [&"tired", &"sleep", 0.75, -6.0], [&"cold", &"warmth", 0.3, -12.0]]:
		var def := thought(row[0], row[3], 0.0, &"miserable", 1)
		def.reason_kind = &"need"
		def.need = row[1]
		def.need_at_least = row[2]
		out.append(def)
	return out


## A thought [param id] worth [param value] for [param hours] game hours (0: held).
static func thought(id: StringName, value: float, hours: float, emotion: StringName, stack: int) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.duration_hours = hours
	def.emotion = emotion
	def.stack_limit = stack
	return def


## The demo interaction set. Comfort, the friend's opener, also leaves its recipient a thought.
static func interactions() -> Array[BustleInteractionDef]:
	var out: Array[BustleInteractionDef] = []
	for id: StringName in INTERACTIONS:
		var def: BustleInteractionDef = load(SOCIAL_DIR % id)
		if id == &"comfort":
			def = def.duplicate()
			def.recipient_thought = thought(&"comforted", 15.0, 12.0, &"relieved", 1)
		out.append(def)
	return out


## The goals of a settler who sleeps in [param bed], with [code]comfort[/code] when
## [param social].
static func goals(bed: StringName, social: bool) -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	var use := BustleGoalDef.new()
	use.id = &"use_object"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	use.sequence = _sequence(&"use", {})
	library.goals.append(use)
	library.goals.append(_urgent(&"eat_now", &"need.food", URGENT_FOOD, &"stove"))
	library.goals.append(_urgent(&"sleep_now", &"need.sleep", URGENT_SLEEP, bed))
	library.goals.append(_urgent(&"warm_up", &"need.warmth", URGENT_WARMTH, &"stove"))
	var farm := BustleGoalDef.new()
	farm.id = FARM
	farm.band = BustleBands.DUTY
	farm.considerations.append(_consider(&"schedule.farm", 0.5))
	farm.sequence = _sequence(&"use", {"object": &"field"})
	library.goals.append(farm)
	var rest := BustleGoalDef.new()
	rest.id = REST
	rest.band = BustleBands.DUTY
	rest.considerations.append(_consider(&"schedule.rest", 0.5))
	rest.considerations.append(_consider(&"need.sleep", DROWSY))
	rest.sequence = _sequence(&"use", {"object": bed})
	library.goals.append(rest)
	var unwind := BustleGoalDef.new()
	unwind.id = UNWIND
	unwind.band = BustleBands.IDLE
	unwind.sequence = _sequence(&"use", {"object": HEARTH})
	library.goals.append(unwind)
	if social:
		library.goals.append(COMFORT_GOAL)
	return library


## The settlers' routine, every day: the field in the day and the night in bed.
static func routine() -> BustleScheduleDef:
	var day := BustleScheduleDay.new()
	day.blocks.append(_block(FARM, WORK_START, WORK_END, FIELD))
	day.blocks.append(_block(REST, REST_START, REST_END, HOME))
	var out := BustleScheduleDef.new()
	out.id = &"settler_days"
	out.day = day
	return out


static func _block(activity: StringName, start: int, end: int, place: StringName) -> BustleScheduleBlock:
	var block := BustleScheduleBlock.new()
	block.activity = activity
	block.start_minute = start
	block.end_minute = end
	block.place = place
	return block


static func _object(id: StringName, relief: Dictionary[StringName, float], tags: Array[StringName],
		capacity: int, hold: int, area: StringName, position: Vector3) -> BustleAffordance:
	var def := BustleAffordanceDef.new()
	def.id = id
	def.relief = relief
	def.tags = tags
	def.capacity = capacity
	def.hold_minutes = hold
	return BustleAffordance.new(id, def, area, position)


static func _need(id: StringName, rate: float, rises_when: Array[StringName], conditions: Dictionary[StringName, float]) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = rises_when
	def.condition_rates = conditions
	return def


# A goal that goes to [param object] once [param input] reaches [param at].
static func _urgent(id: StringName, input: StringName, at: float, object: StringName) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.URGENT
	goal.considerations.append(_consider(input, at))
	goal.sequence = _sequence(&"use", {"object": object})
	return goal


# A need curve: 0 up to [param at], then rising straight to 1 at full pressure.
static func _from(at: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(at, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


# A step consideration: 0 below [param at], 1 from it.
static func _consider(input: StringName, at: float) -> BustleConsideration:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(maxf(at - 0.001, 0.0), 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(at, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = input
	consideration.curve = curve
	return consideration


static func _sequence(action: StringName, params: Dictionary) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = action
	step.params = params
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence
