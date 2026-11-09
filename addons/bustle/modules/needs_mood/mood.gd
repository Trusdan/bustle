# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMood
extends RefCounted

## One agent's mood and thoughts. Mood heads for its target, which is the baseline plus every
## active thought's value (each repeat of a thought counting [member BustleThoughtDef.stack_mult]
## of the one before, times the [code]thought.tag.<tag>[/code] modifiers), clamped to the
## config's range. It moves at the config's rise or fall rate per game hour, times the agent's
## volatility, and stands still while the agent sleeps.
## [br][br]
## [method advance_to] is closed-form: it splits the time only where a thought expires, so an
## OFF_SCREEN agent's day costs one step per expiry. Every thought keeps its reason
## ([method reasons]). The dominant emotion is the emotion with the largest total of absolute
## thought values; on a tie the current one stays.
## @experimental

## How mood moves.
var config: BustleMoodConfig
## The agent's modifiers (baseline, volatility, rates, thought tags), or null for none.
var modifiers: BustleModifierSet = null
## The current mood.
var mood: float = 50.0
## The game minute this mood is at.
var now_minutes: int = 0
## The dominant emotion, or empty with no thoughts that carry one.
var emotion: StringName = &""

var _thoughts: Array[Dictionary] = []
var _next_seq: int = 0


func _init(p_config: BustleMoodConfig = null, p_modifiers: BustleModifierSet = null) -> void:
	config = p_config if p_config != null else BustleMoodConfig.new()
	modifiers = p_modifiers
	mood = baseline()


## Starts at game minute [param now] with mood at the baseline and no thoughts.
## @experimental
func start(now: int) -> void:
	now_minutes = now
	_thoughts.clear()
	mood = baseline()
	emotion = &""


## The agent's resting mood: the config's, through the [code]mood.baseline[/code] modifier, kept
## finite and inside [method mood_range]. A baseline that isn't finite counts as the middle of the
## range.
## @experimental
func baseline() -> float:
	var span := mood_range()
	var base := config.baseline if is_finite(config.baseline) else (span.x + span.y) / 2.0
	return clampf(_value(&"mood.baseline", base), span.x, span.y)


## The mood range as [code](lowest, highest)[/code]: the config's, with bounds that aren't finite
## replaced by 0 and 100 and reversed bounds swapped.
## @experimental
func mood_range() -> Vector2:
	var low := config.min_mood if is_finite(config.min_mood) else 0.0
	var high := config.max_mood if is_finite(config.max_mood) else 100.0
	return Vector2(minf(low, high), maxf(low, high))


## Adds a timed thought from [param def] now, with [param details] added to its reason. Past its
## stack limit the oldest of the same id goes. False for an invalid def or a held one (duration 0).
## @experimental
func add_thought(def: BustleThoughtDef, details: Dictionary = {}) -> bool:
	if def == null or not def.is_valid() or def.duration_hours <= 0.0 or not is_plain(details):
		return false
	var same := _of(def.id)
	while same.size() >= def.stack_limit:
		_thoughts.erase(same.pop_front())
	_append(def, now_minutes + def.duration_minutes(), details)
	return true


## Holds or drops a thought that lasts while its condition holds (duration 0). Holding one that is
## already held only updates its reason. False for an invalid def or a timed one.
## @experimental
func set_held(def: BustleThoughtDef, held: bool, details: Dictionary = {}) -> bool:
	if def == null or not def.is_valid() or def.duration_hours != 0.0 or not is_plain(details):
		return false
	var same := _of(def.id)
	if not held:
		for entry: Dictionary in same:
			_thoughts.erase(entry)
	elif same.is_empty():
		_append(def, -1, details)
	else:
		same[0]["reason"] = _reason(def, details)
	_update_emotion()
	return true


## Holds each need thought in [param defs] while its need's pressure in [param needs] is at least
## its threshold, and drops it otherwise. Its reason names the need and the pressure.
## @experimental
func sync_need_thoughts(needs: BustleNeedSet, defs: Array[BustleThoughtDef]) -> void:
	for def: BustleThoughtDef in defs:
		if def == null or def.need == &"":
			continue
		var pressure := needs.pressure(def.need)
		var held := needs.has_need(def.need) and pressure >= def.need_at_least
		set_held(def, held, {"need": def.need, "pressure": pressure})


