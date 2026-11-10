# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMentalBehaviour
extends RefCounted

## What agents do in a mental state, for a whole society: the circumstances each
## [BustleMentalState] decides from, the state's modifiers, the goals that act it out (in
## [constant BustleBands.GUARDED], so urgent self-care outranks them and orders and duty don't), and
## lashing out.
## [br][br]
## [b]Modifiers.[/b] While an agent is in a state, [member BustleMentalConfig.state_modifiers] for
## it are set on the agent's [BustleModifierSet] (its mood's), and removed when it ends.
## [br][b]Goals[/b] ([method goal_defs], each running the [code]mental[/code] action,
## [BustleMentalAction]): withdraw goes home and turns others away ([method accepts]), wander walks
## about, binge uses the indulgence it
## knows of, and lash out goes to its target and insults it. Sulk, high spirits and inspiration are
## modifiers only.
## [br][b]Locks.[/b] While [member is_locked] holds, no state starts, the goals aren't eligible and
## the modifiers are off; when it ends, the state is evaluated again.
## [br][b]Lashing out[/b] is words only. The target is the most disliked person nearby: in the same
## area and within [member BustleMentalConfig.lash_radius], disliked (opinion below the dislike
## line) or a rival; rivals first, then the lowest opinion, ties by id. Each person can be
## insulted at most [member BustleMentalConfig.insults_per_victim] times an episode. The insult is
## emitted as [signal insulted]; with a [member conflict], the insulted agent then quarrels through
## the usual fight rules, which never mean to kill. Nothing here sets any intent.
## @experimental

## [param agent], in a state, insulted [param target] (words only). [param provocation] is how hard,
## 0 to 1, from the state's tier.
signal insulted(agent: StringName, target: StringName, provocation: float)

## The brain input prefix: [code]fact.mental.<state id>[/code] is 1 while that state's goal can run.
const INPUT_PREFIX := "fact.mental."
## The modifier source the state's modifiers are set under.
const SOURCE := &"mental_state"
## The states that have a goal.
const GOAL_STATES: Array[StringName] = [&"withdraw", &"wander", &"binge", &"lash_out"]

## The agents, their areas and the social and world ports.
var society: BustleSociety
## The states and numbers.
var config: BustleMentalConfig
## Optional: the insulted agent quarrels through it.
var conflict: BustleConflict
## (id) → true while the agent is locked to a task. Empty: never.
var is_locked: Callable = Callable()
## (id) → the affordance it would indulge in (an id), or empty. Empty: none.
var indulgence_of: Callable = Callable()
## (id) → where the agent or person is (a [Vector3]), or null. Empty: the world position of its
## area.
var position_of: Callable = Callable()
## (id) → where home is (a [Vector3]), or null. Empty: none (withdraw then stays put).
var home_of: Callable = Callable()
## (id, now) → where to wander to (a [Vector3]), or null. Empty: the agent's neighbouring areas in
## turn, by the hour.
var wander_to: Callable = Callable()

var _states: Dictionary[StringName, BustleMentalState] = {}
var _insulted: Dictionary[StringName, Dictionary] = {}
var _applied: Dictionary[StringName, Dictionary] = {}


func _init(p_society: BustleSociety = null, p_config: BustleMentalConfig = null) -> void:
	society = p_society if p_society != null else BustleSociety.new()
	config = p_config if p_config != null else BustleMentalConfig.new()


## [param agent]'s state, made on first use.
## @experimental
func state_of(agent: StringName) -> BustleMentalState:
	if not _states.has(agent):
		var state := BustleMentalState.new(agent, config)
		state.state_entered.connect(_on_entered)
		_states[agent] = state
	return _states[agent]


## True while [param agent] is in a low state (for the comfort hook).
## @experimental
func in_low_state(agent: StringName) -> bool:
	return _states.has(agent) and _states[agent].active().get("kind", "") == String(BustleMentalStateDef.LOW)


