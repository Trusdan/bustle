# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAwarenessEntry
extends RefCounted

## One line of a perceiver's awareness list: what it knows about one target right now. A snapshot;
## it doesn't change after it is made.
## @experimental

## The target's id.
var target_id: StringName = &""
## The awareness state ([enum BustleDetectionMeter.State]).
var state: BustleDetectionMeter.State = BustleDetectionMeter.State.UNAWARE
## The meter level, 0..1.
var confidence: float = 0.0
## Where the target was last sensed. Only meaningful while [member has_last_known].
var last_known_position := Vector3.ZERO
## True while there is a last known position.
var has_last_known := false
## Seen at the last sense.
var seen_now := false
## Heard at the last sense.
var heard_now := false
## Seconds since the target was last sensed ([constant INF] if never).
var freshness: float = INF


## A snapshot of [param meter] for [param p_target_id].
## @experimental
static func from_meter(p_target_id: StringName, meter: BustleDetectionMeter) -> BustleAwarenessEntry:
	var entry := BustleAwarenessEntry.new()
	entry.target_id = p_target_id
	entry.state = meter.state
	entry.confidence = meter.level
	entry.last_known_position = meter.last_known_position
	entry.has_last_known = meter.has_last_known
	entry.seen_now = meter.seen_now
	entry.heard_now = meter.heard_now
	entry.freshness = meter.since_sensed
	return entry


## True when the target is sensed right now.
## @experimental
func perceived_now() -> bool:
	return seen_now or heard_now
