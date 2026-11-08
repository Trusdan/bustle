# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleModifierSet
extends RefCounted

## Numbers that sources (a trait, a mood, an injury) add to or multiply, by key, so modules read
## one value without knowing where its parts came from. A key is dot-separated lower-case names,
## such as [code]need.company.rate[/code] or [code]tag.social.mult[/code].
##
## [code]value(key, base) = (base + Σ add) × Π mult[/code], with every source applied in sorted
## source-id order, so the result never depends on the order sources were set. A source has at most
## one entry per key; setting it again replaces it.
## @experimental

# key → source id → [add, mult]
var _entries: Dictionary = {}


## Sets [param source_id]'s contribution to [param key], replacing any earlier one. False (with an
## error) when the key is malformed or a number isn't finite.
## @experimental
func set_source(source_id: StringName, key: StringName, add: float = 0.0, mult: float = 1.0) -> bool:
	if not is_valid_key(key) or source_id == &"" or not is_finite(add) or not is_finite(mult):
		push_error("BustleModifierSet: refused %s from %s" % [key, source_id])
		return false
	if not _entries.has(key):
		_entries[key] = {}
	(_entries[key] as Dictionary)[source_id] = [add, mult]
	return true


## Removes every contribution from [param source_id].
## @experimental
func remove_source(source_id: StringName) -> void:
	for key: StringName in _entries.keys():
		var sources: Dictionary = _entries[key]
		sources.erase(source_id)
		if sources.is_empty():
			_entries.erase(key)


## True when some source contributes to [param key].
## @experimental
func has(key: StringName) -> bool:
	return _entries.has(key)


## [param base] with every source's contribution to [param key] applied.
## @experimental
func value(key: StringName, base: float) -> float:
	if not _entries.has(key):
		return base
	var sources: Dictionary = _entries[key]
	var ids: Array = sources.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var add := 0.0
	var mult := 1.0
	for id: StringName in ids:
		add += float(sources[id][0])
		mult *= float(sources[id][1])
	return (base + add) * mult


## Fills [param context]'s need weights ([code]need.<n>.weight[/code], base 1) for [param needs]
## and tag multipliers ([code]tag.<t>.mult[/code], base 1) for [param tags].
## @experimental
func fill_context(context: BustleScoreContext, needs: Array[StringName], tags: Array[StringName]) -> void:
	for need: StringName in needs:
		context.need_weights[need] = value(StringName("need.%s.weight" % need), 1.0)
	for tag: StringName in tags:
		context.tag_mults[tag] = value(StringName("tag.%s.mult" % tag), 1.0)


## True when [param key] is two or more dot-separated names of lower-case letters, digits and
## underscores.
## @experimental
static func is_valid_key(key: StringName) -> bool:
	var parts := String(key).split(".")
	if parts.size() < 2:
		return false
	for part: String in parts:
		if part.is_empty():
			return false
		for i in part.length():
			var c := part.unicode_at(i)
			if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
				return false
	return true
