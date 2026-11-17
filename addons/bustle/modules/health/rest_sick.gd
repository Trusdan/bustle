# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRestSick
extends RefCounted

## The rest-when-sick goal, opt-in: an agent who is ill rests instead of working or running errands
## until the health port says it is better. Bustle names where to rest; the host moves the body and
## owns the illness and the recovery. Bustle keeps no illness state: every answer comes from the
## ports each time.
## [br][br]
## [b]Who rests:[/b] an agent the port shows one of [member sick_tags] for
## ([method BustleHealthPort.visible_tags]), or one of whose capacities is below its line in
## [member capacity_lines] ([method BustleHealthPort.capacity]), unless it is downed
## ([method BustleHealthBehaviour.is_downed]), locked ([member is_locked]), or should seek care first
## ([member seek_care]). [method fill_inputs] sets its [constant INPUT] to [method sickness].
## [br][br]
## [b]Its place:[/b] [constant BAND], above duty and below orders: it outranks ordinary work and
## errands, never an order, a lock or an urgent need. Orders aren't gated.
## [br][br]
## [b]Where:[/b] [method bed_for]: the agent's own item ([method BustlePropertyPort.items_of])
## that relieves [member bed_need], at a place the world port knows; else where it stands.
## [br][br]
## [b]Ending:[/b] the [BustleRestSickAction] rests while the agent is still ill, and is done on the
## first tick after the port clears the tag or restores the capacity.
## [br][br]
## Register a [BustleRestSickAction] for [constant ACTION] on each agent's runner. Nothing is random.
## @experimental: Added after 1.0 for the health module. The tags, lines, weights and band are PROPOSED defaults, not tuning.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")

## The patient's input: how ill it is, 0 to 1, set only while it should rest.
const INPUT := &"fact.rest_sick"
## The action the goal runs.
const ACTION := &"rest_sick"
## The goal's band: above [constant BustleBands.DUTY], below [constant BustleBands.ORDERED].
## PROPOSED.
const BAND := 65
## How close, in metres, an agent must get to its bed's place.
const REACH := 2.0

## The health behaviour it reads the ports through ([member BustleHealthBehaviour.ports]).
var health: BustleHealthBehaviour
## The visible tags that mean ill enough to rest. PROPOSED: [code]sick[/code].
var sick_tags: Array[StringName] = [&"sick"]
## Capacity name → line, 0 to 1: below the line, the agent rests. PROPOSED:
## [code]consciousness[/code] below 0.5.
var capacity_lines: Dictionary[StringName, float] = {&"consciousness": 0.5}
## How ill a sick tag counts as, 0 to 1. PROPOSED: 1.
var tag_weight: float = 1.0
## How ill a capacity at 0 counts as, 0 to 1; at its line it counts as 0, in a straight line.
## PROPOSED: 1.
var capacity_weight: float = 1.0
## The need a bed relieves ([code]relieves[/code] in a [BustlePropertyPort] item), or empty for no
## bed: the agent rests where it stands.
var bed_need: StringName = &""
## The seek-care rules to defer to: while [method BustleSeekCare.wants_care] holds, the agent seeks
## care instead of resting. Null: it rests whether or not it could seek care.
var seek_care: BustleSeekCare = null
## [code]func(id: StringName) -> bool[/code]: true while the agent is locked to a task
## (for example [method BustleSociety.is_locked]). Empty: never.
var is_locked: Callable = Callable()
## [code]func(id: StringName) -> Variant[/code]: where that agent is now (a [Vector3]), or null.
## Empty: the world port's position of the agent's area.
var where: Callable = Callable()
## [code]func(agent: StringName, place: StringName) -> bool[/code]: true when [param agent] has
## reached its bed's [param place]. Empty: within [constant REACH] metres of it (by [member where]).
var can_reach: Callable = Callable()


func _init(p_health: BustleHealthBehaviour = null, p_sick_tags: Array[StringName] = [&"sick"]) -> void:
	health = p_health
	sick_tags = p_sick_tags.duplicate()


## How ill [param agent] is, 0 to 1, by the port alone: [member tag_weight] for a sick tag, and for
## each capacity below its line [member capacity_weight] × (line − capacity) / line; the highest.
## 0 when well, with no port, or for unusable readings.
func sickness(agent: StringName) -> float:
	if agent == &"" or health == null or health.ports == null:
		return 0.0
	var port := health.ports.health
	var out := 0.0
	if not sick_tags.is_empty():
		for tag: StringName in port.visible_tags(agent):
			if sick_tags.has(tag):
				out = _weight(tag_weight, "tag_weight")
				break
	for name: StringName in capacity_lines:
		var line := float(capacity_lines[name])
		if not is_finite(line) or line <= 0.0 or line > 1.0:
			_Warn.warn("BustleRestSick.capacity_lines", "BustleRestSick: a capacity line isn't above 0 and at most 1; it is skipped")
			continue
		var amount := port.capacity(agent, name)
		if is_finite(amount) and amount < line:
			out = maxf(out, _weight(capacity_weight, "capacity_weight") * (line - clampf(amount, 0.0, 1.0)) / line)
	return clampf(out, 0.0, 1.0)


