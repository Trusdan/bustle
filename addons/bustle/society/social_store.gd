# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSocialStore
extends BustleSocialPort

## The built-in social store: a [BustleSocialPort] that keeps opinions with reasons and
## relationship kinds, for hosts without a social engine of their own. Deeds work as in the port's
## default.
## [br][br]
## [b]Opinions[/b] are one-way: how [code]a[/code] regards [code]b[/code], from 0 to 100, is
## [constant BustleSocialPort.NEUTRAL_OPINION] plus every live opinion entry, clamped. Each entry
## has a value, a reason (plain data; a [code]deed[/code] key when a deed caused it) and lasts a
## number of game days. The store's clock is [method set_time]; entries end at their minute.
## [br][br]
## [b]Kinds[/b] are one-way too ([code]a[/code] counts [code]b[/code] a friend). Kinds a host sets
## ([method set_kind]) stay until it clears them. Kinds the [member rules] form from repeated deeds
## come and go with opinion ([signal kind_changed]); the rules never touch a host's kinds.
## @experimental

## [param a]'s kind [param kind] towards [param b] formed ([param formed] true) or lapsed.
signal kind_changed(a: StringName, b: StringName, kind: StringName, formed: bool)

## When repeated deeds form friends and rivals.
var rules := BustleRelationshipRules.new()
## The store's game minute.
var now_minutes: int = 0

# "a>b" → Array of {value, reason, at, until, seq}.
var _entries: Dictionary[String, Array] = {}
# "a>b" → kinds a host set / kinds the rules formed.
var _host_kinds: Dictionary[String, PackedStringArray] = {}
var _rule_kinds: Dictionary[String, PackedStringArray] = {}
var _next_seq: int = 0


## Moves the store's clock to [param now] (earlier minutes are ignored): ended entries go, and
## every pair's rule kinds are checked again.
## @experimental
func set_time(now: int) -> void:
	if now <= now_minutes:
		return
	now_minutes = now
	var keys: Array[String] = _entries.keys()
	keys.sort()
	for key: String in keys:
		_expire(key)
		var pair := key.split(">")
		update_kinds(StringName(pair[0]), StringName(pair[1]))


## Adds an opinion entry: [param a]'s view of [param b] moves by [param value] for
## [param days] game days from the store's current minute, for [param reason] (plain data; put the
## deed key under [code]deed[/code] when a deed caused it). Then checks the rule kinds. False for
## an empty or identical pair, a value or duration that isn't finite, or a non-positive duration.
## @experimental
func add_opinion(a: StringName, b: StringName, value: float, reason: Dictionary, days: float) -> bool:
	if a == &"" or b == &"" or a == b or not is_finite(value) or not is_finite(days) or days <= 0.0 \
			or days > 1.0e6 or not _is_plain(reason):
		return false
	var key := _key(a, b)
	if not _entries.has(key):
		_entries[key] = []
	_entries[key].append({"value": value, "reason": reason.duplicate(true), "at": now_minutes,
		"until": now_minutes + maxi(roundi(days * 1440.0), 1), "seq": _next_seq})
	_next_seq += 1
	update_kinds(a, b)
	return true


## How [param a] regards [param b], from 0 to 100.
## @experimental
func opinion(a: StringName, b: StringName) -> int:
	return roundi(opinion_value(a, b))


## [method opinion] without rounding.
## @experimental
func opinion_value(a: StringName, b: StringName) -> float:
	var key := _key(a, b)
	_expire(key)
	var total := float(NEUTRAL_OPINION)
	for entry: Dictionary in _entries.get(key, []):
		total += float(entry["value"])
	return clampf(total, 0.0, 100.0)


## Up to [param count] live entries behind [param a]'s opinion of [param b], strongest first:
## [code]{value, reason, at, until}[/code].
## @experimental
func reasons(a: StringName, b: StringName, count: int = 3) -> Array[Dictionary]:
	var key := _key(a, b)
	_expire(key)
	var live: Array = _entries.get(key, []).duplicate()
	live.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if absf(x["value"]) != absf(y["value"]):
			return absf(x["value"]) > absf(y["value"])
		return int(x["seq"]) < int(y["seq"]))
	var out: Array[Dictionary] = []
	for entry: Dictionary in live.slice(0, maxi(count, 0)):
		out.append({"value": entry["value"], "reason": (entry["reason"] as Dictionary).duplicate(true),
			"at": entry["at"], "until": entry["until"]})
	return out


