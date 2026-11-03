# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceptionWorld
extends RefCounted

## Every actor's senses in one place, with the same rules for whoever looks and whoever is looked
## at. Headless: the host adds [BustlePerceptionActor]s, keeps their fields current, supplies a
## sight-ray check ([member line_of_sight]) and calls [method tick].
##
## Each perceiver senses at its profile's [member BustlePerceptionProfile.perception_hz], with
## its phase staggered by its id so perceivers don't all sense on the same tick. It keeps one
## [BustleDetectionMeter] per target ([BustleAwareness]). A target is skipped while it is beyond
## both sight range and hearing reach and has no meter yet. The ray is cast only for a target in
## range, in the cone, visible and lit enough for the profile.
##
## The queries ([method known_nearby], [method last_known], [method perceives],
## [method perceivers_of], [method awareness], [method known_with]) read the latest senses.
## @experimental

## A perceiver's awareness of a target changed state. Emitted on state changes only.
signal perception_changed(perceiver_id: StringName, target_id: StringName, old_state: BustleDetectionMeter.State, new_state: BustleDetectionMeter.State)

## [code]func(from: Vector3, to: Vector3, perceiver_id: StringName, target_id: StringName) -> bool[/code]:
## true when nothing blocks the view. Unset: nothing ever blocks.
var line_of_sight: Callable
## How actors regard each other. The default is neutral everywhere.
var disposition := BustleDispositionPort.new()
## How many sight rays the last [method tick] cast (for benches and tests).
var rays_last_tick: int = 0
## How many perceivers sensed in the last [method tick].
var sensed_last_tick: int = 0

## The awareness key for a broadcast sound with no source.
const NOISE_ID := &"noise"

var _actors: Dictionary = {}
var _order: Array[StringName] = []


## Adds [param actor] (replacing one with the same id) and returns it.
## @experimental
func add_actor(actor: BustlePerceptionActor) -> BustlePerceptionActor:
	if not _actors.has(actor.id):
		_order.append(actor.id)
	_actors[actor.id] = actor
	actor._due = actor.period() * _phase(actor.id)
	if not actor.awareness.state_changed.is_connected(_on_state_changed.bind(actor.id)):
		actor.awareness.state_changed.connect(_on_state_changed.bind(actor.id))
	return actor


## Removes the actor [param id] and every perceiver's meter for it.
## @experimental
func remove_actor(id: StringName) -> void:
	_actors.erase(id)
	_order.erase(id)
	for other: StringName in _order:
		(_actors[other] as BustlePerceptionActor).awareness.forget(id)


## The actor [param id], or null.
## @experimental
func actor(id: StringName) -> BustlePerceptionActor:
	return _actors.get(id) as BustlePerceptionActor


## Every actor id, in the order they were added.
## @experimental
func actor_ids() -> Array[StringName]:
	return _order.duplicate()


## Advances every perceiver whose turn it is by [param delta] seconds.
## @experimental
func tick(delta: float) -> void:
	rays_last_tick = 0
	sensed_last_tick = 0
	for id: StringName in _order:
		var perceiver: BustlePerceptionActor = _actors[id]
		if not perceiver.perceives():
			continue
		perceiver._due -= delta
		if perceiver._due > 0.0:
			continue
		var elapsed := perceiver.period() - perceiver._due if perceiver.period() > 0.0 else delta
		perceiver._due = perceiver.period()
		sense(perceiver, maxf(elapsed, delta))


## Senses every target from [param perceiver] once, as if [param delta] seconds passed. [method tick]
## calls it on the perceiver's turn; tests can call it directly.
## @experimental
func sense(perceiver: BustlePerceptionActor, delta: float) -> void:
	sensed_last_tick += 1
	var profile := perceiver.profile
	for target_id: StringName in _order:
		if target_id == perceiver.id:
			continue
		var target_actor: BustlePerceptionActor = _actors[target_id]
		if not target_actor.perceivable:
			if perceiver.awareness.has(target_id):
				perceiver.awareness.meter(target_id).tick(delta, perceiver.position, perceiver.forward, BustleSenseTarget.new(target_actor.position, 0.0, 0.0, false))
			continue
		var distance := perceiver.position.distance_to(target_actor.position)
		var reach := maxf(profile.sight_range if profile.sees else 0.0, target_actor.noise_radius * profile.hearing_scale if profile.hears else 0.0)
		if distance >= reach and not perceiver.awareness.has(target_id):
			continue
		var target := target_actor.as_target()
		var meter := perceiver.awareness.meter_for(target_id, profile)
		target.line_of_sight = _clear_view(perceiver, target_actor, meter, target)
		meter.tick(delta, perceiver.position, perceiver.forward, target)


