# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSeekCare
extends RefCounted

## The seek-care goal, opt-in: an agent who needs care goes to someone, or somewhere, that can give
## it. Bustle names where; the host moves the body, gives the care and owns the recovery. Bustle
## keeps no health state: every answer comes from the ports each time.
## [br][br]
## [b]Who seeks care:[/b] an agent whose [method BustleHealthPort.needs_care] is at or above
## [member threshold], who isn't downed ([method BustleHealthBehaviour.is_downed]) and who has a
## destination. [method fill_inputs] sets its [constant INPUT] to that need, so the
## [method goal_def] goal scores higher the more urgent the care.
## [br][br]
## [b]Where:[/b] [method destination_for]: the holder of the first of [member care_roles] that is
## held, by someone else who isn't downed ([method BustleRolesPort.holder_of]); else
## [member care_place], a place the world port knows ([method BustleWorldPort.has_place]). Who
## counts as a healer is the host's call: name the roles, and give them to whom it chooses.
## [br][br]
## [b]Arriving:[/b] an agent target is reached in the same area ([method BustleWorldPort.area_of]),
## a place within [constant REACH] metres of it (by [member where]), or by [member can_reach] when
## set. Once there, the patient waits, so a healer whose [member BustleTendJob.nearby] includes it
## can tend it; the tend job itself is unchanged.
## [br][br]
## Register a [BustleSeekCareAction] for [constant ACTION] on each agent's runner. Nothing is random.
## @experimental: Added after 1.0 for the health module. The threshold, the reach and the wait are proposed defaults, not tuning.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")

## The patient's input: how urgently it needs care, 0 to 1, set only while it seeks care.
const INPUT := &"fact.seek_care"
## The action the goal runs.
const ACTION := &"seek_care"
## How close, in metres, a patient must get to a care place.
const REACH := 2.0

## The health behaviour it reads the ports through ([member BustleHealthBehaviour.ports]).
var health: BustleHealthBehaviour
## The need for care, 0 to 1, from which an agent seeks it. Above 0: an agent who needs no care
## never seeks it.
var threshold: float = 0.5
## The roles whose holders give care, in order of preference. Empty: no one is sought.
var care_roles: Array[StringName] = []
## A place to go for care when no care role is held (for example an infirmary), or empty. Needs
## [member where] or [member can_reach] to tell when the patient is there.
var care_place: StringName = &""
## [code]func(id: StringName) -> Variant[/code]: where that agent is now (a [Vector3]), or null.
## Empty: the world port's position of the agent's area.
var where: Callable = Callable()
## [code]func(patient: StringName, target: StringName) -> bool[/code]: true when [param patient] has
## reached [param target] (an agent or a place). Empty: the rules above.
var can_reach: Callable = Callable()


func _init(p_health: BustleHealthBehaviour = null, p_care_roles: Array[StringName] = []) -> void:
	health = p_health
	care_roles = p_care_roles.duplicate()


## True when [param patient] should seek care now: its need is at or above [member threshold], it
## isn't downed, and it has a destination ([method destination_for]).
func wants_care(patient: StringName) -> bool:
	return need(patient) > 0.0 and not destination_for(patient).is_empty()


## How urgently [param patient] needs care, 0 to 1, when that is at or above [member threshold]
## and it isn't downed; 0 otherwise (and for an unusable reading).
func need(patient: StringName) -> float:
	if patient == &"" or health == null or health.ports == null or health.is_downed(patient):
		return 0.0
	var value := health.ports.health.needs_care(patient)
	if not is_finite(value):
		return 0.0
	value = clampf(value, 0.0, 1.0)
	return value if value > 0.0 and value >= _threshold() else 0.0


## Where [param patient] would go for care: [code]{kind: &"agent", target}[/code] for the holder of
## the first held care role (not the patient, not downed), else [code]{kind: &"place", target}[/code]
## for [member care_place] when the world port knows it, else empty.
func destination_for(patient: StringName) -> Dictionary:
	if health == null or health.ports == null:
		return {}
	for role: StringName in care_roles:
		if role == &"":
			continue
		var holder := health.ports.roles.holder_of(role)
		if holder != &"" and holder != patient and not health.is_downed(holder):
			return {"kind": &"agent", "target": holder}
	if care_place != &"" and health.ports.world.has_place(care_place) and _can_judge_place():
		return {"kind": &"place", "target": care_place}
	return {}