## The kinds [param a] has towards [param b], the host's and the rules' together, sorted.
## @experimental
func kinds_between(a: StringName, b: StringName) -> PackedStringArray:
	var key := _key(a, b)
	var out := PackedStringArray(_host_kinds.get(key, PackedStringArray()))
	for kind: String in _rule_kinds.get(key, PackedStringArray()):
		if not out.has(kind):
			out.append(kind)
	out.sort()
	return out


## Gives [param a] the kind [param kind] towards [param b], kept until [method clear_kind].
## @experimental
func set_kind(a: StringName, b: StringName, kind: StringName) -> void:
	if a == &"" or b == &"" or a == b or kind == &"":
		return
	var key := _key(a, b)
	var kinds: PackedStringArray = _host_kinds.get(key, PackedStringArray())
	if not kinds.has(String(kind)):
		kinds.append(String(kind))
		_host_kinds[key] = kinds


## Takes the host's kind [param kind] away from [param a] towards [param b]. Kinds the rules formed
## are left to the rules.
## @experimental
func clear_kind(a: StringName, b: StringName, kind: StringName) -> void:
	var key := _key(a, b)
	if _host_kinds.has(key):
		var kinds: PackedStringArray = _host_kinds[key]
		var at := kinds.find(String(kind))
		if at >= 0:
			kinds.remove_at(at)
		if kinds.is_empty():
			_host_kinds.erase(key)
		else:
			_host_kinds[key] = kinds


## Applies the [member rules] to [param a]'s view of [param b]: forms a friend or rival kind when
## the opinion and deeds call for it, and lets it lapse past its release level.
## @experimental
func update_kinds(a: StringName, b: StringName) -> void:
	var key := _key(a, b)
	var value := opinion_value(a, b)
	var window := now_minutes - roundi(maxf(rules.window_days, 0.0) * 1440.0)
	var good := 0
	var bad := 0
	for entry: Dictionary in _entries.get(key, []):
		if (entry["reason"] as Dictionary).has("deed") and int(entry["at"]) >= window:
			if float(entry["value"]) > 0.0:
				good += 1
			elif float(entry["value"]) < 0.0:
				bad += 1
	_rule(a, b, rules.friend_kind, value >= rules.friend_at and good >= rules.min_deeds, value < rules.friend_release)
	_rule(a, b, rules.rival_kind, value <= rules.rival_at and bad >= rules.min_deeds, value > rules.rival_release)


