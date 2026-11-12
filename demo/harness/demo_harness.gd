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
## [br]- [code]attend[/code]: an agent turned up for a schedule block: [code]{activity, arrival}[/code];
## [br]- [code]event[/code]: a host event started or ended: [code]{event, phase}[/code];
## [br]- [code]state[/code] and [code]state_end[/code]: an agent entered a mental state
## ([code]{state, tier}[/code]) or left one ([code]{state, reason}[/code]), with mood on;
## [br]- [code]talk[/code]: a conversation turn: [code]{with, interaction}[/code], with social on;
## [br]- [code]thought[/code]: a thought came ([code]{thought, phase: "add", value, reason}[/code])
## or went ([code]{thought, phase: "end"}[/code]), with mood on;
## [br]- [code]stuck[/code] and [code]unstuck[/code]: [member stuck] judged an agent stuck
## ([code]{reason, since}[/code]) or moving again ([code]{reason, minutes}[/code]).
## [br][br]
## The optional modules are off until switched on, each before any agent is added:
## [method enable_mood] (needs_mood: a mood and a mental state per agent), [method enable_social]
## (the built-in social store, conversations and the comfort hook) and [method enable_perception]
## (who notices whom). With perception off, an agent notices everyone awake in its area.
## [br][br]
## Needs move on under these conditions: [code]asleep[/code] while using [member sleep_object];
## otherwise [code]awake[/code], plus [code]away[/code] and [code]in_company[/code] while away, or
## the usual [code]alone[/code] / [code]in_company[/code] / [code]crowded[/code] from whoever else
## is home ([method BustleNeedSet.social_conditions]). An active event ([method add_event]) adds its
## condition for everyone.

const Timeline := preload("res://demo/harness/demo_timeline.gd")
const UseAction := preload("res://demo/harness/demo_use_action.gd")
const StuckWatch := preload("res://demo/harness/demo_stuck_watch.gd")
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
## More objects that count as [member sleep_object].
var sleep_objects: Array[StringName] = []
## The area an agent starts in, before it uses anything.
var home_area: StringName = &""
## Object id → the thought an agent gets when a use of it finishes (with mood on).
var use_thoughts: Dictionary[StringName, BustleThoughtDef] = {}
## The goals whose options are other agents rather than objects (with social on).
var people_goals: Array[StringName] = [&"comfort"]

## Each agent's need thoughts, with mood on.
var need_thoughts: Array[BustleThoughtDef] = []
## The mood numbers, with mood on.
var mood_config: BustleMoodConfig = null
## The mental state numbers, with mood on.
var mental_config: BustleMentalConfig = null
## The social store, with social on.
var store: BustleSocialStore = null
## The comfort hook, with social on.
var comfort: BustleComfort = null
## The conversations, with social on.
var conversation: BustleConversation = null
## Who notices whom, with perception on.
var perception: BustlePerceptionWorld = null
## Watches every agent for being stuck (its bound and epsilon are experimental defaults).
var stuck := StuckWatch.new()

# id → {brain, needs, personality, schedule, away, last, dire, attended, using, area, position,
# mood, mental}
var _agents: Dictionary[StringName, Dictionary] = {}
var _use := UseAction.new()
var _converse: BustleConverseAction = null
var _profile: BustlePerceptionProfile = null
# {id, start, end, condition, thought, on}
var _events: Array[Dictionary] = []


func _init(p_world_seed: int = 0) -> void:
	world_seed = p_world_seed
	_use.affordances = affordances
	# The action reaches back through a weak reference, so the run and its action don't hold each
	# other alive.
	var me: WeakRef = weakref(self)
	_use.needs_of = func(id: StringName) -> BustleNeedSet: return me.get_ref().needs_of(id)
	_use.minutes_of = func(object: StringName) -> int: return me.get_ref().minutes_of(object)
	_use.on_used = func(id: StringName, object: StringName, minute: int) -> void:
		me.get_ref()._used(id, object, minute)


## Switches the needs_mood module on: each agent added after this gets a [BustleMood] (with
## [param thoughts] as its need thoughts) and a [BustleMentalState].
func enable_mood(thoughts: Array[BustleThoughtDef], config: BustleMoodConfig = null,
		mental: BustleMentalConfig = null) -> void:
	need_thoughts = thoughts
	mood_config = config if config != null else BustleMoodConfig.new()
	mental_config = mental if mental != null else BustleMentalConfig.new()


