# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## The house demo: two residents, one a loner and one outgoing, in a house with a bed, a stove, a
## table, a bench and a phone, and a morning block of work off site. Everything here is demo data,
## and every number is a starting point, not tuning.
##
## - **Needs:** food (rises while awake, slowly while asleep), sleep (rises while awake), company
##   (rises while awake at home: being in the house together isn't talking, so the phone and the
##   table meet it) and solitude (rises in company, eases alone). Work slows company for everyone,
##   but only the loner's company eases there: the outgoing resident's still rises, more slowly. The
##   loner and outgoing traits change how fast company and solitude rise, and how much social and
##   quiet things count.
## - **Sleep** counts for nothing in the scorer until it reaches [constant SLEEPY].
## - **Goals:** [code]use_object[/code] (personal: use whatever relieves the most), [code]eat_now[/code]
##   and [code]sleep_now[/code] (urgent: cook or go to bed once food or sleep presses hard), and
##   [code]work[/code] (duty: go to work during the work block, which takes the agent off site).
## - **Objects:** each is a [BustleAffordance] in the area [code]house[/code], used for a number of
##   game minutes by the demo's [code]use[/code] action.

const Harness := preload("res://demo/harness/demo_harness.gd")
const LONER := preload("res://demo/traits/loner.tres")
const OUTGOING := preload("res://demo/traits/outgoing.tres")

## The two residents.
const RESIDENT_A := &"resident_a"
const RESIDENT_B := &"resident_b"
## The house's area.
const AREA := &"house"
## The work block, in minutes of the day.
const WORK_START := 540
const WORK_END := 780
## How hard food or sleep must press before it becomes urgent.
const URGENT_FOOD := 0.8
const URGENT_SLEEP := 0.85
## Sleep counts for nothing below this, so a resident doesn't go to bed for a little tiredness.
const SLEEPY := 0.35


## A house run seeded [param world_seed]. Resident A is the loner and B is outgoing, or the other
## way round when [param swapped].
static func build(world_seed: int = 1, swapped: bool = false) -> Harness:
	var house := Harness.new(world_seed)
	house.sleep_object = &"bed"
	house.scoring.need_curves[&"sleep"] = _from(SLEEPY)
	house.add_object(_object(&"bed", {&"sleep": 1.0}, [&"rest"], 2, 600), 480)
	house.add_object(_object(&"stove", {&"food": 0.6}, [&"cook"], 1, 60), 30)
	house.add_object(_object(&"table", {&"food": 0.3, &"company": 0.4}, [&"social", &"meal"], 2, 60), 40)
	house.add_object(_object(&"bench", {&"solitude": 0.8}, [&"quiet"], 1, 90), 60)
	house.add_object(_object(&"phone", {&"company": 0.5}, [&"social"], 1, 60), 20)
	var library := goals()
	var routine := work_routine()
	house.add_agent(RESIDENT_A, library, needs(), [OUTGOING if swapped else LONER] as Array[BustleTraitDef], routine)
	house.add_agent(RESIDENT_B, library, needs(), [LONER if swapped else OUTGOING] as Array[BustleTraitDef], routine)
	return house


## The residents' needs.
static func needs() -> Array[BustleNeedDef]:
	return [
		_need(&"food", 0.055, [&"awake"], {&"asleep": 0.02}),
		_need(&"sleep", 0.06, [&"awake"], {}),
		_need(&"company", 0.06, [&"awake"], {&"away": -0.04}),
		_need(&"solitude", 0.0, [], {&"in_company": 0.04, &"alone": -0.1}),
	]


## The goals every resident has.
static func goals() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	var use := BustleGoalDef.new()
	use.id = &"use_object"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	use.sequence = _sequence(&"use", {})
	library.goals.append(use)
	library.goals.append(_urgent(&"eat_now", &"need.food", URGENT_FOOD, &"stove"))
	library.goals.append(_urgent(&"sleep_now", &"need.sleep", URGENT_SLEEP, &"bed"))
	var work := BustleGoalDef.new()
	work.id = Harness.AWAY_GOAL
	work.band = BustleBands.DUTY
	work.considerations.append(_consider(&"schedule.work", 0.5))
	work.sequence = _sequence(&"wait", {"minutes": 30})
	library.goals.append(work)
	return library


## The work routine: one block, off site, every day.
static func work_routine() -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = Harness.AWAY_GOAL
	block.start_minute = WORK_START
	block.end_minute = WORK_END
	block.place = &"work"
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.id = &"work_mornings"
	routine.day = day
	return routine


## An order to use [param object] once.
static func use_order(id: StringName, object: StringName) -> BustleOrder:
	return BustleOrder.new(id, _sequence(&"use", {"object": object}), object)


static func _object(id: StringName, relief: Dictionary[StringName, float], tags: Array[StringName],
		capacity: int, hold: int) -> BustleAffordance:
	var def := BustleAffordanceDef.new()
	def.id = id
	def.relief = relief
	def.tags = tags
	def.capacity = capacity
	def.hold_minutes = hold
	return BustleAffordance.new(id, def, AREA)


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