## Opinions, kinds and deeds as plain data.
## @experimental
func export_state() -> Dictionary:
	var entries := {}
	var keys: Array[String] = _entries.keys()
	keys.sort()
	for key: String in keys:
		var list: Array = []
		for entry: Dictionary in _entries[key]:
			list.append({"value": entry["value"], "reason": (entry["reason"] as Dictionary).duplicate(true),
				"at": entry["at"], "until": entry["until"]})
		if not list.is_empty():
			entries[key] = list
	var deeds := {}
	for deed_key: StringName in _deeds:
		var deed: Dictionary = _deeds[deed_key]
		var knowers: Array = []
		for id: StringName in (deed["knowers"] as Dictionary):
			knowers.append(String(id))
		knowers.sort()
		var first: Array = []
		for id: StringName in deed["first_hand"]:
			first.append(String(id))
		first.sort()
		deeds[String(deed_key)] = {"actor": String(deed["actor"]), "verb": String(deed["verb"]),
			"target": String(deed["target"]), "place": String(deed["place"]), "first_hand": first, "knowers": knowers}
	return {"now": now_minutes, "entries": entries, "host_kinds": _kinds_data(_host_kinds),
		"rule_kinds": _kinds_data(_rule_kinds), "deeds": deeds, "next_deed": _next_deed}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var data: Dictionary = saved
	var now: Variant = _int(data.get("now"))
	var next_deed: Variant = _int(data.get("next_deed"))
	if now == null or next_deed == null or not data.get("entries") is Dictionary or not data.get("deeds") is Dictionary:
		return false
	var entries: Dictionary[String, Array] = {}
	var seq := 0
	for key: Variant in data["entries"]:
		if not key is String or (key as String).split(">").size() != 2 or not data["entries"][key] is Array:
			return false
		var list: Array = []
		for item: Variant in data["entries"][key]:
			if not item is Dictionary:
				return false
			var value: Variant = item.get("value")
			var at: Variant = _int(item.get("at"))
			var until: Variant = _int(item.get("until"))
			if not (value is float or value is int) or not is_finite(float(value)) or at == null or until == null \
					or int(until) <= int(at) or not item.get("reason") is Dictionary or not _is_plain(item["reason"]):
				return false
			list.append({"value": float(value), "reason": (item["reason"] as Dictionary).duplicate(true), "at": at, "until": until, "seq": seq})
			seq += 1
		entries[key] = list
	var host := _kinds_from(data.get("host_kinds"))
	var formed := _kinds_from(data.get("rule_kinds"))
	if host == null or formed == null:
		return false
	var deeds := {}
	for deed_key: Variant in data["deeds"]:
		var deed: Variant = data["deeds"][deed_key]
		if not deed_key is String or not deed is Dictionary:
			return false
		for field: String in ["actor", "verb", "target", "place"]:
			if not deed.get(field) is String:
				return false
		if not deed.get("first_hand") is Array or not deed.get("knowers") is Array:
			return false
		var knowers := {}
		for id: Variant in deed["knowers"]:
			if not id is String:
				return false
			knowers[StringName(id)] = true
		var first: Array = []
		for id: Variant in deed["first_hand"]:
			if not id is String:
				return false
			first.append(StringName(id))
		deeds[StringName(deed_key)] = {"actor": StringName(deed["actor"]), "verb": StringName(deed["verb"]),
			"target": StringName(deed["target"]), "place": StringName(deed["place"]), "first_hand": first, "knowers": knowers}
	now_minutes = now
	_entries = entries
	_next_seq = seq
	_host_kinds = host
	_rule_kinds = formed
	_deeds = deeds
	_next_deed = next_deed
	return true


func _rule(a: StringName, b: StringName, kind: StringName, form: bool, release: bool) -> void:
	if kind == &"":
		return
	var key := _key(a, b)
	var kinds: PackedStringArray = _rule_kinds.get(key, PackedStringArray())
	var has := kinds.has(String(kind))
	if form and not has:
		kinds.append(String(kind))
		_rule_kinds[key] = kinds
		kind_changed.emit(a, b, kind, true)
	elif has and release:
		kinds.remove_at(kinds.find(String(kind)))
		if kinds.is_empty():
			_rule_kinds.erase(key)
		else:
			_rule_kinds[key] = kinds
		kind_changed.emit(a, b, kind, false)


func _expire(key: String) -> void:
	if not _entries.has(key):
		return
	var kept: Array = []
	for entry: Dictionary in _entries[key]:
		if int(entry["until"]) > now_minutes:
			kept.append(entry)
	if kept.is_empty():
		_entries.erase(key)
	else:
		_entries[key] = kept


static func _key(a: StringName, b: StringName) -> String:
	return "%s>%s" % [a, b]


static func _kinds_data(table: Dictionary[String, PackedStringArray]) -> Dictionary:
	var out := {}
	var keys: Array[String] = table.keys()
	keys.sort()
	for key: String in keys:
		var kinds := PackedStringArray(table[key])
		kinds.sort()
		out[key] = Array(kinds)
	return out


static func _kinds_from(data: Variant) -> Variant:
	if not data is Dictionary:
		return null
	var out: Dictionary[String, PackedStringArray] = {}
	for key: Variant in data:
		if not key is String or (key as String).split(">").size() != 2 or not data[key] is Array:
			return null
		var kinds := PackedStringArray()
		for kind: Variant in data[key]:
			if not kind is String or (kind as String).is_empty():
				return null
			kinds.append(kind)
		out[key] = kinds
	return out


static func _is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not (key is String or key is StringName) or not _is_plain(value[key]):
					return false
			return true
	return false


static func _int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return null
