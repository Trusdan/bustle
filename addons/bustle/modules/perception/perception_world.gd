# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePerceptionWorld
extends RefCounted

## Every actor's senses in one place, with the same rules for whoever looks and whoever is looked
## at. Headless: the host adds [BustlePerceptionActor]s, keeps their fields current, supplies a
## sight-ray check ([member line_of_sight]) and calls [method tick].
##
## Each perceiver senses at its profile's [member BustlePerceptionProfile.perception_hz], with
## its phase staggered evenly by the order actors were added, so perceivers don't all sense on the same tick. It keeps one
## [BustleDetectionMeter] per target ([BustleAwareness]). A target is skipped while it is beyond
## both sight range and hearing reach and has no meter yet. The ray is cast only for a target in
## range, in the cone, visible and lit enough for the profile.
##
## The queries ([method known_nearby], [method last_known], [method perceives],
## [method perceivers_of], [method awareness], [method known_with]) read the latest senses.

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
## Rounding slack for the throttle.
const _EPSILON := 0.000001

var _actors: Dictionary = {}
var _order: Array[StringName] = []
# The actors in _order's order, so the senses loop needn't look each one up.
var _order_actors: Array[BustlePerceptionActor] = []


## Adds [param actor] (replacing one with the same id) and returns it.
func add_actor(actor: BustlePerceptionActor) -> BustlePerceptionActor:
	if not _actors.has(actor.id):
		_order.append(actor.id)
		_order_actors.append(actor)
	else:
		_order_actors[_order.find(actor.id)] = actor
	_actors[actor.id] = actor
	actor._due = actor.period() * _phase(actor.id)
	if not actor.awareness.state_changed.is_connected(_on_state_changed.bind(actor.id)):
		actor.awareness.state_changed.connect(_on_state_changed.bind(actor.id))
	return actor


## Restarts actor [param id]'s throttle with its staggered phase (after its profile changed).
func reschedule(id: StringName) -> void:
	var found := actor(id)
	if found != null:
		found._due = found.period() * _phase(id)


## Removes the actor [param id] and every perceiver's meter for it.
func remove_actor(id: StringName) -> void:
	_actors.erase(id)
	var index := _order.find(id)
	if index >= 0:
		_order.remove_at(index)
		_order_actors.remove_at(index)
	for other: StringName in _order:
		(_actors[other] as BustlePerceptionActor).awareness.forget(id)


## The actor [param id], or null.
func actor(id: StringName) -> BustlePerceptionActor:
	return _actors.get(id) as BustlePerceptionActor


## Every actor id, in the order they were added.
func actor_ids() -> Array[StringName]:
	return _order.duplicate()


## Advances every perceiver whose turn it is by [param delta] seconds.
func tick(delta: float) -> void:
	rays_last_tick = 0
	sensed_last_tick = 0
	# _order_actors changes in step with _order, so this walks the same actors as walking _order
	# would, even when host code adds or removes one mid-tick.
	for perceiver: BustlePerceptionActor in _order_actors:
		var profile := perceiver.profile
		if profile == null:
			continue
		# perceiver.period(), inline: this runs for every actor every tick.
		var period := 0.0 if profile.perception_hz <= 0.0 else 1.0 / profile.perception_hz
		perceiver._due -= delta
		if perceiver._due > _EPSILON:
			continue
		# Keep the remainder so the rate doesn't drift; never build a backlog.
		perceiver._due = maxf(perceiver._due + period, 0.0)
		sense(perceiver, period if period > 0.0 else delta)