## Updates [param agent] at minute [param now] (after its [param mood] has advanced): its state,
## from [method circumstances_of], and its modifiers. Returns the active state.
## @experimental
func update(agent: StringName, now: int, mood: BustleMood, personality: BustlePersonality = null) -> Dictionary:
	var circumstances := circumstances_of(agent, personality)
	var active := state_of(agent).update(now, mood, personality, circumstances)
	var mods := mood.modifiers
	var want := &"" if active.is_empty() or circumstances["locked"] or mods == null else StringName(active["id"])
	if _applied.has(agent) and (_applied[agent]["mods"] != mods or _applied[agent]["id"] != want):
		(_applied[agent]["mods"] as BustleModifierSet).remove_source(SOURCE)
		_applied.erase(agent)
	if want != &"" and not _applied.has(agent):
		var rows: Dictionary = config.state_modifiers.get(want, {})
		for key: StringName in rows:
			mods.set_source(SOURCE, key, float(rows[key][0]), float(rows[key][1]))
		_applied[agent] = {"mods": mods, "id": want}
	return active


## The state whose modifiers are on [param agent]'s modifier set now, or empty.
## @experimental
func applied_state(agent: StringName) -> StringName:
	return _applied[agent]["id"] if _applied.has(agent) else &""


## Whether [param agent] lets [param visitor] start a conversation or a visit now: not while it's
## withdrawn (and not locked), unless [param opener] is one of
## [member BustleMentalConfig.welcome_openers] (comfort, by default). For
## [member BustleConversation.accepts]; a host's own visits ask it too.
## @experimental
func accepts(agent: StringName, _visitor: StringName, opener: StringName = &"") -> bool:
	if not _states.has(agent) or StringName(_states[agent].active().get("id", "")) != &"withdraw":
		return true
	return (is_locked.is_valid() and bool(is_locked.call(agent))) or config.welcome_openers.has(opener)


## What [param agent]'s state decides from now: [code]{locked, indulgence, target, target_opinion,
## target_rival}[/code].
## @experimental
func circumstances_of(agent: StringName, _personality: BustlePersonality = null) -> Dictionary:
	var target := lash_target(agent)
	var social := society.ports.social
	return {"locked": is_locked.is_valid() and bool(is_locked.call(agent)),
		"indulgence": _indulgence(agent) != &"", "target": String(target),
		"target_opinion": float(social.opinion(agent, target)) if target != &"" else 50.0,
		"target_rival": target != &"" and social.kinds_between(agent, target).has("rival")}


## The most disliked person [param agent] could lash out at now, or empty: someone else in its
## area within [member BustleMentalConfig.lash_radius], disliked or a rival, and not insulted
## to the limit this episode. Rivals first, then the lowest opinion, then by id.
## @experimental
func lash_target(agent: StringName) -> StringName:
	var me := society.get_agent(agent)
	if me == null:
		return &""
	var social := society.ports.social
	var here: Variant = _where(agent)
	var best := &""
	var best_key := []
	for other: StringName in society.agent_ids():
		var them := society.get_agent(other)
		if other == agent or them.area != me.area or int(_insulted.get(agent, {}).get(other, 0)) >= config.insults_per_victim:
			continue
		var there: Variant = _where(other)
		if here is Vector3 and there is Vector3 and (here as Vector3).distance_to(there) > config.lash_radius:
			continue
		var rival := social.kinds_between(agent, other).has("rival")
		var opinion := float(social.opinion(agent, other))
		if not rival and opinion >= config.dislike_line:
			continue
		var key := [0 if rival else 1, opinion, String(other)]
		if best == &"" or _before(key, best_key):
			best = other
			best_key = key
	return best


static func _before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Sets each state goal's input in [param inputs]: 1 while [param agent] is in that state, isn't
## locked, and (for binge and lash out) has something to indulge in or someone to lash out at.
## @experimental
func fill_inputs(agent: StringName, inputs: Dictionary[StringName, float]) -> void:
	for id: StringName in GOAL_STATES:
		inputs.erase(StringName(INPUT_PREFIX + String(id)))
	if not _states.has(agent) or (is_locked.is_valid() and bool(is_locked.call(agent))):
		return
	var id := StringName(_states[agent].active().get("id", ""))
	if not GOAL_STATES.has(id) or (id == &"binge" and _indulgence(agent) == &"") or (id == &"lash_out" and lash_target(agent) == &""):
		return
	inputs[StringName(INPUT_PREFIX + String(id))] = 1.0


