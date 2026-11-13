# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRomance
extends RefCounted

## The romance module: the courtship ladder of none, courting, partner, engaged and married. Every
## status is a relationship kind written both ways through the social port ([method
## BustleSocialPort.set_kind]), so the built-in store and a bridge to a social engine both carry it.
## [br][br]
## [method update] moves a pair along the ladder from causes and state alone. Courting starts when
## both opinions and their compatibility reach the [BustleRomanceRules] lines; it becomes a
## partnership after the courting days if both opinions reach the partner line. Engaged and
## married come only from [method request] with the host's [member confirm_hook] approving. A
## courting or partnered pair breaks up when either opinion falls below its release line; an
## engaged or married pair only when the host calls [method end] (which ends any status). Both then
## get the breakup thought. After a breakup, the pair can court again only once its lower opinion
## has been below the courting release line and climbed back, so a breakup sticks until something
## changes. An agent with a partner or more never starts
## courting anyone else, and courting is one at a time. Nothing is random. With rules that aren't
## [method BustleRomanceRules.is_valid], [method update] changes nothing.
## @experimental

## A pair's status changed from [param old] to [param new] (empty: none). [param reason] is
## [code]formed[/code], [code]confirmed[/code], [code]lapsed[/code] or [code]ended[/code].
signal status_changed(a: StringName, b: StringName, old: StringName, new: StringName, reason: StringName)

const COURTING := &"courting"
const PARTNER := &"partner"
const ENGAGED := &"engaged"
const MARRIED := &"married"
## The ladder, lowest first.
const LADDER: Array[StringName] = [COURTING, PARTNER, ENGAGED, MARRIED]

## The social port the kinds go through.
var social: BustleSocialPort
## The lines.
var rules: BustleRomanceRules
## [code]func(a, b) -> float[/code], their compatibility from -1 to 1. Unset:
## [method BustleCompatibility.of] in [member world_seed].
var compatibility: Callable = Callable()
## The world seed for the default compatibility.
var world_seed: int = 0
## [code]func(a, b, status) -> bool[/code]: the host approves engaged or married. Unset: refused, so
## Bustle never gets there on its own.
var confirm_hook: Callable = Callable()

## Pair key → {a, b, status, since, armed, history: [{status, at, reason}]}. [code]armed[/code] is
## false after a breakup until the pair's lower opinion has been below the courting release line.
var _pairs: Dictionary[String, Dictionary] = {}


## Romance over [param p_social] with [param p_rules] (defaults when null) in world [param p_seed].
func _init(p_social: BustleSocialPort = null, p_rules: BustleRomanceRules = null, p_seed: int = 0) -> void:
	social = p_social if p_social != null else BustleSocialPort.new()
	rules = p_rules if p_rules != null else BustleRomanceRules.new()
	world_seed = p_seed


## The status between [param a] and [param b] (empty: none).
## @experimental
func status_of(a: StringName, b: StringName) -> StringName:
	return _pairs.get(_key(a, b), {}).get("status", &"")


## The game minute the pair took its status, or -1.
## @experimental
func since_of(a: StringName, b: StringName) -> int:
	return _pairs.get(_key(a, b), {}).get("since", -1)


## The pair's past changes, oldest first: [code]{status, at, reason}[/code].
## @experimental
func history_of(a: StringName, b: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_pairs.get(_key(a, b), {}).get("history", []))
	return out


## The one [param id] is courting, partnered, engaged or married to, at [param at_least] or above
## on the ladder, or empty.
## @experimental
func bonded_to(id: StringName, at_least: StringName = PARTNER) -> StringName:
	var floor_rank := LADDER.find(at_least)
	for key: String in _sorted_keys():
		var pair: Dictionary = _pairs[key]
		if LADDER.find(pair["status"]) >= floor_rank and (pair["a"] == id or pair["b"] == id):
			return pair["b"] if pair["a"] == id else pair["a"]
	return &""