## Sends a one-off sound to every perceiver ([method BustleDetectionMeter.hear_event]). Returns
## how many heard it. It lands on each hearer's meter for [param source_id] (the actor that made
## it), else for the event's own [member BustleNoiseEvent.source_id], else for
## [constant NOISE_ID], so a sound with no actor behind it still shows up as a lead.
## @experimental
func broadcast(event: BustleNoiseEvent, source_id: StringName = &"") -> int:
	var key := source_id if source_id != &"" else event.source_id
	if key == &"":
		key = NOISE_ID
	var heard := 0
	for id: StringName in _order:
		var perceiver: BustlePerceptionActor = _actors[id]
		if not perceiver.perceives() or id == key:
			continue
		if not event.reaches(perceiver.position, perceiver.profile.hearing_scale) or not perceiver.profile.hears:
			continue
		if perceiver.awareness.meter_for(key, perceiver.profile).hear_event(event, perceiver.position):
			heard += 1
	return heard


## The targets [param perceiver_id] knows about (not unaware) whose last known position is within
## [param radius] of it, sorted.
## @experimental
func known_nearby(perceiver_id: StringName, radius: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var perceiver := actor(perceiver_id)
	if perceiver == null:
		return out
	for entry: BustleAwarenessEntry in perceiver.awareness.entries():
		if entry.state != BustleDetectionMeter.State.UNAWARE and entry.has_last_known \
				and entry.last_known_position.distance_to(perceiver.position) <= radius:
			out.append(entry.target_id)
	return out


## Where [param perceiver_id] last sensed [param target_id], or null if it never has.
## @experimental
func last_known(perceiver_id: StringName, target_id: StringName) -> Variant:
	var perceiver := actor(perceiver_id)
	var found := perceiver.awareness.meter(target_id) if perceiver != null else null
	if found == null or not found.has_last_known:
		return null
	return found.last_known_position


## True when [param perceiver_id] sensed [param target_id] (seen or heard) at its last sense.
## @experimental
func perceives(perceiver_id: StringName, target_id: StringName) -> bool:
	var perceiver := actor(perceiver_id)
	var found := perceiver.awareness.meter(target_id) if perceiver != null else null
	return found != null and (found.seen_now or found.heard_now)


## Every perceiver that senses [param target_id] now, sorted.
## @experimental
func perceivers_of(target_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _order:
		if perceives(id, target_id):
			out.append(id)
	out.sort()
	return out


## [param perceiver_id]'s awareness list (one entry per target it has sensed), sorted by id.
## @experimental
func awareness(perceiver_id: StringName) -> Array[BustleAwarenessEntry]:
	var perceiver := actor(perceiver_id)
	if perceiver == null:
		var empty: Array[BustleAwarenessEntry] = []
		return empty
	return perceiver.awareness.entries()


## The targets [param perceiver_id] knows about (not unaware) that it regards as
## [param wanted] (for example the hostile ones a fight picks from), sorted.
## @experimental
func known_with(perceiver_id: StringName, wanted: BustleDispositionPort.Disposition) -> Array[StringName]:
	var out: Array[StringName] = []
	var perceiver := actor(perceiver_id)
	if perceiver == null:
		return out
	for entry: BustleAwarenessEntry in perceiver.awareness.entries():
		var other := actor(entry.target_id)
		if entry.state == BustleDetectionMeter.State.UNAWARE or other == null:
			continue
		if disposition.disposition(perceiver.id, perceiver.group, other.id, other.group) == wanted:
			out.append(entry.target_id)
	return out


## How [param a_id] regards [param b_id], through [member disposition].
## @experimental
func disposition_between(a_id: StringName, b_id: StringName) -> BustleDispositionPort.Disposition:
	var a := actor(a_id)
	var b := actor(b_id)
	return disposition.disposition(a_id, a.group if a != null else &"", b_id, b.group if b != null else &"")


func _clear_view(perceiver: BustlePerceptionActor, target_actor: BustlePerceptionActor, meter: BustleDetectionMeter, target: BustleSenseTarget) -> bool:
	if target.visibility <= 0.0 or not meter.light_allows(target):
		return false
	if meter.sight_cone(perceiver.position, perceiver.forward, target.position) <= 0.0:
		return false
	if not line_of_sight.is_valid():
		return true
	rays_last_tick += 1
	return line_of_sight.call(perceiver.position, target.position, perceiver.id, target_actor.id) == true


func _on_state_changed(target_id: StringName, old: BustleDetectionMeter.State, new: BustleDetectionMeter.State, perceiver_id: StringName) -> void:
	perception_changed.emit(perceiver_id, target_id, old, new)


## A stable fraction 0..1 from [param id], so each perceiver's phase is the same every run.
static func _phase(id: StringName) -> float:
	return float(String(id).hash() & 0xFFFF) / 65536.0
