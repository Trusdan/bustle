# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWyrdFacts
extends RefCounted

## Dialogue facts: what an agent is doing and how it feels, registered in Wyrd as host functions
## with Wyrd's stable [code]register_function[/code], so content can ask, for example,
## [code]npc_goal(x)[/code]. Wyrd calls a host callable; it never names Bustle.
##
## @experimental
## Each function takes the agent as an [code]entity[/code]. An unknown agent, or one with nothing
## to report yet, gives an empty symbol or 0.
##
## [codeblock]
## npc_goal(entity) -> symbol          the goal it chose on its last tick, or empty when idle
## npc_goal_reason(entity) -> symbol   the need that weighed most in that choice, or empty
## npc_need(entity, symbol) -> float   that need's pressure on its last tick, 0 to 1
## npc_top_need(entity) -> symbol      its most pressing need (ties by id), or empty
## npc_mood_band(entity) -> symbol     low, normal or high, by mood_bands
## npc_emotion(entity) -> symbol       its dominant emotion
## npc_mood_reason(entity) -> symbol   its strongest active thought
## [/codeblock]
##
## Goal and needs come from the agent's brain. Mood comes from [member mood_of]; without it the
## three mood functions report nothing.

## The function names, in a fixed order.
const NAMES: PackedStringArray = [
	"npc_goal", "npc_goal_reason", "npc_need", "npc_top_need", "npc_mood_band", "npc_emotion",
	"npc_mood_reason",
]
## [method mood_band] below [member BustleMentalConfig.break_threshold].
const LOW := &"low"
## [method mood_band] between the two lines.
const NORMAL := &"normal"
## [method mood_band] above [member BustleMentalConfig.high_spirits_above].
const HIGH := &"high"

## (id) → that agent's mood: anything with a [code]mood[/code] number, an [code]emotion[/code] and
## [code]reasons()[/code], such as a [BustleMood]; or null. Empty: nobody has a mood.
var mood_of: Callable = Callable()
## The lines between mood bands: the mental states' own lines, so a low band is where low states
## start and a high band is where high spirits can.
var mood_bands := BustleMentalConfig.new()

var _society: WeakRef = null


## Facts about the agents of [param society].
func _init(society: BustleSociety = null) -> void:
	_society = weakref(society) if society != null else null


## Registers every function in [param wyrd] with [code]register_function[/code]. Returns the names
## Wyrd accepted (a name already registered there is refused, with Wyrd's error).
## @experimental
func register(wyrd: Object) -> PackedStringArray:
	var done := PackedStringArray()
	if wyrd == null:
		return done
	var table := [
		[&"npc_goal", func(args: Array) -> StringName: return goal(_id(args)), [&"entity"], &"symbol"],
		[&"npc_goal_reason", func(args: Array) -> StringName: return goal_reason(_id(args)), [&"entity"], &"symbol"],
		[&"npc_need", func(args: Array) -> float: return need(_id(args), StringName(str(args[1]))), [&"entity", &"symbol"], &"float"],
		[&"npc_top_need", func(args: Array) -> StringName: return top_need(_id(args)), [&"entity"], &"symbol"],
		[&"npc_mood_band", func(args: Array) -> StringName: return mood_band(_id(args)), [&"entity"], &"symbol"],
		[&"npc_emotion", func(args: Array) -> StringName: return emotion(_id(args)), [&"entity"], &"symbol"],
		[&"npc_mood_reason", func(args: Array) -> StringName: return mood_reason(_id(args)), [&"entity"], &"symbol"],
	]
	for row: Array in table:
		if wyrd.call(&"register_function", row[0], row[1], row[2], row[3]):
			done.append(String(row[0]))
	return done


## The goal [param id] chose on its last tick, or empty when idle or unknown.
## @experimental
func goal(id: StringName) -> StringName:
	var brain := _brain(id)
	if brain == null or brain.last_intent == null or brain.last_intent.idle:
		return &""
	return brain.last_intent.goal_id


## The need that weighed most in [param id]'s last choice (ties by id), or empty when no need did.
## @experimental
func goal_reason(id: StringName) -> StringName:
	var brain := _brain(id)
	if brain == null or brain.last_intent == null or brain.last_intent.idle:
		return &""
	for candidate: BustleCandidate in brain.last_candidates:
		if candidate.goal_id != brain.last_intent.goal_id or candidate.option_id != brain.last_intent.option_id:
			continue
		var best := &""
		var best_value := -INF
		for reason: Dictionary in candidate.reasons:
			if reason.get("kind") != &"need":
				continue
			var value := float(reason.get("value", 0.0))
			var named := StringName(reason.get("need", &""))
			if value > best_value or (value == best_value and String(named) < String(best)):
				best = named
				best_value = value
		return best
	return &""


## [param need_id]'s pressure for [param id] on its last tick, 0 to 1. 0 when unknown.
## @experimental
func need(id: StringName, need_id: StringName) -> float:
	var inputs := _inputs(id)
	return clampf(float(inputs.get(StringName("need." + String(need_id)), 0.0)), 0.0, 1.0)


## [param id]'s most pressing need on its last tick (ties by id), or empty when it has none above 0.
## @experimental
func top_need(id: StringName) -> StringName:
	var best := &""
	var best_value := 0.0
	var inputs := _inputs(id)
	var keys: Array = inputs.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for key: StringName in keys:
		if not String(key).begins_with("need.") or String(key).count(".") != 1:
			continue
		var value := float(inputs[key])
		if value > best_value:
			best = StringName(String(key).substr(5))
			best_value = value
	return best


## [param id]'s mood band: [constant LOW] below [member BustleMentalConfig.break_threshold],
## [constant HIGH] above [member BustleMentalConfig.high_spirits_above], else [constant NORMAL].
## Empty with no mood.
## @experimental
func mood_band(id: StringName) -> StringName:
	var mood := _mood(id)
	if mood == null:
		return &""
	var value := float(mood.get(&"mood"))
	if value < mood_bands.break_threshold:
		return LOW
	if value > mood_bands.high_spirits_above:
		return HIGH
	return NORMAL


## [param id]'s dominant emotion, or empty.
## @experimental
func emotion(id: StringName) -> StringName:
	var mood := _mood(id)
	return StringName(mood.get(&"emotion")) if mood != null else &""


## [param id]'s strongest active thought, or empty.
## @experimental
func mood_reason(id: StringName) -> StringName:
	var mood := _mood(id)
	if mood == null:
		return &""
	var reasons: Array = mood.call(&"reasons")
	return StringName((reasons[0] as Dictionary).get("thought", &"")) if not reasons.is_empty() else &""


func _id(args: Array) -> StringName:
	return StringName(str(args[0])) if not args.is_empty() else &""


func _brain(id: StringName) -> BustleBrain:
	var society := _society.get_ref() as BustleSociety if _society != null else null
	var state := society.get_agent(id) if society != null and id != &"" else null
	return state.brain if state != null else null


func _inputs(id: StringName) -> Dictionary:
	var brain := _brain(id)
	if brain == null or brain.last_senses == null:
		return {}
	return brain.last_senses.inputs


func _mood(id: StringName) -> Object:
	if not mood_of.is_valid() or _brain(id) == null:
		return null
	return mood_of.call(id) as Object
