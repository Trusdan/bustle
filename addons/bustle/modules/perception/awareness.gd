# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAwareness
extends RefCounted

## One perceiver's awareness list: a [BustleDetectionMeter] per target it has sensed, keyed by
## the target's id. Meters are made the first time a target is sensed or heard.
## @experimental

## A target's meter changed state.
signal state_changed(target_id: StringName, old: BustleDetectionMeter.State, new: BustleDetectionMeter.State)

var _meters: Dictionary = {}


## The meter for [param target_id], made with [param profile] if there is none yet.
## @experimental
func meter_for(target_id: StringName, profile: BustlePerceptionProfile) -> BustleDetectionMeter:
	if _meters.has(target_id):
		return _meters[target_id]
	var meter := BustleDetectionMeter.new(profile)
	meter.state_changed.connect(func(old: BustleDetectionMeter.State, new: BustleDetectionMeter.State) -> void: state_changed.emit(target_id, old, new))
	_meters[target_id] = meter
	return meter


## The meter for [param target_id], or null if it has never been sensed.
## @experimental
func meter(target_id: StringName) -> BustleDetectionMeter:
	return _meters.get(target_id) as BustleDetectionMeter


## True when there is a meter for [param target_id].
## @experimental
func has(target_id: StringName) -> bool:
	return _meters.has(target_id)


## The ids with a meter.
## @experimental
func target_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _meters:
		out.append(id)
	return out


## A snapshot entry for [param target_id], or null.
## @experimental
func entry(target_id: StringName) -> BustleAwarenessEntry:
	var found := meter(target_id)
	return BustleAwarenessEntry.from_meter(target_id, found) if found != null else null


## Snapshot entries for every target, sorted by id.
## @experimental
func entries() -> Array[BustleAwarenessEntry]:
	var ids := target_ids()
	ids.sort()
	var out: Array[BustleAwarenessEntry] = []
	for id: StringName in ids:
		out.append(entry(id))
	return out


## Drops [param target_id]'s meter (for example when the target is gone for good).
## @experimental
func forget(target_id: StringName) -> void:
	_meters.erase(target_id)


## Every meter as plain data, for a save.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in _meters:
		out[String(id)] = (_meters[id] as BustleDetectionMeter).export_state()
	return out


## Restores [method export_state]'s data, making each meter with [param profile]. Emits no
## signals.
## @experimental
func import_state(data: Dictionary, profile: BustlePerceptionProfile) -> void:
	_meters.clear()
	for key: Variant in data:
		var value: Variant = data[key]
		if value is Dictionary:
			meter_for(StringName(str(key)), profile).import_state(value)
