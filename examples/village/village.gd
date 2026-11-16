# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## The village, headless: four villagers with needs, jobs that come from roles, a mood, skills and
## room thoughts, on the host's own clock and map. [code]village_view.gd[/code] only draws it, and
## [code]check.gd[/code] runs it without a window. It calls Bustle's public API only.
## [br][br]
## What Bustle does: it keeps the needs, scores the choices, gives jobs from roles, holds thoughts
## and skills. What the host (this file) does: it moves the clock, walks the villagers, and acts on
## each choice (eating relieves food, work earns practice). Bustle never moves anyone.
## [br][br]
## The names of people, places, jobs, skills and thoughts are PROPOSED flavor text.

const HostClock := preload("res://host/host_clock.gd")
const HostWorld := preload("res://host/host_world.gd")

## Game minutes per step.
const STEP := 10
## How far a villager walks in one step, in map units.
const WALK := 60.0

## PROPOSED: the places on the map, as (x, 0, z).
const PLACES := {
	&"bakery": Vector3(170, 0, 150), &"forge": Vector3(480, 0, 150), &"loom": Vector3(790, 0, 150),
	&"square": Vector3(480, 0, 320),
	&"home_ann": Vector3(150, 0, 490), &"home_bram": Vector3(370, 0, 490),
	&"home_cora": Vector3(590, 0, 490), &"home_dov": Vector3(810, 0, 490),
}
## PROPOSED: the places that are rooms (indoors), with their room scores (0 to 1).
const ROOMS := {
	&"bakery": {&"comfort": 0.8, &"beauty": 0.6}, &"forge": {&"comfort": 0.2}, &"loom": {&"beauty": 0.7},
	&"home_ann": {&"comfort": 0.7}, &"home_bram": {&"comfort": 0.7},
	&"home_cora": {&"comfort": 0.7}, &"home_dov": {&"comfort": 0.7},
}
## PROPOSED: who holds each role at the start. dov holds none, so has no job.
const ROLES := {&"baker": &"ann", &"smith": &"bram", &"weaver": &"cora"}
## PROPOSED: each role's workplace, start and end minute of the day, and the skill it practises.
const JOBS := {
	&"baker": [&"bakery", 300, 720, &"baking"],
	&"smith": [&"forge", 480, 960, &"smithing"],
	&"weaver": [&"loom", 540, 1020, &"weaving"],
}
## PROPOSED: the villagers.
const PEOPLE: Array[StringName] = [&"ann", &"bram", &"cora", &"dov"]

## The population: agents, brains and the ports.
var society := BustleSociety.new(1)
## The host's clock and map (host adapters).
var clock := HostClock.new()
var world := HostWorld.new()
## Rooms and their scores (the default port, filled by the host).
var environment := BustleEnvironmentPort.new()
## The skills module, used as the skills port.
var skills := BustleSkills.new()
## The built-in social store, used as the social port, and greetings recorded through it.
var social := BustleSocialStore.new()
var interactions: BustleSocialInteractions
## Jobs as roles: each role's routine follows its holder.
var roster: BustleScheduleRoster
## The environment module: thoughts from the room a villager is in.
var room_thoughts: BustleRoomThoughts
## Each villager's needs and mood (the mood module).
var needs: Dictionary[StringName, BustleNeedSet] = {}
var moods: Dictionary[StringName, BustleMood] = {}
## What each villager is doing, in words, and where it is heading.
var doing: Dictionary[StringName, String] = {}
var targets: Dictionary[StringName, StringName] = {}
## Counts for the check: meals eaten, work steps, greetings, and room thoughts seen.
var meals := 0
var work_steps := 0
var greetings := 0
var room_thoughts_seen := 0

var _bread: BustleThoughtDef
var _ads: Array[BustleAdvertisement] = []


func _init() -> void:
	_ports()
	_archetype()
	_jobs()
	_people()
	_thoughts()


## The current game minute.
func now() -> int:
	return clock.now_minutes()


## One step of [constant STEP] game minutes: the clock moves on, then each villager's needs rise,
## its brain chooses, and the host walks it and acts on the choice.
func step() -> void:
	clock.minutes += STEP
	social.set_time(now())
	for id: StringName in society.agent_ids():
		_step_one(id)
	_greet()


## A villager's skill level in its job's skill (0 with no job).
func skill_level(id: StringName) -> float:
	var job := roster.job_of(id)
	return skills.level(id, JOBS[job][3]) if JOBS.has(job) else 0.0


# Plugs the host adapters and the modules in as ports (docs/ports.md).
func _ports() -> void:
	world.spots.assign(PLACES)
	society.set_port(&"clock", clock)
	society.set_port(&"world", world)
	society.set_port(&"environment", environment)
	society.set_port(&"skills", skills)
	society.set_port(&"social", social)
	var table := BustleRoleTable.new()
	table.holders.assign(ROLES)
	society.set_port(&"roles", BustleRolesPort.new(table))
	for room: StringName in ROOMS:
		environment.set_scores(room, ROOMS[room])
	interactions = BustleSocialInteractions.new(social, 1)
	var greeting := BustleInteractionDef.new()
	greeting.id = &"greet"
	greeting.recipient_value = 3.0
	greeting.initiator_value = 2.0
	interactions.greeting = greeting


