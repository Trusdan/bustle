# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConversation
extends RefCounted

## A conversation: a few turns between two agents, each turn one interaction picked by weight and
## recorded through [method BustleSocialInteractions.interact]. The two sides take turns to speak,
## the initiator first.
## [br][br]
## It runs two ways with the same results. [method run] does a whole conversation at once (for
## agents nobody is watching); [BustleConverseAction] does one turn per tick (for agents in view).
## Both go through [method begin] and [method step], which keep everything in a plain-data state,
## and every choice is seeded by the world seed, the pair, the start minute and the turn, never by
## when a tick happens.
## [br][br]
## An interaction's weight is its [member BustleInteractionDef.weight], bent by:
## [br]- the speaker's sliders ([member BustleInteractionDef.slider_weights]);
## [br]- the speaker's modifiers: [code]conversation.<id>.weight[/code], which traits set;
## [br]- the speaker's opinion of the listener: a high one makes positive interactions likelier and
## negative ones rarer ([member opinion_weight]);
## [br]- the speaker's mood: below 50, [code]curt[/code] interactions grow likelier
## ([member curt_mood_scale]).
## [br]A low mood also lowers the chance of starting at all ([member start_mood_scale]).
## @experimental

## Where the interactions are recorded, with the world seed and moods.
var social: BustleSocialInteractions
## The interactions a conversation picks from.
var interactions: Array[BustleInteractionDef] = []
## Turns in a conversation, both sides together.
var turns: int = 4
## Game minutes between turns.
var turn_minutes: int = 1
## The chance of starting a conversation in a neutral or good mood (0 to 1).
var start_chance: float = 1.0
## How much a low mood lowers [member start_chance]: at mood 0 it is multiplied by
## [code]1 − start_mood_scale[/code].
var start_mood_scale: float = 0.5
## How much a low mood raises the weight of [code]curt[/code] interactions: at mood 0 it is
## multiplied by [code]1 + curt_mood_scale[/code].
var curt_mood_scale: float = 1.0
## How much opinion bends weights: a positive interaction's weight is multiplied by
## [code]1 + opinion_weight × (opinion − 50) / 50[/code], a negative one's by
## [code]1 − ...[/code] (never below 0).
var opinion_weight: float = 1.0
## (id) → that agent's [BustlePersonality], or null. Empty: nobody has one.
var personality_of: Callable = Callable()
## (id) → that agent's [BustleModifierSet], or null. Empty: nobody has one.
var modifiers_of: Callable = Callable()


func _init(p_social: BustleSocialInteractions = null, p_interactions: Array[BustleInteractionDef] = []) -> void:
	social = p_social if p_social != null else BustleSocialInteractions.new()
	interactions = p_interactions


## The chance that [param initiator] starts a conversation, given its mood.
## @experimental
func chance_to_start(initiator: StringName) -> float:
	var low := _low(_mood(initiator))
	return clampf(start_chance * maxf(1.0 - start_mood_scale * low, 0.0), 0.0, 1.0)


## Whether [param initiator] starts a conversation with [param recipient] at minute [param now]:
## a roll against [method chance_to_start], the same every time for the same inputs.
## @experimental
func wants_to_start(initiator: StringName, recipient: StringName, now: int) -> bool:
	return _roll(["start", initiator, recipient, now]) < chance_to_start(initiator)


## A new conversation's state (plain data, safe to save), or an empty dictionary when the pair is
## not two different agents. [param opener], when given, is the id of the first turn's interaction,
## picked even when its weight is 0.
## @experimental
func begin(initiator: StringName, recipient: StringName, now: int, opener: StringName = &"",
		place: StringName = &"") -> Dictionary:
	if initiator == &"" or recipient == &"" or initiator == recipient:
		return {}
	return {"a": String(initiator), "b": String(recipient), "start": now, "turn": 0, "turns": maxi(turns, 0),
		"opener": String(opener), "place": String(place)}


## The game minute [param state]'s next turn happens at.
## @experimental
func next_minute(state: Dictionary) -> int:
	return int(state.get("start", 0)) + int(state.get("turn", 0)) * maxi(turn_minutes, 0)


## True when [param state] has no turns left.
## @experimental
func is_finished(state: Dictionary) -> bool:
	return int(state.get("turn", 0)) >= int(state.get("turns", 0))