## True when [param agent] should rest now: it is ill ([method sickness]), and not downed, locked,
## or seeking care first ([member seek_care]).
func wants_rest(agent: StringName) -> bool:
	return sickness(agent) > 0.0 and _may_rest(agent)


## Sets [param agent]'s [constant INPUT] in [param inputs] to its [method sickness] while it should
## rest, or erases it.
func fill_inputs(agent: StringName, inputs: Dictionary[StringName, float]) -> void:
	inputs.erase(INPUT)
	var value := sickness(agent)
	if value > 0.0 and _may_rest(agent):
		inputs[INPUT] = value


## Where [param agent] would rest: [code]{item, place}[/code] for its own item that relieves
## [member bed_need] the most (ties in id order), at a place the world port knows; empty to rest
## where it stands.
func bed_for(agent: StringName) -> Dictionary:
	if bed_need == &"" or health == null or health.ports == null:
		return {}
	var best := {}
	var best_amount := 0.0
	for record: Dictionary in health.ports.property.items_of(agent):
		var amount := float((record.get("relieves", {}) as Dictionary).get(bed_need, 0.0))
		var place := StringName(record.get("place", &""))
		if amount > best_amount and place != &"" and health.ports.world.has_place(place):
			best = {"item": StringName(record["id"]), "place": place}
			best_amount = amount
	if best.is_empty() or not _can_judge_bed():
		return {}
	return best


## True when [param agent] is at [param bed] (from [method bed_for]); true for an empty bed.
func has_reached(agent: StringName, bed: Dictionary) -> bool:
	if bed.is_empty():
		return true
	var place := StringName(bed["place"])
	if can_reach.is_valid():
		var reached: Variant = can_reach.call(agent, place)
		if _Warn.fits(reached, "bool", "BustleRestSick.can_reach"):
			return bool(reached)
	var here: Variant = position_of(agent)
	return here is Vector3 and (here as Vector3).distance_to(health.ports.world.place_position(place)) <= REACH


## Where [param id] is now, from [member where], else the world port's position of its area; null
## when [member where] doesn't say.
func position_of(id: StringName) -> Variant:
	if where.is_valid():
		var found: Variant = where.call(id)
		if found == null:
			return null
		if found is Vector3 and (found as Vector3).is_finite():
			return found
		_Warn.warn("BustleRestSick.where.wrong_type", "BustleRestSick.where: the hook returned %s, not a Vector3 or null; using no position" % type_string(typeof(found)))
		return null
	var world := health.ports.world
	return world.place_position(world.area_of(id))


## The rest-when-sick goal: band [param band] ([constant BAND] by default), tags
## [code]rest_sick[/code] and [code]travel[/code] (so the downed gate blocks it too), scored by
## [constant INPUT] in a straight line, running [constant ACTION] until the agent is well.
static func goal_def(band: int = BAND) -> BustleGoalDef:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = INPUT
	consideration.curve = curve
	var sequence := BustleActionSequence.new()
	var rest := BustleActionStep.new()
	rest.action = ACTION
	sequence.steps.append(rest)
	var goal := BustleGoalDef.new()
	goal.id = &"rest_sick"
	goal.band = band
	goal.tags = [&"rest_sick", &"travel"]
	goal.considerations.append(consideration)
	goal.sequence = sequence
	return goal


# True when nothing keeps an ill [param agent] from resting: not downed, not locked, and not
# seeking care first.
func _may_rest(agent: StringName) -> bool:
	if health.is_downed(agent):
		return false
	if is_locked.is_valid() and _Warn.as_bool(is_locked.call(agent), false, "BustleRestSick.is_locked"):
		return false
	return seek_care == null or not seek_care.wants_care(agent)


# A weight to use: [param value] clamped to 0..1, or 1 (with one warning) when it isn't finite.
func _weight(value: float, name: String) -> float:
	if is_finite(value):
		return clampf(value, 0.0, 1.0)
	_Warn.warn("BustleRestSick." + name, "BustleRestSick: %s isn't a number; using 1" % name)
	return 1.0


# A bed can be used only when its arrival can be told: by can_reach or by where.
func _can_judge_bed() -> bool:
	if can_reach.is_valid() or where.is_valid():
		return true
	_Warn.warn("BustleRestSick.bed", "BustleRestSick: bed_need is set but neither where nor can_reach is, so arrival at a bed can't be told; the agent rests where it stands")
	return false