## Switches social on: conversations through [param p_store] with [param interactions], and the
## comfort hook, for agents added after this. Comfort needs mood on too: with no mood, nobody is
## low.
func enable_social(p_store: BustleSocialStore, interactions: Array[BustleInteractionDef]) -> void:
	store = p_store
	var social := BustleSocialInteractions.new(store, world_seed)
	var me: WeakRef = weakref(self)
	social.mood_of = func(id: StringName) -> Object: return me.get_ref().mood_of(id)
	conversation = BustleConversation.new(social, interactions)
	_converse = BustleConverseAction.new(conversation)
	comfort = BustleComfort.new()
	comfort.low_state_of = func(id: StringName) -> bool: return me.get_ref().in_low_state(id)


## Switches perception on: who an agent notices comes from a [BustlePerceptionWorld], each agent
## an actor with [param profile] at the place of the object it last used.
func enable_perception(profile: BustlePerceptionProfile) -> void:
	perception = BustlePerceptionWorld.new()
	_profile = profile


## Adds a host event [param id] from game minute [param start] for [param minutes]: while it lasts,
## everyone's needs also move on under [param condition], and when it starts every agent with a
## mood gets [param thought] (or none when null).
func add_event(id: StringName, start: int, minutes: int, condition: StringName,
		thought: BustleThoughtDef = null) -> void:
	_events.append({"id": id, "start": start, "end": start + minutes, "condition": condition,
		"thought": thought, "on": false})


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
	if _converse != null:
		brain.runner.register(&"converse", _converse)
		brain.score_boost = func(goal: StringName, option: StringName) -> float: return me.get_ref()._fits(goal, option)
	brain.orders.finished.connect(func(order_id: StringName, outcome: BustleOrderQueue.Outcome, _reason: StringName) -> void:
		var run: RefCounted = me.get_ref()
		run.timeline.add(run.now, id, &"order", {"order": String(order_id), "outcome": BustleOrderQueue.Outcome.keys()[outcome]}))
	var needs := BustleNeedSet.new()
	for def: BustleNeedDef in need_defs:
		needs.add_need(def)
	var mood: BustleMood = null
	var mental: BustleMentalState = null
	if mood_config != null:
		mood = BustleMood.new(mood_config, brain.modifiers)
		mood.start(now)
		mental = BustleMentalState.new(id, mental_config)
		mental.state_entered.connect(func(agent: StringName, state: StringName, info: Dictionary) -> void:
			me.get_ref().timeline.add(int(info["since"]), agent, &"state", {"state": String(state), "tier": String(info["tier"])}))
		mental.state_exited.connect(func(agent: StringName, state: StringName, reason: StringName) -> void:
			var run: RefCounted = me.get_ref()
			run.timeline.add(run.now, agent, &"state_end", {"state": String(state), "reason": String(reason)}))
	var personality := BustlePersonality.new()
	for def: BustleTraitDef in traits:
		personality.add_trait(def)
	personality.apply(brain.modifiers, needs, own, mood)
	_agents[id] = {"brain": brain, "needs": needs, "personality": personality,
		"schedule": BustleSchedule.new(routine) if routine != null else null, "away": false,
		"last": "", "dire": {}, "attended": {}, "using": &"", "area": home_area, "position": Vector3.ZERO,
		"mood": mood, "mental": mental, "thoughts": {}, "consumed": false, "using_since": now}
	if perception != null:
		var actor := BustlePerceptionActor.new()
		actor.id = id
		actor.profile = _profile
		perception.add_actor(actor)
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


## [param id]'s mood, or null with mood off.
func mood_of(id: StringName) -> BustleMood:
	return _agents[id]["mood"] if _agents.has(id) else null


## [param id]'s mental state, or null with mood off.
func mental_of(id: StringName) -> BustleMentalState:
	return _agents[id]["mental"] if _agents.has(id) else null


## True while [param id] is in a low mental state.
func in_low_state(id: StringName) -> bool:
	var mental := mental_of(id)
	return mental != null and mental.active().get("kind", "") == String(BustleMentalStateDef.LOW)