## Drops every thought with id [param id].
## @experimental
func remove_thought(id: StringName) -> void:
	for entry: Dictionary in _of(id):
		_thoughts.erase(entry)
	_update_emotion()


## The number of active thoughts with id [param id] (all of them when empty).
## @experimental
func count(id: StringName = &"") -> int:
	return _thoughts.size() if id == &"" else _of(id).size()


## The mood target now: the baseline plus every active thought, clamped.
## @experimental
func target() -> float:
	var total := baseline()
	for entry: Dictionary in _thoughts:
		total += _effective(entry)
	var span := mood_range()
	return clampf(total if is_finite(total) else baseline(), span.x, span.y)


## Moves to game minute [param now]: thoughts that expire on the way go at their minute, and mood
## heads for the target between expiries, unless [param asleep] (then only thoughts expire).
## Earlier minutes do nothing.
## @experimental
func advance_to(now: int, asleep: bool = false) -> void:
	_expire()
	while now_minutes < now:
		var until := now
		for entry: Dictionary in _thoughts:
			var expires: int = entry["expires"]
			if expires > now_minutes and expires < until:
				until = expires
		if not asleep:
			_approach(float(until - now_minutes) / 60.0)
		now_minutes = until
		_expire()
		# At every boundary, so a tie keeps the emotion it had at that moment whatever the step size.
		_update_emotion()
	_update_emotion()


