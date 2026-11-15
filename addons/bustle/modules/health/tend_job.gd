# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTendJob
extends RefCounted

## The tend job, opt-in: an able agent tends someone near it who needs care. Bustle only asks; the
## host does the care and owns the recovery ([method BustleHealthPort.care]).
## [br][br]
## [method fill_inputs] sets the healer's [constant INPUT] to the urgency of its [method patient_for]
## (the patient's [method BustleHealthPort.needs_care]), so the [method goal_def] goal scores higher
## the more urgent the care. Its band is [constant BustleBands.PERSONAL]: a busy agent (on duty, in a
## need it must see to, or under an order) doesn't tend. A downed agent doesn't either: it gets no
## input, and the goal carries [code]work[/code], which the downed gate blocks. Orders aren't gated.
## [br][br]
## Register a [BustleTendAction] for [constant ACTION] on each healer's runner. Nothing is random and
## nothing is kept: the patient is chosen from the port's readings each time.

## The healer's input: the urgency of the care it could give, 0 to 1, set only while above 0.
const INPUT := &"fact.tend"
## The action the goal runs.
const ACTION := &"tend"

## [param healer] asked the host to care for [param patient]; [param done] is the host's answer.
signal tended(healer: StringName, patient: StringName, done: bool)

## The health behaviour it reads the port through.
var health: BustleHealthBehaviour
## [code]func(healer) -> Array[StringName][/code]: who [code]healer[/code] could tend now (for example
## the agents in its area). Unset: nobody, so nobody tends.
var nearby: Callable = Callable()


func _init(p_health: BustleHealthBehaviour = null, p_nearby: Callable = Callable()) -> void:
	health = p_health
	nearby = p_nearby


## Who [param healer] would tend now: of those [member nearby], not itself, the one whose
## [method BustleHealthPort.needs_care] is highest and above 0 (ties in id order). Empty when
## [param healer] is downed, or nobody needs care.
func patient_for(healer: StringName) -> StringName:
	if health == null or health.ports == null or not nearby.is_valid() or health.is_downed(healer):
		return &""
	var found: Variant = nearby.call(healer)
	if not found is Array:
		return &""
	var best := &""
	var best_care := 0.0
	var ids: Array[StringName] = []
	ids.assign(found)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		var care := urgency(id)
		if id != healer and care > best_care:
			best = id
			best_care = care
	return best


## How urgently [param patient] needs care, 0 to 1 (0 for an unusable reading).
func urgency(patient: StringName) -> float:
	if health == null or health.ports == null:
		return 0.0
	var value := health.ports.health.needs_care(patient)
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


## Sets [param healer]'s [constant INPUT] in [param inputs] to its patient's urgency, or erases it
## when there is no patient.
func fill_inputs(healer: StringName, inputs: Dictionary[StringName, float]) -> void:
	inputs.erase(INPUT)
	var patient := patient_for(healer)
	if patient != &"":
		inputs[INPUT] = urgency(patient)


## Asks the host to have [param healer] care for [param patient], and emits [signal tended] with
## its answer. False with no port, or when the host refuses.
func tend(healer: StringName, patient: StringName) -> bool:
	if health == null or health.ports == null or patient == &"" or patient == healer:
		return false
	var done := health.ports.health.care(healer, patient)
	tended.emit(healer, patient, done)
	return done


## The tend goal: band [constant BustleBands.PERSONAL], tags [code]tend[/code] and [code]work[/code],
## scored by [constant INPUT] in a straight line, running [constant ACTION] and then waiting
## [param minutes] game minutes, so care is asked for at most that often. A refused request waits
## the same before the goal can be chosen again. Experimental defaults.
static func goal_def(minutes: int = 30) -> BustleGoalDef:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = INPUT
	consideration.curve = curve
	var sequence := BustleActionSequence.new()
	var tend_step := BustleActionStep.new()
	tend_step.action = ACTION
	sequence.steps.append(tend_step)
	var wait := BustleActionStep.new()
	wait.action = &"wait"
	wait.params = {"minutes": maxi(minutes, 0)}
	sequence.steps.append(wait)
	var goal := BustleGoalDef.new()
	goal.id = &"tend"
	goal.band = BustleBands.PERSONAL
	goal.tags = [&"tend", &"work"]
	goal.fail_cooldown_minutes = maxi(minutes, 0)
	goal.considerations.append(consideration)
	goal.sequence = sequence
	return goal
