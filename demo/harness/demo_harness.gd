# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## Runs a small demo population headless, one fixed step of game time at a time, the way a host
## would: for each agent in id order it moves the needs on, fills the senses (needs, schedule,
## personality and the objects it can use), ticks the brain and acts on the intent. Agents and
## objects are plain data, so a scene and a test drive the same run.
##
## What it logs to [member timeline] (see [code]demo/README.md[/code]):
## [br]- [code]choice[/code]: an agent's choice changed: [code]{goal, option, order}[/code];
## [br]- [code]used[/code]: a use of an object finished: [code]{object}[/code];
## [br]- [code]order[/code]: an order finished: [code]{order, outcome}[/code];
## [br]- [code]attend[/code]: an agent turned up for a schedule block: [code]{activity, arrival}[/code].
## [br][br]
## Needs move on under these conditions: [code]asleep[/code] while using [member sleep_object];
## otherwise [code]awake[/code], plus [code]away[/code] and [code]in_company[/code] while away, or
## the usual [code]alone[/code] / [code]in_company[/code] / [code]crowded[/code] from whoever else
## is home ([method BustleNeedSet.social_conditions]).

const Timeline := preload("res://demo/harness/demo_timeline.gd")
const UseAction := preload("res://demo/harness/demo_use_action.gd")
## The goal an agent pursues while it is away (off site, so out of company at home).
const AWAY_GOAL := &"work"

## Game minutes per step.
var step_minutes: int = 10
## The current game minute.
var now: int = 0
## The world seed.
var world_seed: int = 0
## The objects.
var affordances := BustleAffordanceSet.new()
## The run's log.
var timeline := Timeline.new()
## Object id → game minutes one use takes.
var use_minutes: Dictionary[StringName, int] = {}
## The object an agent sleeps in: while it's using it, its needs move on under [code]asleep[/code]
## instead of [code]awake[/code].
var sleep_object: StringName = &"bed"
## The scorer's curves and settings, shared by every agent added after it is set.
var scoring := BustleScoringConfig.new()
## The pressure above which a need counts as dire (see [method dire_minutes]).
var dire_pressure: float = 0.95

# id → {brain, needs, personality, schedule, away, last, dire}
var _agents: Dictionary[StringName, Dictionary] = {}
var _use := UseAction.new()


func _init(p_world_seed: int = 0) -> void:
	world_seed = p_world_seed
	_use.affordances = affordances
	# The action reaches back through a weak reference, so the run and its action don't hold each
	# other alive.
	var me: WeakRef = weakref(self)
	_use.needs_of = func(id: StringName) -> BustleNeedSet: return me.get_ref().needs_of(id)
	_use.minutes_of = func(object: StringName) -> int: return me.get_ref().minutes_of(object)
	_use.on_used = func(id: StringName, object: StringName, minute: int) -> void:
		me.get_ref().timeline.add(minute, id, &"used", {"object": String(object)})


## Places [param affordance], used for [param minutes] game minutes at a time.
func add_object(affordance: BustleAffordance, minutes: int) -> void:
	affordances.add(affordance)
	use_minutes[affordance.id] = minutes


## Adds agent [param id] with [param library], [param need_defs], [param traits] and an optional
## routine. Returns its brain.
func add_agent(id: StringName, library: BustleGoalLibrary, need_defs: Array[BustleNeedDef],
		traits: Array[BustleTraitDef] = [], routine: BustleScheduleDef = null) -> BustleBrain:
	var own := BustleGoalLibrary.new()
	own.goals = library.goals.duplicate()
	var brain := BustleBrain.new(id, own, scoring, world_seed)
	brain.runner.register(&"use", _use)
	var me: WeakRef = weakref(self)
	brain.orders.finished.connect(func(order_id: StringName, outcome: BustleOrderQueue.Outcome, _reason: StringName) -> void:
		var run: RefCounted = me.get_ref()
		run.timeline.add(run.now, id, &"order", {"order": String(order_id), "outcome": BustleOrderQueue.Outcome.keys()[outcome]}))
	var needs := BustleNeedSet.new()
	for def: BustleNeedDef in need_defs:
		needs.add_need(def)
	var personality := BustlePersonality.new()
	for def: BustleTraitDef in traits:
		personality.add_trait(def)
	personality.apply(brain.modifiers, needs, own)
	_agents[id] = {"brain": brain, "needs": needs, "personality": personality,
		"schedule": BustleSchedule.new(routine) if routine != null else null, "away": false,
		"last": "", "dire": {}, "attended": {}, "using": &""}
	return brain


