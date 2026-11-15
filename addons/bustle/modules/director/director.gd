# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDirector
extends RefCounted

## The storyteller: it paces host-authored events ([BustleEventDef]) by the story's tension and
## fires the one the story needs most. Nothing is random: there is no seed and no deck, and the
## same events, inputs, locks and clock give the same timeline.
## [br][br]
## Each [method update], an event is eligible when its preconditions hold on the host's inputs, its
## cooldown has passed, it isn't lock-sensitive while a quest lock is held, and the director port
## ([method BustleDirectorPort.allows]) agrees. Of those, the pick is the best by, in turn:
## [br]- pacing ([method need]): events that move tension the way the story needs come first, those
## that leave it alone next, and those that push the wrong way last, so they still fire when nothing
## else can;
## [br]- score ([method BustleEventDef.score]), highest first;
## [br]- id.
## [br]At most one event fires per update, and none within [member BustleDirectorRules.beat_gap_minutes]
## of the last. Firing emits [signal event_fired], then [member effects] applies what the event
## declares (thoughts, orders, spawn requests). Population and wealth reach it as host inputs
## ([method hooks]); Bustle keeps no economy.
## [br][br]
## With no events, nothing fires, and the director port is left as it is.

## The story needs nothing in particular.
const NEED_NONE := 0
## The story needs tension raised.
const NEED_RAISE := 1
## The story needs relief.
const NEED_RELIEVE := -1
## The saved-state layout version.
const STATE_VERSION := 1
## The population hook: the input a host fills with a head count, for preconditions, scores and
## tension to read ([method hooks]).
const INPUT_POPULATION := &"fact.population"
## The wealth hook: the input a host fills with a wealth figure. Bustle has no economy: it only reads
## the number.
const INPUT_WEALTH := &"fact.wealth"

## [param id] fired at game minute [param now].
signal event_fired(id: StringName, now: int)

## The pacing rules. Invalid rules ([method BustleDirectorRules.validate]) fire nothing.
var rules: BustleDirectorRules
## The ports it reads: [code]director[/code], the host's veto. Null: every event is allowed.
var ports: BustlePorts
## Applies each fired event's effects, after [signal event_fired]. Null: no effects are applied.
var effects: BustleDirectorEffects = null

var _defs: Array[BustleEventDef] = []
# Event id → the game minute it last fired.
var _last: Dictionary[StringName, int] = {}
# Recently fired events, oldest first: [id, minute], within the rules' memory.
var _history: Array[Array] = []


## Starts with [param p_rules] (the defaults when null), reading the veto from [param p_ports].
func _init(p_rules: BustleDirectorRules = null, p_ports: BustlePorts = null) -> void:
	rules = p_rules if p_rules != null else BustleDirectorRules.new()
	ports = p_ports


## Adds [param def]. False, changing nothing, when it is null, invalid, or its id is taken.
func add_event(def: BustleEventDef) -> bool:
	if def == null or def.validate() != "" or find(def.id) != null:
		return false
	_defs.append(def)
	return true


## The event with [param id], or null.
func find(id: StringName) -> BustleEventDef:
	for def: BustleEventDef in _defs:
		if def.id == id:
			return def
	return null


## The story's tension at [param now] on [param inputs], 0 to 1: the weighted inputs plus each
## remembered event's tension, fading over the memory.
func tension(now: int, inputs: Dictionary) -> float:
	if rules.validate() != "":
		return 0.0
	var out := 0.0
	for key: StringName in rules.tension_inputs:
		var value := float(inputs.get(key, 0.0))
		if is_finite(value):
			out += rules.tension_inputs[key] * value
	for entry: Array in _history:
		var def := find(entry[0])
		var age := now - int(entry[1])
		if def != null and age >= 0 and age < rules.memory_minutes:
			out += def.tension * (1.0 - float(age) / rules.memory_minutes)
	return clampf(out, 0.0, 1.0)


## What the story needs at [param now]: [constant NEED_RELIEVE] at or above the high line,
## [constant NEED_RAISE] at or below the low line, otherwise [constant NEED_NONE].
func need(now: int, inputs: Dictionary) -> int:
	var value := tension(now, inputs)
	if value >= rules.high:
		return NEED_RELIEVE
	if value <= rules.low:
		return NEED_RAISE
	return NEED_NONE


