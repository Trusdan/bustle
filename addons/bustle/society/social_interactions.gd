# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSocialInteractions
extends RefCounted

## Greetings and interactions between agents, on a [BustleSocialStore]. Every interaction goes
## through one pure function, [method outcome], which gives the same answer for the same pair,
## minute, interaction, compatibility and moods; [method interact] then records it: a deed (the
## verb is the interaction's id) and, together with it, opinion entries whose reason names that
## deed, plus any thoughts. A greeting is an interaction with cooldowns: one per pair (either way
## round) and one per initiator, so agents don't greet the same person over and over, or everyone
## at once.
## @experimental

## The store everything is recorded in.
var store: BustleSocialStore
## The world seed, for compatibility and the outcome's randomness.
var world_seed: int = 0
## The interaction a greeting is.
var greeting: BustleInteractionDef
## Game minutes before the same two agents greet again.
var pair_cooldown_minutes: int = 120
## Game minutes before an agent greets anyone again.
var agent_cooldown_minutes: int = 10
## (id) → that agent's mood (anything with a [code]mood[/code] number and [code]add_thought[/code]),
## or null. Empty: nobody has a mood.
var mood_of: Callable = Callable()

var _pair_ready: Dictionary[String, int] = {}
var _agent_ready: Dictionary[StringName, int] = {}


func _init(p_store: BustleSocialStore = null, p_world_seed: int = 0) -> void:
	store = p_store if p_store != null else BustleSocialStore.new()
	world_seed = p_world_seed


## The result of [param initiator] doing [param def] to [param recipient] at minute [param now],
## without recording anything: [code]{interaction, initiator, recipient, to_recipient,
## to_initiator}[/code]. [param to_recipient] is how much the recipient's opinion of the initiator
## moves, [param to_initiator] the other way. Moods are 0 to 100, or negative for none. The same
## inputs always give the same result.
## @experimental
static func outcome(def: BustleInteractionDef, initiator: StringName, recipient: StringName, now: int,
		world_seed: int, compatibility: float, initiator_mood: float = -1.0, recipient_mood: float = -1.0) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, world_seed)
	bytes.append_array(("%s|%s|%s|%d" % [initiator, recipient, def.id, now]).to_utf8_buffer())
	var h := -3750763034362895579 # 0xcbf29ce484222325 as a signed 64-bit int
	for byte: int in bytes:
		h = (h ^ byte) * 1099511628211
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var compat := clampf(compatibility, -1.0, 1.0) if is_finite(compatibility) else 0.0
	var bend := maxf(1.0 + compat * def.compatibility_scale, 0.0)
	var to_recipient := _with_mood(def.recipient_value + rng.randf_range(-1.0, 1.0) * def.spread, recipient_mood, def.mood_scale) * bend
	var to_initiator := _with_mood(def.initiator_value + rng.randf_range(-1.0, 1.0) * def.spread, initiator_mood, def.mood_scale) * bend
	return {"interaction": def.id, "initiator": initiator, "recipient": recipient,
		"to_recipient": to_recipient, "to_initiator": to_initiator}


## [param initiator] does [param def] to [param recipient] at minute [param now] at
## [param place], seen by [param witnesses]: works out the [method outcome], records the deed and
## the opinion entries that name it, and gives each side its thought. Returns the outcome with
## [code]ok[/code] and the [code]deed[/code] key, or [code]{ok: false, reason}[/code].
## @experimental
func interact(def: BustleInteractionDef, initiator: StringName, recipient: StringName, now: int,
		place: StringName = &"", witnesses: Array[Dictionary] = []) -> Dictionary:
	if def == null or not def.is_valid():
		return {"ok": false, "reason": &"invalid"}
	if initiator == &"" or recipient == &"" or initiator == recipient:
		return {"ok": false, "reason": &"no_pair"}
	store.set_time(now)
	var a_mood := _mood(initiator)
	var b_mood := _mood(recipient)
	var result := outcome(def, initiator, recipient, now, world_seed,
		BustleCompatibility.of(initiator, recipient, world_seed),
		float(a_mood.get(&"mood")) if a_mood != null else -1.0, float(b_mood.get(&"mood")) if b_mood != null else -1.0)
	var key := store.record_deed(initiator, def.id, recipient, place, witnesses)
	if result["to_recipient"] != 0.0:
		store.add_opinion(recipient, initiator, result["to_recipient"],
			{"deed": String(key), "interaction": String(def.id), "by": String(initiator)}, def.days)
	if result["to_initiator"] != 0.0:
		store.add_opinion(initiator, recipient, result["to_initiator"],
			{"deed": String(key), "interaction": String(def.id), "with": String(recipient)}, def.days)
	if b_mood != null and def.recipient_thought != null:
		b_mood.call(&"add_thought", def.recipient_thought, {"deed": String(key), "by": String(initiator)})
	if a_mood != null and def.initiator_thought != null:
		a_mood.call(&"add_thought", def.initiator_thought, {"deed": String(key), "with": String(recipient)})
	result["ok"] = true
	result["deed"] = key
	return result


## True when [param initiator] may greet [param recipient] at minute [param now].
## @experimental
func can_greet(initiator: StringName, recipient: StringName, now: int) -> bool:
	return _pair_ready.get(_pair(initiator, recipient), -1) <= now and _agent_ready.get(initiator, -1) <= now


## [param initiator] greets [param recipient] (see [member greeting]), unless a cooldown is
## running ([code]{ok: false, reason: cooling_down}[/code]). Starts both cooldowns.
## @experimental
func greet(initiator: StringName, recipient: StringName, now: int, place: StringName = &"",
		witnesses: Array[Dictionary] = []) -> Dictionary:
	if not can_greet(initiator, recipient, now):
		return {"ok": false, "reason": &"cooling_down"}
	var result := interact(greeting, initiator, recipient, now, place, witnesses)
	if result.get("ok", false):
		_pair_ready[_pair(initiator, recipient)] = now + maxi(pair_cooldown_minutes, 0)
		_agent_ready[initiator] = now + maxi(agent_cooldown_minutes, 0)
	return result


## The greeting cooldowns as plain data.
## @experimental
func export_state() -> Dictionary:
	var pairs := {}
	for key: String in _pair_ready:
		pairs[key] = _pair_ready[key]
	var agents := {}
	for id: StringName in _agent_ready:
		agents[String(id)] = _agent_ready[id]
	return {"pairs": pairs, "agents": agents}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("pairs") is Dictionary or not saved.get("agents") is Dictionary:
		return false
	var pairs: Dictionary[String, int] = {}
	var agents: Dictionary[StringName, int] = {}
	for key: Variant in saved["pairs"]:
		var until: Variant = BustleSocialStore._int(saved["pairs"][key])
		if not key is String or until == null:
			return false
		pairs[key] = until
	for key: Variant in saved["agents"]:
		var until: Variant = BustleSocialStore._int(saved["agents"][key])
		if not key is String or until == null:
			return false
		agents[StringName(key)] = until
	_pair_ready = pairs
	_agent_ready = agents
	return true


func _mood(id: StringName) -> Object:
	if not mood_of.is_valid():
		return null
	var found: Variant = mood_of.call(id)
	return found if found is Object and found.has_method(&"add_thought") else null


static func _with_mood(value: float, mood: float, scale: float) -> float:
	if not is_finite(mood) or mood < 0.0:
		return value
	var lift := scale * (clampf(mood, 0.0, 100.0) - 50.0) / 50.0
	return value * maxf(1.0 + lift, 0.0) if value > 0.0 else value * maxf(1.0 - lift, 0.0)


static func _pair(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]