## The agents' ids, sorted.
func agent_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_agents.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## [param id]'s brain.
func brain_of(id: StringName) -> BustleBrain:
	return _agents[id]["brain"]


## [param id]'s needs.
func needs_of(id: StringName) -> BustleNeedSet:
	return _agents[id]["needs"]


## How many game minutes one use of [param object] takes.
func minutes_of(object: StringName) -> int:
	return use_minutes.get(object, step_minutes)


## [param id]'s routine, or null.
func schedule_of(id: StringName) -> BustleSchedule:
	return _agents[id]["schedule"]


## True while [param id] is away (pursuing [constant AWAY_GOAL]).
func is_away(id: StringName) -> bool:
	return _agents[id]["away"]


## The longest run of game minutes [param id]'s need [param need] stayed above
## [member dire_pressure] so far.
func dire_minutes(id: StringName, need: StringName) -> int:
	return int((_agents[id]["dire"] as Dictionary).get(need, {}).get("longest", 0))


## Runs one step for every agent, in id order. Returns each agent's intent.
func step() -> Dictionary[StringName, BustleIntent]:
	var intents: Dictionary[StringName, BustleIntent] = {}
	var home := 0
	for id: StringName in agent_ids():
		if not is_away(id):
			home += 1
	for id: StringName in agent_ids():
		intents[id] = _step_agent(id, home - (0 if is_away(id) else 1))
	now += step_minutes
	return intents


## Runs whole steps until at least [param minutes] more game minutes have passed.
func run(minutes: int) -> void:
	var until := now + minutes
	while now < until:
		step()


func _step_agent(id: StringName, others_home: int) -> BustleIntent:
	var agent := _agents[id]
	var brain: BustleBrain = agent["brain"]
	var needs: BustleNeedSet = agent["needs"]
	# Asleep, an agent is in no company at all; away, it is among others; at home, it is with
	# whoever else is home.
	var conditions: Array[StringName] = [&"asleep"]
	if agent["using"] != sleep_object:
		conditions = [&"in_company", &"away"]
		if not agent["away"]:
			conditions = BustleNeedSet.social_conditions(others_home, BustleNeedSet.crowd_tolerance(brain.modifiers))
		conditions.append(&"awake")
	needs.advance(step_minutes, conditions, brain.modifiers)
	_track_dire(agent, needs)
	var senses := BustleSenses.new()
	senses.now_minutes = now
	needs.fill_inputs(senses.inputs)
	(agent["personality"] as BustlePersonality).fill_inputs(senses.inputs)
	var schedule: BustleSchedule = agent["schedule"]
	if schedule != null:
		schedule.fill_inputs(senses.inputs, now)
	senses.advertisements = affordances.advertisements(id, now)
	var intent := brain.tick(step_minutes * 60.0, senses)
	agent["away"] = intent.goal_id == AWAY_GOAL and intent.order_id == &""
	agent["using"] = intent.use_affordance
	if schedule != null and intent.goal_id != &"":
		var arrival := schedule.attend(now, intent.goal_id)
		var start := int(schedule.block_at(now).get("start", -1))
		if arrival != &"" and not (agent["attended"] as Dictionary).has(start):
			(agent["attended"] as Dictionary)[start] = true
			timeline.add(now, id, &"attend", {"activity": String(intent.goal_id), "arrival": String(arrival)})
	var choice := "%s|%s|%s" % [intent.goal_id, intent.option_id, intent.order_id]
	if intent.player_controlled:
		choice = "player"
	if choice != agent["last"]:
		agent["last"] = choice
		timeline.add(now, id, &"choice", {"goal": String(intent.goal_id), "option": String(intent.option_id),
			"order": String(intent.order_id)} if not intent.player_controlled else {"player": 1})
	return intent


func _track_dire(agent: Dictionary, needs: BustleNeedSet) -> void:
	var dire: Dictionary = agent["dire"]
	for need: StringName in needs.ids():
		var row: Dictionary = dire.get(need, {"run": 0, "longest": 0})
		row["run"] = int(row["run"]) + step_minutes if needs.pressure(need) > dire_pressure else 0
		row["longest"] = maxi(int(row["longest"]), int(row["run"]))
		dire[need] = row