## The pair's compatibility from -1 to 1.
## @experimental
func compatibility_of(a: StringName, b: StringName) -> float:
	if compatibility.is_valid():
		return float(compatibility.call(a, b))
	return BustleCompatibility.of(a, b, world_seed)


## Moves the pair along the ladder at game minute [param now]: a courting or partnered pair breaks
## up below its release line; else courting or partner forms when the lines are met (courting only
## for a pair that is armed: never broken up, or below the courting release line since). Engaged
## and married never lapse here. [param mood_a] and [param mood_b] (anything with
## [code]add_thought[/code]) get the breakup thought. Returns the status after.
## @experimental
func update(a: StringName, b: StringName, now: int, mood_a: Object = null, mood_b: Object = null) -> StringName:
	return _update(a, b, now, func() -> Array: return [mood_a, mood_b])


func _update(a: StringName, b: StringName, now: int, moods: Callable) -> StringName:
	if a == &"" or b == &"" or a == b or not social.supports_kinds() or not rules.is_valid():
		return status_of(a, b)
	var status := status_of(a, b)
	var low := mini(social.opinion(a, b), social.opinion(b, a))
	if status == COURTING or status == PARTNER:
		var release := rules.courting_release if status == COURTING else rules.partner_release
		if low < release:
			var pair: Array = moods.call()
			_break(a, b, now, &"lapsed", pair[0], pair[1])
			return &""
		if status == COURTING and low >= rules.partner_opinion \
				and now - since_of(a, b) >= roundi(rules.partner_days * 1440.0):
			_move(a, b, PARTNER, now, &"formed")
		return status_of(a, b)
	if status != &"":
		return status
	var record: Dictionary = _pairs.get(_key(a, b), {})
	if not bool(record.get("armed", true)):
		if low >= rules.courting_release:
			return &""
		record["armed"] = true
	if may_court(a, b) and low >= rules.courting_opinion and compatibility_of(a, b) >= rules.courting_compat:
		_move(a, b, COURTING, now, &"formed")
	return status_of(a, b)


## Every pair of [param ids], in id order (see [method update]). [param mood_of] is
## [code]func(id) -> Object[/code] for the breakup thought, or unset.
## @experimental
func update_all(ids: Array[StringName], now: int, mood_of: Callable = Callable()) -> void:
	var sorted := ids.duplicate()
	sorted.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for i: int in sorted.size():
		for j: int in range(i + 1, sorted.size()):
			var a: StringName = sorted[i]
			var b: StringName = sorted[j]
			_update(a, b, now, func() -> Array:
				if not mood_of.is_valid():
					return [null, null]
				return [mood_of.call(a), mood_of.call(b)])


## True when [param a] and [param b] may start courting: neither holds a
## [member BustleRomanceRules.blocked_kinds] kind toward the other, and neither is already courting,
## partnered, engaged or married to anyone (one courtship at a time, so a partnership never leaves
## a second courtship behind). Affairs have no path, whatever
## [member BustleRomanceRules.affairs_enabled] says.
## @experimental
func may_court(a: StringName, b: StringName) -> bool:
	for kind: StringName in rules.blocked_kinds:
		if social.kinds_between(a, b).has(String(kind)) or social.kinds_between(b, a).has(String(kind)):
			return false
	return bonded_to(a, COURTING) == &"" and bonded_to(b, COURTING) == &""


## Asks to move the pair up to [param status] ([constant ENGAGED] from partner, or
## [constant MARRIED] from engaged) at game minute [param now]. Only [member confirm_hook] can
## approve it. False (and no change) for any other step, or when the hook refuses or is unset.
## @experimental
func request(a: StringName, b: StringName, status: StringName, now: int) -> bool:
	var current := status_of(a, b)
	var steps := {ENGAGED: PARTNER, MARRIED: ENGAGED}
	if not steps.has(status) or current != steps[status] or not confirm_hook.is_valid():
		return false
	if not bool(confirm_hook.call(a, b, status)):
		return false
	_move(a, b, status, now, &"confirmed")
	return true


