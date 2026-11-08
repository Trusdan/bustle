# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLeisure
extends RefCounted

## Leisure with kinds and tolerance, so agents vary what they do for fun. Each kind (for example
## a walk, music, games) has a tolerance from 0 to 1. Every use of a kind adds
## [member tolerance_per_use] to it, and tolerances fall by [member tolerance_decay_per_day] per game
## day. [method adjust] scales an option's relief of [member need] by [code]1 − tolerance[/code],
## and to 0 at or past [member boredom_threshold], so the scorer stops picking a kind it is bored of
## and turns to another. An option's kind is its first tag that is one of [member kinds].
## [br][br]
## The defaults are a starting point, not tuning: a host sets its own. Tuning that isn't a finite
## number counts as 0 (the threshold as 1), and tolerances stay within 0 to 1.
## @experimental

## The need that leisure meets.
var need: StringName = &"leisure"
## The leisure kinds (tags on options).
var kinds: Array[StringName] = []
## Tolerance added by one use.
var tolerance_per_use: float = 0.25
## Tolerance lost per game day.
var tolerance_decay_per_day: float = 0.5
## At or above this tolerance, a kind gives no relief.
var boredom_threshold: float = 0.75

var _tolerance: Dictionary[StringName, float] = {}


## [param kind]'s tolerance, from 0 to 1.
## @experimental
func tolerance(kind: StringName) -> float:
	return _tolerance.get(kind, 0.0)


## True when [param kind] is at or past the boredom threshold.
## @experimental
func is_bored(kind: StringName) -> bool:
	var threshold := clampf(boredom_threshold, 0.0, 1.0) if is_finite(boredom_threshold) else 1.0
	return tolerance(kind) >= threshold - 1e-9


## How much of its relief an option of [param kind] still gives: [code]1 − tolerance[/code], or 0
## when bored. 1 for anything that isn't a leisure kind.
## @experimental
func relief_factor(kind: StringName) -> float:
	if not kinds.has(kind):
		return 1.0
	return 0.0 if is_bored(kind) else 1.0 - tolerance(kind)


## The leisure kind of [param ad] (its first tag that is a kind), or empty.
## @experimental
func kind_of(ad: BustleAdvertisement) -> StringName:
	for tag: StringName in ad.tags:
		if kinds.has(tag):
			return tag
	return &""


## A copy of [param ad] with its relief of [member need] scaled by its kind's
## [method relief_factor]. Options of no kind come back unchanged (as a copy).
## @experimental
func adjust(ad: BustleAdvertisement) -> BustleAdvertisement:
	var out := BustleAdvertisement.new(ad.option_id, ad.relief.duplicate(), ad.adds.duplicate(), ad.tags.duplicate(), ad.distance)
	var kind := kind_of(ad)
	if kind != &"" and out.relief.has(need):
		out.relief[need] = out.relief[need] * relief_factor(kind)
	return out


## Records one use of [param kind]: its tolerance rises by [member tolerance_per_use]. Returns the
## relief factor the use had (before the rise), so the caller can scale what it relieves.
## @experimental
func use(kind: StringName) -> float:
	var factor := relief_factor(kind)
	if kinds.has(kind):
		_tolerance[kind] = clampf(tolerance(kind) + _rate(tolerance_per_use), 0.0, 1.0)
	return factor


## Lets [param minutes] of game time pass: every tolerance falls.
## @experimental
func advance(minutes: float) -> void:
	if not is_finite(minutes) or minutes <= 0.0:
		return
	var fall := _rate(tolerance_decay_per_day) * minutes / 1440.0
	if not is_finite(fall):
		return
	for kind: StringName in _tolerance.keys():
		var left := tolerance(kind) - fall
		if left <= 0.0:
			_tolerance.erase(kind)
		else:
			_tolerance[kind] = left


## The tolerances as plain data: [code]{"tolerance": {kind: value}}[/code].
## @experimental
func export_state() -> Dictionary:
	var out := {}
	var keys: Array[StringName] = _tolerance.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for kind: StringName in keys:
		out[String(kind)] = _tolerance[kind]
	return {"tolerance": out}


## Restores tolerances from [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("tolerance") is Dictionary:
		return false
	var staged: Dictionary[StringName, float] = {}
	var data: Dictionary = saved["tolerance"]
	for key: Variant in data:
		var value: Variant = data[key]
		if not (key is String or key is StringName) or not (value is float or value is int) or not is_finite(float(value)):
			return false
		staged[StringName(key)] = clampf(float(value), 0.0, 1.0)
	_tolerance = staged
	return true


static func _rate(value: float) -> float:
	return maxf(value, 0.0) if is_finite(value) else 0.0