## The object [param id] is using, or empty.
func using_of(id: StringName) -> StringName:
	return _agents[id]["using"]


## True while [param id] uses an object and the use is still inside its expected time (the object's
## minutes, plus a step for the step it started in). A use that runs on past that doesn't count as
## a legitimate long activity for the stuck watch.
func using_on_time(id: StringName) -> bool:
	var agent := _agents[id]
	var object: StringName = agent["using"]
	return object != &"" and now - int(agent["using_since"]) <= minutes_of(object) + step_minutes


## True while [param id] sleeps.
func is_asleep(id: StringName) -> bool:
	return _sleeps_in(_agents[id]["using"])


## The area [param id] is in: that of the object it last used, or [member home_area].
func area_of(id: StringName) -> StringName:
	return _agents[id]["area"]


## Who [param id] notices now: other agents awake and at hand, through perception when it is on,
## else everyone awake in its area. Nobody, while [param id] sleeps or is away.
func noticed_by(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if is_asleep(id) or is_away(id):
		return out
	for other: StringName in agent_ids():
		if other == id or is_asleep(other) or is_away(other):
			continue
		var seen := perception.perceives(id, other) if perception != null else area_of(other) == area_of(id)
		if seen:
			out.append(other)
	return out


## The longest run of game minutes [param id]'s need [param need] stayed above
## [member dire_pressure] so far.
func dire_minutes(id: StringName, need: StringName) -> int:
	return int((_agents[id]["dire"] as Dictionary).get(need, {}).get("longest", 0))


## Runs one step for every agent, in id order. Returns each agent's intent.
func step() -> Dictionary[StringName, BustleIntent]:
	var intents: Dictionary[StringName, BustleIntent] = {}
	_update_events()
	if store != null:
		store.set_time(now)
	if perception != null:
		_sense()
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
	var asleep := _sleeps_in(agent["using"])
	var conditions: Array[StringName] = [&"asleep"]
	if not asleep:
		conditions = [&"in_company", &"away"]
		if not agent["away"]:
			conditions = BustleNeedSet.social_conditions(others_home, BustleNeedSet.crowd_tolerance(brain.modifiers))
		conditions.append(&"awake")
	for event: Dictionary in _events:
		if event["on"]:
			conditions.append(event["condition"])
	needs.advance(step_minutes, conditions, brain.modifiers)
	_track_dire(agent, needs)
	var personality: BustlePersonality = agent["personality"]
	var mood: BustleMood = agent["mood"]
	var senses := BustleSenses.new()
	senses.now_minutes = now
	needs.fill_inputs(senses.inputs)
	personality.fill_inputs(senses.inputs)
	if mood != null:
		mood.sync_need_thoughts(needs, need_thoughts)
		mood.advance_to(now, asleep)
		(agent["mental"] as BustleMentalState).update(now, mood, personality)
		mood.fill_inputs(senses.inputs)
	var schedule: BustleSchedule = agent["schedule"]
	if schedule != null:
		schedule.fill_inputs(senses.inputs, now)
	senses.advertisements = affordances.advertisements(id, now)
	if comfort != null:
		comfort.advertise(id, noticed_by(id), store, mood_of, senses)
	var intent := brain.tick(step_minutes * 60.0, senses)
	agent["away"] = intent.goal_id == AWAY_GOAL and intent.order_id == &""
	if intent.use_affordance != agent["using"]:
		agent["using_since"] = now
	agent["using"] = intent.use_affordance
	var used := affordances.get_affordance(intent.use_affordance) if intent.use_affordance != &"" else null
	if used != null:
		agent["area"] = used.area
		agent["position"] = used.position
	var turn: Dictionary = brain.runner.context.output.get("turn", {})
	if not turn.is_empty():
		timeline.add(now, id, &"talk", {"with": String(turn["recipient"] if turn["initiator"] == id else turn["initiator"]),
			"interaction": String(turn["interaction"])})
	if schedule != null and intent.goal_id != &"":
		var arrival := schedule.attend(now, intent.goal_id)
		var start := int(schedule.block_at(now).get("start", -1))
		if arrival != &"" and not (agent["attended"] as Dictionary).has(start):
			(agent["attended"] as Dictionary)[start] = true
			timeline.add(now, id, &"attend", {"activity": String(intent.goal_id), "arrival": String(arrival)})
	_note_thoughts(id, agent)
	_watch(id, agent, intent)
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


func _sleeps_in(object: StringName) -> bool:
	return object != &"" and (object == sleep_object or sleep_objects.has(object))


func _used(id: StringName, object: StringName, minute: int) -> void:
	timeline.add(minute, id, &"used", {"object": String(object)})
	_agents[id]["consumed"] = true
	var mood := mood_of(id)
	if mood != null and use_thoughts.has(object):
		mood.add_thought(use_thoughts[object], {"object": String(object)})


# Options that are agents are only for people goals, and objects only for the others.
func _fits(goal: StringName, option: StringName) -> float:
	if option == &"":
		return 1.0
	return 1.0 if people_goals.has(goal) == _agents.has(option) else 0.0


func _update_events() -> void:
	for event: Dictionary in _events:
		var on: bool = now >= int(event["start"]) and now < int(event["end"])
		if on == event["on"]:
			continue
		event["on"] = on
		timeline.add(now, &"", &"event", {"event": String(event["id"]), "phase": "start" if on else "end"})
		var thought: BustleThoughtDef = event["thought"]
		if on and thought != null:
			for id: StringName in agent_ids():
				var mood := mood_of(id)
				if mood != null:
					mood.add_thought(thought, {"event": String(event["id"])})


func _sense() -> void:
	for id: StringName in agent_ids():
		var actor := perception.actor(id)
		var hidden := is_asleep(id) or is_away(id)
		actor.position = _agents[id]["position"]
		actor.profile = null if hidden else _profile
		actor.perceivable = not hidden
	perception.tick(step_minutes * 60.0)


# Logs the thoughts that came and went since the last step: a thought is its id and expiry.
func _note_thoughts(id: StringName, agent: Dictionary) -> void:
	var mood: BustleMood = agent["mood"]
	if mood == null:
		return
	var had: Dictionary = agent["thoughts"]
	var have := {}
	for entry: Dictionary in mood.reasons():
		var key := "%s|%d" % [entry["thought"], int(entry["expires"])]
		have[key] = int(have.get(key, 0)) + 1
		if int(have[key]) > int(had.get(key, 0)):
			timeline.add(now, id, &"thought", {"thought": String(entry["thought"]), "phase": "add",
				"value": snappedf(float(entry["value"]), 0.001), "reason": _plain(entry["reason"])})
	var gone: Array = had.keys()
	gone.sort()
	for key: String in gone:
		for i: int in int(had[key]) - int(have.get(key, 0)):
			timeline.add(now, id, &"thought", {"thought": key.get_slice("|", 0), "phase": "end"})
	agent["thoughts"] = have


# Feeds the stuck watch what this agent did this step, and logs a change.
func _watch(id: StringName, agent: Dictionary, intent: BustleIntent) -> void:
	var schedule: BustleSchedule = agent["schedule"]
	var block: Dictionary = schedule.block_at(now) if schedule != null else {}
	var mental: BustleMentalState = agent["mental"]
	var state: Dictionary = mental.active() if mental != null else {}
	var legit: bool = _sleeps_in(agent["using"]) or using_on_time(id) or agent["away"] \
		or intent.order_id != &"" or intent.player_controlled \
		or (not block.is_empty() and StringName(block["block"].activity) == intent.goal_id) \
		or (not state.is_empty() and now < int(state["until"]))
	var change := stuck.observe(id, now, step_minutes, {"goal": intent.goal_id,
		"step": (agent["brain"] as BustleBrain).runner.step_index, "legit": legit,
		"consumed": agent["consumed"], "position": agent["position"], "place": agent["area"],
		"failed": not intent.failure.is_empty(),
		"state_overdue": not state.is_empty() and now >= int(state["until"])})
	agent["consumed"] = false
	if not change.is_empty():
		var kind := StringName(change["event"])
		change.erase("event")
		timeline.add(now, id, kind, change)


# A reason as plain data with its numbers rounded, so the timeline reads the same everywhere.
static func _plain(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, 0.001)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[String(key)] = _plain(value[key])
		return out
	if value is StringName:
		return String(value)
	return value