# Two goals every villager chooses from: use something on offer (the bakery, its home) once a need
# presses enough (min_score), or work while its routine says so. With neither worth it, the brain
# idles, and the host sends the villager to stroll in the square.
func _archetype() -> void:
	var use := BustleGoalDef.new()
	use.id = &"use_object"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	use.min_score = 0.3
	var work := BustleGoalDef.new()
	work.id = &"work"
	work.band = BustleBands.PERSONAL
	work.base_weight = 0.5
	var during_shift := BustleConsideration.new()
	during_shift.input = &"schedule.work"
	during_shift.curve = Curve.new()
	during_shift.curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	during_shift.curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	work.considerations.append(during_shift)
	var library := BustleGoalLibrary.new()
	library.goals.append(use)
	library.goals.append(work)
	society.register_archetype(&"villager", library)
	_ads.append(BustleAdvertisement.new(&"bakery", {&"food": 0.7} as Dictionary[StringName, float]))
	_ads.append(BustleAdvertisement.new(&"home", {&"rest": 0.8} as Dictionary[StringName, float]))


# Each role's routine: one block of "work" at its workplace. The roster gives it to the holder.
func _jobs() -> void:
	var routines := BustleRoleSchedules.new()
	for role: StringName in JOBS:
		var block := BustleScheduleBlock.new()
		block.activity = &"work"
		block.place = JOBS[role][0]
		block.start_minute = JOBS[role][1]
		block.end_minute = JOBS[role][2]
		var routine := BustleScheduleDef.new()
		routine.id = role
		routine.day = BustleScheduleDay.new()
		routine.day.blocks.append(block)
		routines.schedules[role] = routine
		var skill := BustleSkillDef.new()
		skill.id = JOBS[role][3]
		skill.xp_curve = [60.0] as Array[float]
		skills.add_def(skill)
	roster = BustleScheduleRoster.new(society.ports.roles, routines)


func _people() -> void:
	for id: StringName in PEOPLE:
		var state := society.add_agent(id, &"villager")
		state.position = PLACES[_home(id)]
		state.has_position = true
		world.areas[id] = _home(id)
		roster.add_agent(id)
		var set := BustleNeedSet.new()
		set.add_need(_need(&"food", 0.08))
		set.add_need(_need(&"rest", 0.05))
		needs[id] = set
		var mood := BustleMood.new()
		mood.start(0)
		moods[id] = mood
		doing[id] = "waking up"
		targets[id] = _home(id)


# A meal is a good thought for six hours; a cosy room a held thought while inside, a cold one a
# bad thought (the environment module holds and drops them).
func _thoughts() -> void:
	_bread = _thought(&"fresh_bread", 4.0, 6.0)
	var rules: Array[BustleRoomThought] = []
	var cosy := BustleRoomThought.new()
	cosy.score = &"comfort"
	cosy.at_least = 0.7
	cosy.thought = _thought(&"cosy_room", 3.0, 0.0)
	rules.append(cosy)
	var bare := BustleRoomThought.new()
	bare.score = &"comfort"
	bare.at_most = 0.3
	bare.thought = _thought(&"bare_room", -2.0, 0.0)
	rules.append(bare)
	room_thoughts = BustleRoomThoughts.new(rules, society.ports)


func _step_one(id: StringName) -> void:
	var state := society.get_agent(id)
	var set := needs[id]
	var mood := moods[id]
	var conditions: Array[StringName] = [&"awake"]
	conditions.append_array(BustleEnvironmentPort.conditions_of(environment, id))
	set.advance(STEP, conditions)

	# What the brain senses: the needs, the routine's hours, the mood, and what is on offer.
	var senses := BustleSenses.new()
	senses.now_minutes = now()
	set.fill_inputs(senses.inputs)
	roster.schedule_of(id).fill_inputs(senses.inputs, now())
	mood.fill_inputs(senses.inputs)
	senses.advertisements.assign(_ads)
	var intent := state.brain.tick(STEP * 60.0, senses)

	# The host acts on the choice: where to go, then what happens on arrival.
	var target := _target(id, intent)
	targets[id] = target
	var spot: Vector3 = PLACES[target]
	state.position = state.position.move_toward(spot, WALK)
	var arrived := state.position.is_equal_approx(spot)
	var was := world.area_of(id)
	world.areas[id] = target if arrived else &"street"
	environment.set_room(id, target if arrived and ROOMS.has(target) else &"")
	if arrived:
		_arrive(id, target, was != target)
	room_thoughts_seen += room_thoughts.sync(id, mood).size()
	mood.advance_to(now())


func _target(id: StringName, intent: BustleIntent) -> StringName:
	if intent.goal_id == &"work":
		var current: Dictionary = roster.schedule_of(id).block_at(now())
		if current.get("block") != null:
			doing[id] = "working (%s)" % roster.job_of(id)
			return current["block"].place
	if intent.option_id == &"bakery":
		doing[id] = "eating"
		return &"bakery"
	if intent.option_id == &"home":
		doing[id] = "resting"
		return _home(id)
	doing[id] = "strolling"
	return &"square"


func _arrive(id: StringName, place: StringName, just_now: bool) -> void:
	var set := needs[id]
	if doing[id] == "eating":
		set.relieve(&"food", 0.35)
		if just_now:
			moods[id].add_thought(_bread)
			meals += 1
	elif doing[id] == "resting":
		set.relieve(&"rest", 0.3)
	elif doing[id].begins_with("working"):
		skills.add_xp(id, JOBS[roster.job_of(id)][3], 1.0)
		work_steps += 1


# Villagers strolling in the square greet each other (the social store keeps the opinions).
func _greet() -> void:
	var here: Array[StringName] = []
	for id: StringName in society.agent_ids():
		if world.area_of(id) == &"square":
			here.append(id)
	for a: StringName in here:
		for b: StringName in here:
			if a != b and interactions.greet(a, b, now(), &"square").get("ok", false):
				greetings += 1


static func _home(id: StringName) -> StringName:
	return StringName("home_%s" % id)


static func _need(id: StringName, rate: float) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = [&"awake"] as Array[StringName]
	return def


static func _thought(id: StringName, value: float, hours: float) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.duration_hours = hours
	def.reason_kind = &"environment" if hours == 0.0 else &"event"
	return def