## Every active thought with its reason, strongest first:
## [code]{thought, value, emotion, reason, expires}[/code] (expires is -1 for a held thought).
## @experimental
func reasons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _thoughts:
		var def: BustleThoughtDef = entry["def"]
		out.append({"thought": def.id, "value": _effective(entry), "emotion": def.emotion,
			"reason": (entry["reason"] as Dictionary).duplicate(true), "expires": entry["expires"], "_seq": entry["seq"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(a["value"]) != absf(b["value"]):
			return absf(a["value"]) > absf(b["value"])
		if a["thought"] != b["thought"]:
			return String(a["thought"]) < String(b["thought"])
		return int(a["_seq"]) < int(b["_seq"]))
	for item: Dictionary in out:
		item.erase("_seq")
	return out


## Writes the mood into [param inputs] as [constant BustleInputs.MOOD], for the scorer's mood curves.
## @experimental
func fill_inputs(inputs: Dictionary[StringName, float]) -> void:
	inputs[BustleInputs.MOOD] = mood


## The mood as plain data: mood, minute, emotion and each thought's id, start, end and reason.
## @experimental
func export_state() -> Dictionary:
	var thoughts: Array = []
	for entry: Dictionary in _thoughts:
		thoughts.append({"id": String((entry["def"] as BustleThoughtDef).id), "started": entry["started"],
			"expires": entry["expires"], "reason": (entry["reason"] as Dictionary).duplicate(true)})
	return {"mood": mood, "now": now_minutes, "emotion": String(emotion), "thoughts": thoughts}


## Restores [method export_state], finding each thought's def by id in [param defs]. False (and
## nothing changes) when the data is malformed or impossible: a thought [param defs] doesn't have,
## a start after the save's minute, a held thought with an end, a timed one without one (or ending
## before it starts), more of one id than its stack limit (one for a held thought), or a reason
## that isn't plain data. A timed thought that had already ended by the save's minute is dropped.
## @experimental
func import_state(saved: Variant, defs: Array[BustleThoughtDef]) -> bool:
	if not saved is Dictionary:
		return false
	var data: Dictionary = saved
	var by_id: Dictionary[StringName, BustleThoughtDef] = {}
	for def: BustleThoughtDef in defs:
		if def != null and def.is_valid():
			by_id[def.id] = def
	var new_mood: Variant = data.get("mood")
	var new_now: Variant = _int(data.get("now"))
	if not (new_mood is float or new_mood is int) or not is_finite(float(new_mood)) or new_now == null \
			or not data.get("emotion") is String or not data.get("thoughts") is Array:
		return false
	var staged: Array[Dictionary] = []
	var counts: Dictionary[StringName, int] = {}
	for item: Variant in data["thoughts"]:
		if not item is Dictionary:
			return false
		var id: Variant = item.get("id")
		var started: Variant = _int(item.get("started"))
		var expires: Variant = _int(item.get("expires"))
		if not id is String or not by_id.has(StringName(id)) or started == null or expires == null \
				or not item.get("reason") is Dictionary or not is_plain(item["reason"]):
			return false
		var def := by_id[StringName(id)]
		if int(started) > int(new_now):
			return false
		if def.duration_hours == 0.0:
			if int(expires) != -1:
				return false
		elif int(expires) <= int(started):
			return false
		elif int(expires) <= int(new_now):
			continue # Ran out before the save's minute: dropped, as advance_to would have.
		counts[def.id] = counts.get(def.id, 0) + 1
		if counts[def.id] > (1 if def.duration_hours == 0.0 else def.stack_limit):
			return false
		staged.append({"def": def, "started": started, "expires": expires,
			"reason": (item["reason"] as Dictionary).duplicate(true), "seq": staged.size()})
	_thoughts = staged
	_next_seq = staged.size()
	mood = clampf(float(new_mood), mood_range().x, mood_range().y)
	now_minutes = new_now
	emotion = StringName(data["emotion"])
	_update_emotion()
	return true


func _append(def: BustleThoughtDef, expires: int, details: Dictionary) -> void:
	_thoughts.append({"def": def, "started": now_minutes, "expires": expires,
		"reason": _reason(def, details), "seq": _next_seq})
	_next_seq += 1
	_update_emotion()


func _reason(def: BustleThoughtDef, details: Dictionary) -> Dictionary:
	var out := details.duplicate(true)
	out["kind"] = String(def.reason_kind) # plain data, so it saves and compares the same after JSON
	return out


func _of(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _thoughts:
		if (entry["def"] as BustleThoughtDef).id == id:
			out.append(entry)
	return out


# A thought's value: its own, times its stack factor among the same id (oldest first), times the
# thought.tag.<tag> modifiers.
func _effective(entry: Dictionary) -> float:
	var def: BustleThoughtDef = entry["def"]
	var rank := 0
	for other: Dictionary in _of(def.id):
		if int(other["seq"]) < int(entry["seq"]):
			rank += 1
	var value := def.value * pow(def.stack_mult, rank)
	var tags := def.tags.duplicate()
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for tag: StringName in tags:
		value *= _value(StringName("thought.tag.%s" % tag), 1.0)
	return value if is_finite(value) else 0.0


func _approach(hours: float) -> void:
	var goal := target()
	var volatility := maxf(_value(&"mood.volatility", _rate(config.volatility)), 0.0)
	var rate := _rate(config.rise_per_hour) * _value(&"mood.rise.mult", 1.0) if goal > mood \
			else _rate(config.fall_per_hour) * _value(&"mood.fall.mult", 1.0)
	var step := maxf(rate * volatility * hours, 0.0)
	var span := mood_range()
	if is_finite(step):
		mood = clampf(move_toward(mood, goal, step), span.x, span.y)


func _expire() -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _thoughts:
		var expires: int = entry["expires"]
		if expires < 0 or expires > now_minutes:
			kept.append(entry)
	_thoughts = kept


func _update_emotion() -> void:
	var totals: Dictionary[StringName, float] = {}
	for entry: Dictionary in _thoughts:
		var def: BustleThoughtDef = entry["def"]
		if def.emotion != &"":
			totals[def.emotion] = totals.get(def.emotion, 0.0) + absf(_effective(entry))
	var best := -1.0
	for value: float in totals.values():
		best = maxf(best, value)
	if totals.is_empty() or best <= 0.0:
		emotion = &""
		return
	var tied: Array[StringName] = []
	for key: StringName in totals:
		if totals[key] >= best - 1e-9:
			tied.append(key)
	if tied.has(emotion):
		return
	tied.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	emotion = tied[0]


func _value(key: StringName, base: float) -> float:
	var out := modifiers.value(key, base) if modifiers != null else base
	return out if is_finite(out) else base


static func _rate(value: float) -> float:
	return maxf(value, 0.0) if is_finite(value) else 0.0


## True when [param value] is plain data that saves as JSON: null, a bool, an int, a finite float,
## a string, or arrays and string-keyed dictionaries of those.
## @experimental
static func is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not is_plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not (key is String or key is StringName) or not is_plain(value[key]):
					return false
			return true
	return false


static func _int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return null