## Ends the pair's relationship at game minute [param now] (one of them chose to, as the host
## decides), whatever its status; this is the only way an engaged or married pair ends. Both get
## the breakup thought. The pair can't court again until its lower opinion has been below the
## courting release line. False when they have none.
## @experimental
func end(a: StringName, b: StringName, now: int, mood_a: Object = null, mood_b: Object = null) -> bool:
	if status_of(a, b) == &"":
		return false
	_break(a, b, now, &"ended", mood_a, mood_b)
	return true


## Every pair's status, since and history, as plain data, sorted. The kinds themselves are saved
## by the social port.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for key: String in _sorted_keys():
		var pair: Dictionary = _pairs[key]
		var history: Array = []
		for entry: Dictionary in pair["history"]:
			history.append({"status": String(entry["status"]), "at": entry["at"], "reason": String(entry["reason"])})
		out[key] = {"a": String(pair["a"]), "b": String(pair["b"]), "status": String(pair["status"]),
			"since": pair["since"], "armed": pair.get("armed", true), "history": history}
	return out


## Restores [method export_state], replacing every pair. False (and nothing changes) when it is
## malformed or holds a status off the ladder. A pair saved without [code]armed[/code] is armed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var restored: Dictionary[String, Dictionary] = {}
	for key: Variant in saved:
		var row: Variant = saved[key]
		if not row is Dictionary or not row.get("a") is String or not row.get("b") is String \
				or not row.get("history") is Array or not _is_int(row.get("since")) or not row.get("status") is String \
				or (row["status"] != "" and not LADDER.has(StringName(row["status"]))) \
				or not row.get("armed", true) is bool:
			return false
		var a := StringName(row["a"])
		var b := StringName(row["b"])
		if a == &"" or b == &"" or a == b or key != _key(a, b):
			return false
		var history: Array[Dictionary] = []
		for entry: Variant in row["history"]:
			if not entry is Dictionary or not entry.get("status") is String or not _is_int(entry.get("at")) \
					or not entry.get("reason") is String:
				return false
			history.append({"status": StringName(entry["status"]), "at": int(entry["at"]),
				"reason": StringName(entry["reason"])})
		restored[key] = {"a": a, "b": b, "status": StringName(row["status"]), "since": int(row["since"]),
			"armed": row.get("armed", true), "history": history}
	_pairs = restored
	return true


func _move(a: StringName, b: StringName, status: StringName, now: int, reason: StringName) -> void:
	var old := status_of(a, b)
	for kind: StringName in LADDER:
		if kind != status:
			social.clear_kind(a, b, kind)
			social.clear_kind(b, a, kind)
	if status != &"":
		social.set_kind(a, b, status)
		social.set_kind(b, a, status)
	var key := _key(a, b)
	var pair: Dictionary = _pairs.get(key, {"a": a if String(a) < String(b) else b,
		"b": b if String(a) < String(b) else a, "armed": true, "history": [] as Array[Dictionary]})
	pair["status"] = status
	pair["since"] = now
	(pair["history"] as Array).append({"status": status, "at": now, "reason": reason})
	while (pair["history"] as Array).size() > rules.history_limit:
		(pair["history"] as Array).pop_front()
	_pairs[key] = pair
	status_changed.emit(pair["a"], pair["b"], old, status, reason)


func _break(a: StringName, b: StringName, now: int, reason: StringName, mood_a: Object, mood_b: Object) -> void:
	_move(a, b, &"", now, reason)
	_pairs[_key(a, b)]["armed"] = mini(social.opinion(a, b), social.opinion(b, a)) < rules.courting_release
	for pair: Array in [[mood_a, b], [mood_b, a]]:
		var mood: Object = pair[0]
		if rules.breakup_thought != null and mood != null and mood.has_method(&"add_thought"):
			mood.call(&"add_thought", rules.breakup_thought, {"with": String(pair[1])})


func _sorted_keys() -> Array[String]:
	var out: Array[String] = []
	out.assign(_pairs.keys())
	out.sort()
	return out


static func _key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]


static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