## Senses every target from [param perceiver] once, as if [param delta] seconds passed. [method tick]
## calls it on the perceiver's turn; tests can call it directly.
func sense(perceiver: BustlePerceptionActor, delta: float) -> void:
	sensed_last_tick += 1
	var profile := perceiver.profile
	var perceiver_id := perceiver.id
	# These are read once and kept while only skipped targets go by. Host code can change them
	# (the sight ray, or a perception_changed handler during a meter's tick), so they are read
	# again after any target that ran it.
	var awareness := perceiver.awareness
	var meters: Dictionary = awareness._meters
	var position := perceiver.position
	var forward := perceiver.forward
	var sight_reach := profile.sight_range if profile.sees else 0.0
	var hears := profile.hears
	var hearing_scale := profile.hearing_scale
	# One target per sense, refilled for each actor: nothing keeps it past its meter's tick.
	var target := BustleSenseTarget.new()
	var index := -1
	for target_actor: BustlePerceptionActor in _order_actors:
		index += 1
		var target_id: StringName = _order[index]
		if target_id == perceiver_id:
			continue
		var meter: BustleDetectionMeter = meters.get(target_id)
		if target_actor.perceivable:
			var to_target := target_actor.position - position
			var distance := to_target.length()
			if meter == null:
				if distance >= maxf(sight_reach, target_actor.noise_radius * hearing_scale if hears else 0.0):
					continue
				meter = awareness.meter_for(target_id, profile)
			target.position = target_actor.position
			target.visibility = target_actor.visibility
			target.noise_radius = target_actor.noise_radius
			target.carries_light = target_actor.carries_light
			var cone := meter._cone_at(forward, to_target, distance)
			# _clear_view(), inline: no ray for a target that can't be seen anyway.
			var clear := false
			# The same comparisons as before (a NaN visibility still gets its ray).
			if not target.visibility <= 0.0 and not cone <= 0.0 \
					and (meter.profile.sight_light != BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY or target.carries_light):
				clear = _ray(perceiver, target_actor, target)
			target.line_of_sight = clear
			if perceiver.position == position and perceiver.forward == forward:
				meter._tick_at(delta, target, distance, cone)
			else:
				# The sight ray moved or turned the perceiver: sense from where it is now.
				meter.tick(delta, perceiver.position, perceiver.forward, target)
		elif meter != null:
			target.position = target_actor.position
			target.visibility = 0.0
			target.noise_radius = 0.0
			target.line_of_sight = false
			target.carries_light = false
			meter.tick(delta, position, forward, target)
		else:
			continue
		awareness = perceiver.awareness
		meters = awareness._meters
		position = perceiver.position
		forward = perceiver.forward
		sight_reach = profile.sight_range if profile.sees else 0.0
		hears = profile.hears
		hearing_scale = profile.hearing_scale


## Sends a one-off sound to every perceiver ([method BustleDetectionMeter.hear_event]). Returns
## how many heard it. It lands on each hearer's meter for [param source_id] (the actor that made
## it), else for the event's own [member BustleNoiseEvent.source_id], else for
## [constant NOISE_ID], so a sound with no actor behind it still shows up as a lead.
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
func last_known(perceiver_id: StringName, target_id: StringName) -> Variant:
	var perceiver := actor(perceiver_id)
	var found := perceiver.awareness.meter(target_id) if perceiver != null else null
	if found == null or not found.has_last_known:
		return null
	return found.last_known_position


## True when [param perceiver_id] sensed [param target_id] (seen or heard) at its last sense.
func perceives(perceiver_id: StringName, target_id: StringName) -> bool:
	var perceiver := actor(perceiver_id)
	var found := perceiver.awareness.meter(target_id) if perceiver != null else null
	return found != null and (found.seen_now or found.heard_now)


## Every perceiver that senses [param target_id] now, sorted.
func perceivers_of(target_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _order:
		if perceives(id, target_id):
			out.append(id)
	out.sort()
	return out


## [param perceiver_id]'s awareness list (one entry per target it has sensed), sorted by id.
func awareness(perceiver_id: StringName) -> Array[BustleAwarenessEntry]:
	var perceiver := actor(perceiver_id)
	if perceiver == null:
		var empty: Array[BustleAwarenessEntry] = []
		return empty
	return perceiver.awareness.entries()


## The targets [param perceiver_id] knows about (not unaware) that it regards as
## [param wanted] (for example the hostile ones a fight picks from), sorted.
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
func disposition_between(a_id: StringName, b_id: StringName) -> BustleDispositionPort.Disposition:
	var a := actor(a_id)
	var b := actor(b_id)
	return disposition.disposition(a_id, a.group if a != null else &"", b_id, b.group if b != null else &"")


# The sight ray for a target in range, in the cone, visible and lit enough.
func _ray(perceiver: BustlePerceptionActor, target_actor: BustlePerceptionActor, target: BustleSenseTarget) -> bool:
	if not line_of_sight.is_valid():
		return true
	rays_last_tick += 1
	return line_of_sight.call(perceiver.position, target.position, perceiver.id, target_actor.id) == true


func _on_state_changed(target_id: StringName, old: BustleDetectionMeter.State, new: BustleDetectionMeter.State, perceiver_id: StringName) -> void:
	perception_changed.emit(perceiver_id, target_id, old, new)


## A fraction 0..1 for [param id]'s phase: its place in the actor order times the golden ratio,
## so perceivers spread evenly over the period and the spread is the same every run.
func _phase(id: StringName) -> float:
	return fposmod(float(_order.find(id)) * 0.6180339887, 1.0)