## [param agent] insults [param target] at minute [param now], if that's still allowed: it must be
## in a state, and [param target] must be its [method lash_target]. Emits [signal insulted]; with a
## [member conflict], [param target] then quarrels with [param agent] through the fight rules.
## True when it insulted.
## @experimental
func insult(agent: StringName, target: StringName, now: int) -> bool:
	if not _states.has(agent) or not _states[agent].is_active() or target == &"" or lash_target(agent) != target:
		return false
	var counts: Dictionary = _insulted.get_or_add(agent, {})
	counts[target] = int(counts.get(target, 0)) + 1
	var provocation := float(config.provocation.get(StringName(_states[agent].active()["tier"]), 0.2))
	insulted.emit(agent, target, provocation)
	if conflict != null:
		conflict.quarrel(target, agent, now, provocation)
	return true


## Where [param id] is, for moving towards it: [member position_of], else its area's position.
## @experimental
func position(id: StringName) -> Variant:
	return _where(id)


## Where [param agent] should be heading in its state at minute [param now] (a [Vector3]), or null.
## @experimental
func destination(agent: StringName, now: int) -> Variant:
	match StringName(state_of(agent).active().get("id", "")):
		&"withdraw":
			return home_of.call(agent) if home_of.is_valid() else null
		&"wander":
			if wander_to.is_valid():
				return wander_to.call(agent, now)
			var me := society.get_agent(agent)
			var around := society.ports.world.neighbour_areas(me.area) if me != null else [] as Array[StringName]
			return society.ports.world.place_position(around[floori(now / 60.0) % around.size()]) if not around.is_empty() else null
		&"lash_out":
			return _where(lash_target(agent))
	return null


## The affordance [param agent] would indulge in, or empty.
## @experimental
func indulgence(agent: StringName) -> StringName:
	return _indulgence(agent)


## Every agent's state and this episode's insults, as plain data.
## @experimental
func export_state() -> Dictionary:
	var states := {}
	for id: StringName in _states:
		states[String(id)] = _states[id].export_state()
	var insults := {}
	for id: StringName in _insulted:
		insults[String(id)] = _insulted[id].duplicate()
	return {"states": states, "insulted": insults}


## Restores [method export_state]. False (and nothing changes) when malformed. On success, the
## state modifiers set so far are taken off; the next [method update] sets the loaded states'.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("states") is Dictionary or not saved.get("insulted") is Dictionary:
		return false
	var staged: Dictionary[StringName, BustleMentalState] = {}
	for id: Variant in saved["states"]:
		var state := BustleMentalState.new(StringName(str(id)), config)
		if not id is String or not state.import_state(saved["states"][id]):
			return false
		state.state_entered.connect(_on_entered)
		staged[StringName(id)] = state
	var insults: Dictionary[StringName, Dictionary] = {}
	for id: Variant in saved["insulted"]:
		var row: Variant = saved["insulted"][id]
		if not id is String or not row is Dictionary or not (row as Dictionary).values().all(func(n: Variant) -> bool: return n is int and n > 0):
			return false
		insults[StringName(id)] = (row as Dictionary).duplicate()
	for agent: StringName in _applied:
		(_applied[agent]["mods"] as BustleModifierSet).remove_source(SOURCE)
	_applied.clear()
	_states = staged
	_insulted = insults
	return true


## The goals that act out withdraw, wander, binge and lash out: one per state, in
## [constant BustleBands.GUARDED], eligible while [code]fact.mental.<id>[/code] is 1, each running
## the [code]mental[/code] action.
## @experimental
static func goal_defs() -> Array[BustleGoalDef]:
	var out: Array[BustleGoalDef] = []
	for id: StringName in GOAL_STATES:
		var goal: BustleGoalDef = BustleCrime.goal_defs()[0]
		goal.id = StringName("mental_" + String(id))
		goal.considerations[0].input = StringName(INPUT_PREFIX + String(id))
		goal.sequence.steps[0].action = &"mental"
		out.append(goal)
	return out


func _on_entered(agent: StringName, _id: StringName, _info: Dictionary) -> void:
	_insulted.erase(agent)


func _indulgence(agent: StringName) -> StringName:
	return StringName(indulgence_of.call(agent)) if indulgence_of.is_valid() else &""


func _where(id: StringName) -> Variant:
	if id == &"":
		return null
	if position_of.is_valid():
		return position_of.call(id)
	var state := society.get_agent(id)
	return society.ports.world.place_position(state.area) if state != null else null
