# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRoomThoughts
extends RefCounted

## The environment module: thoughts from the room an agent is in. The host computes rooms and their
## scores and reports them through the environment port ([BustleEnvironmentPort]); this module
## turns them into held thoughts with [BustleRoomThought] rules.
## [br][br]
## [method sync] holds, for each score of the agent's room, the most extreme high rule it meets
## (the highest [member BustleRoomThought.at_least]) and the most extreme low rule (the lowest
## [member BustleRoomThought.at_most]), so a better score gives a better thought. Every other rule
## thought is dropped, so leaving the room, or its scores changing, clears or swaps them. A score
## the room doesn't have is unset and meets no rule. Thoughts go through the mood's
## [code]set_held[/code], so one of each is held at most. Nothing is random.
## [br][br]
## With no environment port, the default one (no rooms) or no mood, there are no environment
## thoughts and nothing errors.
## @experimental

## [param id] moved from [param old_room] to [param new_room] (empty: no room) as of the last sync.
signal room_changed(id: StringName, old_room: StringName, new_room: StringName)

## The ports it reads: [code]environment[/code]. Null (or a null port): no rooms.
var ports: BustlePorts

var _rules: Array[BustleRoomThought] = []
## Agent id → {room, thoughts (the thought ids chosen at the last sync)}.
var _state: Dictionary[StringName, Dictionary] = {}


## Starts with [param rules] (invalid ones are skipped with a warning), reading rooms from
## [param p_ports].
func _init(rules: Array[BustleRoomThought] = [], p_ports: BustlePorts = null) -> void:
	ports = p_ports
	for rule: BustleRoomThought in rules:
		if not add_rule(rule):
			push_warning("BustleRoomThoughts: skipped a room thought rule")


## Adds [param rule]. False (and no change) when it's null or invalid.
## @experimental
func add_rule(rule: BustleRoomThought) -> bool:
	if rule == null or not rule.is_valid():
		return false
	_rules.append(rule)
	return true


## The room [param id] is in, from the environment port; empty with none.
## @experimental
func room_of(id: StringName) -> StringName:
	var environment: BustleEnvironmentPort = ports.environment if ports != null else null
	return environment.room_of(id) if environment != null else &""


## The rules [param room] meets now: per score, the most extreme high rule and the most extreme
## low rule it meets, in [constant BustleEnvironmentPort.SCORES] order. Ties go to the rule added
## first. Empty for no room.
## @experimental
func chosen(room: StringName) -> Array[BustleRoomThought]:
	var out: Array[BustleRoomThought] = []
	var environment: BustleEnvironmentPort = ports.environment if ports != null else null
	if room == &"" or environment == null:
		return out
	var values := environment.scores(room)
	for score: StringName in BustleEnvironmentPort.SCORES:
		var value: float = values.get(score, NAN)
		var high: BustleRoomThought = null
		var low: BustleRoomThought = null
		for rule: BustleRoomThought in _rules:
			if rule.score != score or not rule.matches(value):
				continue
			if rule.is_high() and (high == null or rule.at_least > high.at_least):
				high = rule
			elif not rule.is_high() and (low == null or rule.at_most < low.at_most):
				low = rule
		for rule: BustleRoomThought in [high, low]:
			if rule != null:
				out.append(rule)
	return out


## Brings [param id]'s environment thoughts in line with its room now. On [param mood] (anything
## with [code]set_held(def, held, details)[/code], such as a [code]BustleMood[/code]) it drops every
## rule thought not chosen, then holds the chosen ones with [code]room[/code], [code]score[/code]
## and [code]value[/code] in their reason. Returns the chosen thought ids, sorted.
## @experimental
func sync(id: StringName, mood: Object = null) -> Array[StringName]:
	var room := room_of(id)
	var rules := chosen(room)
	var keep: Array[Resource] = []
	for rule: BustleRoomThought in rules:
		keep.append(rule.thought)
	if mood != null and mood.has_method(&"set_held"):
		var dropped: Array[Resource] = []
		for rule: BustleRoomThought in _rules:
			if not keep.has(rule.thought) and not dropped.has(rule.thought):
				mood.call(&"set_held", rule.thought, false, {})
				dropped.append(rule.thought)
		var values := ports.environment.scores(room) if rules.size() > 0 else ({} as Dictionary[StringName, float])
		for rule: BustleRoomThought in rules:
			mood.call(&"set_held", rule.thought, true,
					{"room": String(room), "score": String(rule.score), "value": values[rule.score]})
	var ids: Array[StringName] = []
	for def: Resource in keep:
		if not ids.has(def.get(&"id")):
			ids.append(def.get(&"id"))
	ids = _sorted(ids)
	var old: StringName = _state.get(id, {}).get("room", &"")
	if room == &"" and ids.is_empty():
		_state.erase(id)
	else:
		_state[id] = {"room": room, "thoughts": ids}
	if old != room:
		room_changed.emit(id, old, room)
	return ids


## The thought ids chosen for [param id] at its last sync, sorted.
## @experimental
func thoughts_of(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_state.get(id, {}).get("thoughts", []))
	return out


## Drops [param id]'s environment thoughts from [param mood] and forgets it (for an agent that
## leaves the society).
## @experimental
func forget(id: StringName, mood: Object = null) -> void:
	if mood != null and mood.has_method(&"set_held"):
		for rule: BustleRoomThought in _rules:
			mood.call(&"set_held", rule.thought, false, {})
	_state.erase(id)


## What each agent was last synced to, as plain data: [code]{agent: {room, thoughts}}[/code],
## sorted. The thoughts themselves are saved with the mood.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in _sorted(_state.keys()):
		var names: Array = []
		for thought: StringName in _state[id]["thoughts"]:
			names.append(String(thought))
		out[String(id)] = {"room": String(_state[id]["room"]), "thoughts": names}
	return out


## Restores [method export_state], replacing what's kept. False (and nothing changes) for malformed
## data or a thought id no rule has. The next [method sync] brings the mood in line; holding a
## thought that is already held adds no second one.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var known: Array[StringName] = []
	for rule: BustleRoomThought in _rules:
		known.append(rule.thought.get(&"id"))
	var restored: Dictionary[StringName, Dictionary] = {}
	for id: Variant in saved:
		var row: Variant = saved[id]
		if not id is String or String(id).is_empty() or not row is Dictionary or not row.get("room") is String \
				or not row.get("thoughts") is Array:
			return false
		var ids: Array[StringName] = []
		for thought: Variant in row["thoughts"]:
			if not thought is String or not known.has(StringName(thought)) or ids.has(StringName(thought)):
				return false
			ids.append(StringName(thought))
		restored[StringName(id)] = {"room": StringName(row["room"]), "thoughts": _sorted(ids)}
	_state = restored
	return true


static func _sorted(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ids)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
