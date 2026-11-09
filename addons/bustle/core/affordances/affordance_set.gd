# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAffordanceSet
extends RefCounted

## The placed affordances of a population, by id, so one generic "use something" goal can score
## them all. [method advertisements] gives the scorer one advertisement per affordance an agent may
## use (refused, full and unaffordable ones are left out), in id order.
## @experimental

var _all: Dictionary[StringName, BustleAffordance] = {}


## Adds [param affordance]. False for an empty or taken id, or an invalid def.
## @experimental
func add(affordance: BustleAffordance) -> bool:
	if affordance == null or affordance.id == &"" or _all.has(affordance.id) or not affordance.def.is_valid():
		return false
	_all[affordance.id] = affordance
	return true


## Removes affordance [param id].
## @experimental
func remove(id: StringName) -> void:
	_all.erase(id)


## Affordance [param id], or null.
## @experimental
func get_affordance(id: StringName) -> BustleAffordance:
	return _all.get(id)


## Every id, sorted.
## @experimental
func ids() -> Array[StringName]:
	var out: Array[StringName] = _all.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The ids of the affordances in [param area], sorted.
## @experimental
func in_area(area: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ids():
		if _all[id].area == area:
			out.append(id)
	return out


## What [param agent] is offered at minute [param now]: one advertisement per affordance it may
## use, in id order. [param distance] maps an affordance to its distance (empty: 0). Only
## [param only] (when not empty) are considered: a host passes the ones the agent knows of.
## @experimental
func advertisements(agent: StringName, now: int, distance: Callable = Callable(), trade: BustleTradePort = null, leisure: BustleLeisure = null, only: Array[StringName] = []) -> Array[BustleAdvertisement]:
	var out: Array[BustleAdvertisement] = []
	for id: StringName in ids():
		if not only.is_empty() and not only.has(id):
			continue
		var affordance := _all[id]
		var far := float(distance.call(affordance)) if distance.is_valid() else 0.0
		var ad := affordance.advertise(agent, now, far if is_finite(far) else 0.0, trade, leisure)
		if ad != null:
			out.append(ad)
	return out


## Every affordance's state ([method BustleAffordance.export_state]) by id.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in ids():
		out[String(id)] = _all[id].export_state()
	return {"affordances": out}


## Restores [method export_state] for the affordances it has (others are skipped). False, changing
## nothing, when any entry is malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("affordances") is Dictionary:
		return false
	var entries: Dictionary = saved["affordances"]
	var copies: Dictionary[StringName, BustleAffordance] = {}
	for key: Variant in entries:
		if not key is String:
			return false
		var live := get_affordance(StringName(key))
		if live == null:
			continue
		var copy := BustleAffordance.new(live.id, live.def, live.area, live.position)
		if not copy.import_state(entries[key]):
			return false
		copies[live.id] = copy
	for id: StringName in copies:
		_all[id].import_state(entries[String(id)])
	return true