## Sets [param patient]'s [constant INPUT] in [param inputs] to its [method need] while it seeks
## care, or erases it.
func fill_inputs(patient: StringName, inputs: Dictionary[StringName, float]) -> void:
	inputs.erase(INPUT)
	var value := need(patient)
	if value > 0.0 and not destination_for(patient).is_empty():
		inputs[INPUT] = value


## True when [param patient] has reached [param destination] (from [method destination_for]).
func has_reached(patient: StringName, destination: Dictionary) -> bool:
	if destination.is_empty() or health == null or health.ports == null:
		return false
	var target := StringName(destination.get("target", &""))
	if can_reach.is_valid():
		var reached: Variant = can_reach.call(patient, target)
		if _Warn.fits(reached, "bool", "BustleSeekCare.can_reach"):
			return bool(reached)
	var world := health.ports.world
	if destination.get("kind") == &"agent":
		return world.area_of(patient) == world.area_of(target)
	var here: Variant = position_of(patient)
	return here is Vector3 and (here as Vector3).distance_to(world.place_position(target)) <= REACH


## Where to move [param patient] towards for [param destination]: the target agent's position, or
## the place's; null when it can't be told.
func position_for(destination: Dictionary) -> Variant:
	if destination.is_empty() or health == null or health.ports == null:
		return null
	var target := StringName(destination.get("target", &""))
	if destination.get("kind") == &"place":
		return health.ports.world.place_position(target)
	return position_of(target)


## Where [param id] is now, from [member where], else the world port's position of its area; null
## when [member where] doesn't say.
func position_of(id: StringName) -> Variant:
	if where.is_valid():
		var found: Variant = where.call(id)
		if found == null:
			return null
		if found is Vector3 and (found as Vector3).is_finite():
			return found
		_Warn.warn("BustleSeekCare.where.wrong_type", "BustleSeekCare.where: the hook returned %s, not a Vector3 or null; using no position" % type_string(typeof(found)))
		return null
	var world := health.ports.world
	return world.place_position(world.area_of(id))


## The seek-care goal: band [param band] ([constant BustleBands.PERSONAL] by default), tags
## [code]seek_care[/code] and [code]travel[/code] (so the downed gate blocks it too), scored by
## [constant INPUT] in a straight line, running [constant ACTION] and then waiting [param minutes]
## game minutes where it arrived, for care. A failed run (nowhere to go) waits the same before the
## goal can be chosen again.
static func goal_def(minutes: int = 30, band: int = BustleBands.PERSONAL) -> BustleGoalDef:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = INPUT
	consideration.curve = curve
	var sequence := BustleActionSequence.new()
	var go := BustleActionStep.new()
	go.action = ACTION
	sequence.steps.append(go)
	var wait := BustleActionStep.new()
	wait.action = &"wait"
	wait.params = {"minutes": maxi(minutes, 0)}
	sequence.steps.append(wait)
	var goal := BustleGoalDef.new()
	goal.id = &"seek_care"
	goal.band = band
	goal.tags = [&"seek_care", &"travel"]
	goal.fail_cooldown_minutes = maxi(minutes, 0)
	goal.considerations.append(consideration)
	goal.sequence = sequence
	return goal


# The threshold to use: [member threshold], or 0.5 (with one warning) when it isn't a number in 0..1.
func _threshold() -> float:
	if is_finite(threshold) and threshold >= 0.0 and threshold <= 1.0:
		return threshold
	_Warn.warn("BustleSeekCare.threshold", "BustleSeekCare: threshold %s isn't between 0 and 1; using 0.5" % threshold)
	return 0.5


# A care place can be used only when its arrival can be told: by can_reach or by where.
func _can_judge_place() -> bool:
	if can_reach.is_valid() or where.is_valid():
		return true
	_Warn.warn("BustleSeekCare.care_place", "BustleSeekCare: care_place is set but neither where nor can_reach is, so arrival there can't be told; the place isn't used")
	return false