## Takes [param state]'s next turn at [method next_minute] and moves the state on. Returns the
## turn's [method BustleSocialInteractions.interact] result with its [code]turn[/code] number, or
## [code]{ok: false, reason}[/code]: [code]finished[/code], or [code]nothing_to_say[/code] (no
## interaction has any weight, which also ends the conversation).
## @experimental
func step(state: Dictionary) -> Dictionary:
	if state.is_empty() or is_finished(state):
		return {"ok": false, "reason": &"finished"}
	var turn := int(state["turn"])
	var speaker := StringName(state["a"] if turn % 2 == 0 else state["b"])
	var listener := StringName(state["b"] if turn % 2 == 0 else state["a"])
	var minute := next_minute(state)
	var def: BustleInteractionDef = null
	if turn == 0 and state.get("opener", "") != "":
		def = _find(StringName(state["opener"]))
	if def == null:
		def = pick(speaker, listener, _roll(["turn", state["a"], state["b"], int(state["start"]), turn]))
	if def == null:
		state["turn"] = state["turns"]
		return {"ok": false, "reason": &"nothing_to_say"}
	state["turn"] = turn + 1
	var result := social.interact(def, speaker, listener, minute, StringName(state.get("place", "")))
	result["turn"] = turn
	return result


## A whole conversation at once: [method wants_to_start], then every turn. Returns
## [code]{ok: true, turns}[/code] with each turn's result, or [code]{ok: false, reason}[/code]
## ([code]declined[/code] or [code]no_pair[/code]).
## @experimental
func run(initiator: StringName, recipient: StringName, now: int, opener: StringName = &"",
		place: StringName = &"") -> Dictionary:
	var state := begin(initiator, recipient, now, opener, place)
	if state.is_empty():
		return {"ok": false, "reason": &"no_pair"}
	if not wants_to_start(initiator, recipient, now):
		return {"ok": false, "reason": &"declined"}
	var results: Array[Dictionary] = []
	while not is_finished(state):
		var result := step(state)
		if result.get("ok", false):
			results.append(result)
	return {"ok": true, "turns": results}


## Each interaction's weight for [param speaker] talking to [param listener] (see the class
## description), by id, in [member interactions] order. Invalid interactions are left out.
## @experimental
func weights(speaker: StringName, listener: StringName) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	var personality: Variant = personality_of.call(speaker) if personality_of.is_valid() else null
	var modifiers: Variant = modifiers_of.call(speaker) if modifiers_of.is_valid() else null
	var opinion_lift := opinion_weight * (social.store.opinion(speaker, listener) - 50.0) / 50.0
	var curt := 1.0 + curt_mood_scale * _low(_mood(speaker))
	for def: BustleInteractionDef in interactions:
		if def == null or not def.is_valid() or out.has(def.id):
			continue
		var w := def.weight
		if personality is BustlePersonality:
			for slider: StringName in def.slider_weights:
				w *= maxf(1.0 + def.slider_weights[slider] * ((personality as BustlePersonality).slider(slider) - 50.0) / 50.0, 0.0)
		if modifiers is BustleModifierSet:
			w = maxf((modifiers as BustleModifierSet).value(StringName("conversation.%s.weight" % def.id), w), 0.0)
		if def.recipient_value > 0.0:
			w *= maxf(1.0 + opinion_lift, 0.0)
		elif def.recipient_value < 0.0:
			w *= maxf(1.0 - opinion_lift, 0.0)
		if def.tags.has(&"curt"):
			w *= curt
		out[def.id] = w if is_finite(w) else 0.0
	return out


## The interaction [param speaker] picks for [param listener] with [param roll] (0 to 1), by
## [method weights]. Null when none has any weight.
## @experimental
func pick(speaker: StringName, listener: StringName, roll: float) -> BustleInteractionDef:
	var table := weights(speaker, listener)
	var total := 0.0
	for id: StringName in table:
		total += table[id]
	if total <= 0.0:
		return null
	var target := clampf(roll, 0.0, 1.0) * total
	var last: StringName = &""
	for id: StringName in table:
		if table[id] <= 0.0:
			continue
		last = id
		target -= table[id]
		if target < 0.0:
			return _find(id)
	return _find(last)


func _find(id: StringName) -> BustleInteractionDef:
	for def: BustleInteractionDef in interactions:
		if def != null and def.id == id and def.is_valid():
			return def
	return null


# How far below 50 the agent's mood is, 0 (50 or more, or no mood) to 1 (0).
func _low(mood: float) -> float:
	return clampf((50.0 - mood) / 50.0, 0.0, 1.0) if is_finite(mood) and mood >= 0.0 else 0.0


func _mood(id: StringName) -> float:
	var found := social._mood(id)
	return float(found.get(&"mood")) if found != null else -1.0


# 0 to 1, from the world seed and length-prefixed parts.
func _roll(parts: Array) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, social.world_seed)
	for part: Variant in parts:
		var text := str(part)
		bytes.append_array(("%d:%s|" % [text.length(), text]).to_utf8_buffer())
	var h := -3750763034362895579 # 0xcbf29ce484222325 as a signed 64-bit int
	for byte: int in bytes:
		h = (h ^ byte) * 1099511628211
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng.randf()