## The eligible events at [param now], best first (see the class description). Empty within the
## beat gap, before the last fired event, or with invalid rules.
func eligible(now: int, inputs: Dictionary, locked: bool) -> Array[BustleEventDef]:
	var out: Array[BustleEventDef] = []
	if rules.validate() != "":
		return out
	if not _history.is_empty():
		var last_beat := int(_history[-1][1])
		if now < last_beat or now - last_beat < rules.beat_gap_minutes:
			return out
	for def: BustleEventDef in _defs:
		if def.lock_sensitive and locked:
			continue
		if _last.has(def.id) and now - _last[def.id] < def.cooldown_minutes:
			continue
		if not def.preconditions_hold(inputs):
			continue
		if ports != null and ports.director != null and not ports.director.allows(def.event_kind()):
			continue
		out.append(def)
	var wanted := need(now, inputs)
	var rank := func(def: BustleEventDef) -> int:
		if wanted == NEED_NONE or def.tension == 0.0:
			return 1
		return 0 if signf(def.tension) == float(wanted) else 2
	out.sort_custom(func(a: BustleEventDef, b: BustleEventDef) -> bool:
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		var sa := a.score(inputs)
		var sb := b.score(inputs)
		if sa != sb:
			return sa > sb
		return String(a.id) < String(b.id))
	return out


## Fires the best eligible event at [param now] on the host's [param inputs], with the quest lock
## [param locked], and emits [signal event_fired]. Returns its id, or empty when none fires.
func update(now: int, inputs: Dictionary = {}, locked: bool = false) -> StringName:
	var candidates := eligible(now, inputs, locked)
	if candidates.is_empty():
		return &""
	var id := candidates[0].id
	_last[id] = now
	_history.append([id, now])
	while not _history.is_empty() and now - int(_history[0][1]) >= rules.memory_minutes:
		_history.pop_front()
	event_fired.emit(id, now)
	if effects != null:
		effects.apply(candidates[0], now)
	return id


## [param inputs] with the population and wealth hooks set: [param population] as
## [constant INPUT_POPULATION] and [param wealth] as [constant INPUT_WEALTH]. A copy; the host's
## dictionary is left alone.
static func hooks(population: int, wealth: float, inputs: Dictionary = {}) -> Dictionary:
	var out := inputs.duplicate()
	out[INPUT_POPULATION] = float(population)
	out[INPUT_WEALTH] = wealth
	return out


## The game minute [param id] last fired, or -1.
func last_fired(id: StringName) -> int:
	return _last.get(id, -1)


## Cooldowns and recent history as plain data. Tension comes from these and the inputs, so it
## comes back with them.
func export_state() -> Dictionary:
	var last := {}
	var ids: Array = _last.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		last[String(id)] = _last[id]
	var history: Array = []
	for entry: Array in _history:
		history.append([String(entry[0]), entry[1]])
	return {"version": STATE_VERSION, "last": last, "history": history}


static func _save_format() -> Dictionary:
	return {"key": "version", "current": STATE_VERSION, "steps": {}}


## Restores [method export_state]. Minutes may be whole floats, as in a save read back from JSON.
## False, changing nothing, for another version, a malformed entry, a minute that isn't whole, an
## event id the director doesn't have, or history out of order.
func import_state(saved: Dictionary) -> bool:
	if not BustleSaveFormat._read(&"BustleDirector", saved, _save_format())["ok"]:
		return false
	if int(saved.get("version", -1)) != STATE_VERSION or not saved.get("last") is Dictionary \
			or not saved.get("history") is Array:
		return false
	var last: Dictionary[StringName, int] = {}
	for key: Variant in saved["last"]:
		var minute: Variant = saved["last"][key]
		if find(StringName(str(key))) == null or not _whole(minute):
			return false
		last[StringName(str(key))] = int(minute)
	var history: Array[Array] = []
	for entry: Variant in saved["history"]:
		if not entry is Array or entry.size() != 2 or find(StringName(str(entry[0]))) == null or not _whole(entry[1]) \
				or (not history.is_empty() and int(entry[1]) < int(history[-1][1])):
			return false
		history.append([StringName(str(entry[0])), int(entry[1])])
	_last = last
	_history = history
	return true


# A whole number of minutes: an int, or a whole float (as a save read back from JSON has).
static func _whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
