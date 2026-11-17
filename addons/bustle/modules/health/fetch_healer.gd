# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFetchHealer
extends RefCounted

## Fetching a healer, opt-in: when an agent is downed or urgently needs care and no healer is within
## reach, a bystander goes to the nearest healer and tells it, by the same movement and arrival
## rule as fetching help in a fight ([method BustleFetchHelpAction.approach]). The healer is then
## summoned to the patient, and the tend job does the rest. Bustle names who and where; the host
## moves the bodies and gives the care.
## [br][br]
## [b]Patients:[/b] [method urgency]: a downed agent ([method BustleHealthBehaviour.is_downed]), or one
## whose [method BustleHealthPort.needs_care] is at or above [member urgent_at].
## [br][br]
## [b]Healers:[/b] the holders of [member care_roles] ([method BustleRolesPort.holder_of]) and
## whoever [member healers] names (for example the agents with the tend goal), never a downed one.
## Who may tend stays the host's call.
## [br][br]
## [b]Errands:[/b] [method notice] (or [method look], over [member nearby]) starts one when a bystander
## who isn't downed, isn't busy ([member is_busy]) and has no errand sees a patient who has none,
## and no healer is within [member reach] of the patient. It goes to the nearest healer not already
## summoned to another patient; a healer keeps the first summons it gets. On arrival
## ([method arrive]) the healer is summoned: [method summoned_to] names the patient, its
## [constant SUMMONED] input is set, and [method nearby_with_summons] adds the patient to the tend
## job's [member BustleTendJob.nearby]. An errand ends when the patient recovers or dies
## ([member is_dead]), when the bystander is downed, when the healer can't be fetched, or when it
## was summoned to another patient first ([code]healer_busy[/code]); a summons
## ends when the patient is tended ([method tended]), recovers or dies.
## [br][br]
## Errands and summons are saved ([method export_state]). Nothing is random.
## @experimental: Added after 1.0 for the health module. The urgency line, weights, reach and band are PROPOSED defaults, not tuning.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")

## The save format's version ([method export_state]).
const STATE_VERSION := 1
## The bystander's input: its patient's urgency, 0 to 1, set only while it is on an errand.
const INPUT := &"fact.fetch_healer"
## The healer's input: its summoned patient's urgency, 0 to 1, set only while it is summoned.
const SUMMONED := &"fact.summoned"
## The action the goal runs.
const ACTION := &"fetch_healer"

## [param bystander] set off to fetch [param healer] for [param patient].
signal errand_started(bystander: StringName, patient: StringName, healer: StringName)
## [param bystander]'s errand for [param patient] ended, for [param reason]: [code]arrived[/code],
## [code]recovered[/code], [code]dead[/code], [code]bystander_downed[/code], [code]no_healer[/code],
## [code]healer_busy[/code] (the healer was summoned to another patient meanwhile) or
## [code]dropped[/code].
signal errand_ended(bystander: StringName, patient: StringName, reason: StringName)
## [param healer] was told about [param patient].
signal summoned(healer: StringName, patient: StringName)

## The health behaviour it reads the ports through ([member BustleHealthBehaviour.ports]).
var health: BustleHealthBehaviour
## The roles whose holders give care. Empty: only [member healers].
var care_roles: Array[StringName] = []
## [code]func() -> Array[StringName][/code]: other agents who may tend (for example those with the
## tend goal). Empty: only [member care_roles].
var healers: Callable = Callable()
## The need for care, 0 to 1, from which a patient who is up needs a healer fetched. PROPOSED: 0.8.
var urgent_at: float = 0.8
## How urgent a downed patient is, 0 to 1. PROPOSED: 1.
var downed_weight: float = 1.0
## How urgent a patient is per unit of need for care, 0 to 1. PROPOSED: 1.
var care_weight: float = 1.0
## Metres: a healer this close to the patient needs no fetching. PROPOSED: 15, as
## [member BustleConflictConfig.help_radius].
var reach: float = 15.0
## [code]func(id: StringName) -> Variant[/code]: where that agent is now (a [Vector3]), or null.
## Empty: the world port's position of the agent's area.
var where: Callable = Callable()
## [code]func(bystander: StringName) -> Array[StringName][/code]: who [param bystander] can see now,
## for [method look]. Empty: nobody.
var nearby: Callable = Callable()
## [code]func(id: StringName) -> bool[/code]: true while that agent is busy with an order (or a
## lock). Empty: never.
var is_busy: Callable = Callable()
## [code]func(id: StringName) -> bool[/code]: true when that agent has died (for example
## [method BustleLifeStages.is_dead]). Empty: never; call [method drop] instead.
var is_dead: Callable = Callable()

# bystander → {patient, healer, since}
var _errands: Dictionary[StringName, Dictionary] = {}
# healer → patient
var _summons: Dictionary[StringName, StringName] = {}


func _init(p_health: BustleHealthBehaviour = null, p_care_roles: Array[StringName] = []) -> void:
	health = p_health
	care_roles = p_care_roles.duplicate()


## How urgently [param patient] needs a healer, 0 to 1: [member downed_weight] when downed, else
## [member care_weight] × its need for care when that is at or above [member urgent_at]; 0
## otherwise, with no port, and for a dead patient.
func urgency(patient: StringName) -> float:
	if patient == &"" or health == null or health.ports == null or _dead(patient):
		return 0.0
	if health.is_downed(patient):
		return _unit(downed_weight, "downed_weight")
	var need := health.ports.health.needs_care(patient)
	if not is_finite(need) or need <= 0.0 or need < _unit(urgent_at, "urgent_at"):
		return 0.0
	return clampf(_unit(care_weight, "care_weight") * clampf(need, 0.0, 1.0), 0.0, 1.0)


## The agents who may tend [param patient] now: the holders of [member care_roles] and those
## [member healers] names, not the patient and not downed, sorted by id.
func healers_for(patient: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if health == null or health.ports == null:
		return out
	var found: Array[StringName] = []
	for role: StringName in care_roles:
		if role != &"":
			found.append(health.ports.roles.holder_of(role))
	if healers.is_valid():
		var named: Variant = healers.call()
		if named is Array:
			for id: Variant in named:
				if id is StringName or id is String:
					found.append(StringName(id))
		else:
			_Warn.warn("BustleFetchHealer.healers.wrong_type", "BustleFetchHealer.healers: the hook returned %s, not an Array; using none" % type_string(typeof(named)))
	for id: StringName in found:
		if id != &"" and id != patient and not out.has(id) and not health.is_downed(id) and not _dead(id):
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## True when a healer is within [member reach] of [param patient] (by [method position_of]).
func healer_within_reach(patient: StringName) -> bool:
	var here: Variant = position_of(patient)
	if not here is Vector3:
		return false
	for healer: StringName in healers_for(patient):
		var there: Variant = position_of(healer)
		if there is Vector3 and (here as Vector3).distance_to(there) <= maxf(_finite(reach, "reach"), 0.0):
			return true
	return false


## The healer nearest to [param patient] (ties in id order), not [param bystander] and not already
## summoned to another patient, or empty. A healer with no position isn't chosen.
func nearest_healer(patient: StringName, bystander: StringName = &"") -> StringName:
	var here: Variant = position_of(patient)
	if not here is Vector3:
		return &""
	var best := &""
	var best_distance := INF
	for healer: StringName in healers_for(patient):
		var there: Variant = position_of(healer)
		if healer == bystander or not there is Vector3 or not [&"", patient].has(summoned_to(healer)):
			continue
		var distance := (here as Vector3).distance_to(there)
		if distance < best_distance:
			best = healer
			best_distance = distance
	return best


## [param bystander] sees [param patient] at minute [param now]. It sets off to fetch the nearest
## healer when the patient needs one ([method urgency]), no errand or summons is under way for it,
## and no healer is within [member reach]; and when the bystander isn't the patient or a healer,
## isn't downed, isn't busy and has no errand. Returns the healer, or empty when it doesn't go.
func notice(bystander: StringName, patient: StringName, now: int) -> StringName:
	if patient == &"" or bystander == patient or not _can_go(bystander):
		return &""
	return _try(bystander, patient, now)


# notice() once the bystander is known to be free to go.
func _try(bystander: StringName, patient: StringName, now: int) -> StringName:
	if urgency(patient) <= 0.0 or _summons.values().has(patient) or not errand_for(patient).is_empty():
		return &""
	if healers_for(patient).has(bystander) or healer_within_reach(patient):
		return &""
	var healer := nearest_healer(patient, bystander)
	if healer == &"":
		return &""
	_errands[bystander] = {"patient": patient, "healer": healer, "since": now}
	errand_started.emit(bystander, patient, healer)
	return healer


## [method notice] for each agent [member nearby] says [param bystander] can see (in id order),
## until it sets off. Returns the healer, or empty.
func look(bystander: StringName, now: int) -> StringName:
	if not nearby.is_valid() or not _can_go(bystander):
		return &""
	var seen: Variant = nearby.call(bystander)
	if not seen is Array:
		_Warn.warn("BustleFetchHealer.nearby.wrong_type", "BustleFetchHealer.nearby: the hook returned %s, not an Array; seeing nobody" % type_string(typeof(seen)))
		return &""
	var ids: Array[StringName] = []
	for id: Variant in seen:
		if id is StringName or id is String:
			ids.append(StringName(id))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for patient: StringName in ids:
		if patient == &"" or patient == bystander:
			continue
		var healer := _try(bystander, patient, now)
		if healer != &"":
			return healer
	return &""


## [param bystander]'s errand, [code]{patient, healer, since}[/code] (a copy), or empty. Ends it
## first when it should end (see the class description).
func errand_of(bystander: StringName) -> Dictionary:
	_review(bystander)
	return _errands.get(bystander, {}).duplicate()


## The errand under way for [param patient] ([code]{bystander, healer, since}[/code]), or empty.
func errand_for(patient: StringName) -> Dictionary:
	for bystander: StringName in _errands:
		if StringName(_errands[bystander]["patient"]) == patient:
			var out := _errands[bystander].duplicate()
			out.erase("patient")
			out["bystander"] = bystander
			return out
	return {}


## [param bystander] reached its healer at minute [param _now]: the healer is summoned to the
## patient and the errand ends ([code]arrived[/code]). A healer keeps the first summons it gets:
## when it was summoned to another patient meanwhile, the errand ends ([code]healer_busy[/code])
## and the healer's summons is left as it was. False when it has no errand, or the healer is busy.
func arrive(bystander: StringName, _now: int) -> bool:
	var errand := errand_of(bystander)
	if errand.is_empty():
		return false
	var healer := StringName(errand["healer"])
	var patient := StringName(errand["patient"])
	if not [&"", patient].has(summoned_to(healer)):
		_end(bystander, &"healer_busy")
		return false
	_end(bystander, &"arrived")
	_summons[healer] = patient
	summoned.emit(healer, patient)
	return true


## The patient [param healer] was summoned to, or empty. Ends the summons first when the patient
## recovered or died.
func summoned_to(healer: StringName) -> StringName:
	var patient: StringName = _summons.get(healer, &"")
	if patient != &"" and urgency(patient) <= 0.0:
		_summons.erase(healer)
		return &""
	return patient


## [param healer] tended [param patient]: a summons to that patient ends when [param done]. Connect
## it to [signal BustleTendJob.tended].
func tended(healer: StringName, patient: StringName, done: bool) -> void:
	if done and _summons.get(healer, &"") == patient:
		_summons.erase(healer)


## Forgets [param patient] (it died, or left the population): its errand ends
## ([code]dropped[/code]) and any summons to it.
func drop(patient: StringName) -> void:
	for bystander: StringName in _errands.keys():
		if StringName(_errands[bystander]["patient"]) == patient or bystander == patient:
			_end(bystander, &"dropped")
	for healer: StringName in _summons.keys():
		if _summons[healer] == patient or healer == patient:
			_summons.erase(healer)


## Sets [param id]'s [constant INPUT] while it is on an errand, and its [constant SUMMONED] while
## it is summoned, each to the patient's [method urgency]; erases them otherwise.
func fill_inputs(id: StringName, inputs: Dictionary[StringName, float]) -> void:
	inputs.erase(INPUT)
	inputs.erase(SUMMONED)
	var errand := errand_of(id)
	if not errand.is_empty():
		inputs[INPUT] = urgency(StringName(errand["patient"]))
	var patient := summoned_to(id)
	if patient != &"":
		inputs[SUMMONED] = urgency(patient)


## A [member BustleTendJob.nearby] that adds a healer's summoned patient to what [param base]
## answers, so the unchanged tend job can choose it.
func nearby_with_summons(base: Callable) -> Callable:
	return func(healer: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		if base.is_valid():
			var found: Variant = base.call(healer)
			if found is Array:
				out.assign(found)
		var patient := summoned_to(healer)
		if patient != &"" and not out.has(patient):
			out.append(patient)
		return out


## Where [param id] is now, from [member where], else the world port's position of its area; null
## when [member where] doesn't say.
func position_of(id: StringName) -> Variant:
	if where.is_valid():
		var found: Variant = where.call(id)
		if found == null:
			return null
		if found is Vector3 and (found as Vector3).is_finite():
			return found
		_Warn.warn("BustleFetchHealer.where.wrong_type", "BustleFetchHealer.where: the hook returned %s, not a Vector3 or null; using no position" % type_string(typeof(found)))
		return null
	if health == null or health.ports == null:
		return null
	var world := health.ports.world
	return world.place_position(world.area_of(id))


## The fetch-a-healer goal: band [param band] ([constant BustleBands.URGENT] by default), tags
## [code]fetch_healer[/code] and [code]travel[/code] (so the downed gate blocks it too), scored by
## [constant INPUT] in a straight line, running [constant ACTION].
static func goal_def(band: int = BustleBands.URGENT) -> BustleGoalDef:
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
	var goal := BustleGoalDef.new()
	goal.id = &"fetch_healer"
	goal.band = band
	goal.tags = [&"fetch_healer", &"travel"]
	goal.considerations.append(consideration)
	goal.sequence = sequence
	return goal


## Its errands and summons, sorted by id: [code]{version, errands: {bystander: {patient, healer,
## since}}, summons: {healer: patient}}[/code].
func export_state() -> Dictionary:
	var errands := {}
	var ids: Array[StringName] = _errands.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for bystander: StringName in ids:
		var row: Dictionary = _errands[bystander]
		errands[String(bystander)] = {"patient": String(row["patient"]), "healer": String(row["healer"]), "since": int(row["since"])}
	var summons := {}
	var healers_ids: Array[StringName] = _summons.keys()
	healers_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for healer: StringName in healers_ids:
		summons[String(healer)] = String(_summons[healer])
	return {"version": STATE_VERSION, "errands": errands, "summons": summons}


static func _save_format() -> Dictionary:
	return {"key": "version", "current": STATE_VERSION, "steps": {}}


## Restores [method export_state]. Minutes may be whole floats, as in a save read back from JSON.
## False, changing nothing, for another version or a malformed entry.
func import_state(saved: Dictionary) -> bool:
	if not BustleSaveFormat._read(&"BustleFetchHealer", saved, _save_format())["ok"]:
		return false
	if not saved.get("errands") is Dictionary or not saved.get("summons") is Dictionary:
		return false
	var errands: Dictionary[StringName, Dictionary] = {}
	for key: Variant in saved["errands"]:
		var row: Variant = saved["errands"][key]
		if not key is String or String(key).is_empty() or not row is Dictionary:
			return false
		var since: Variant = (row as Dictionary).get("since")
		if not (row as Dictionary).get("patient") is String or not (row as Dictionary).get("healer") is String \
				or String(row["patient"]).is_empty() or String(row["healer"]).is_empty() \
				or not (since is int or (since is float and is_finite(since) and since == floorf(since))):
			return false
		errands[StringName(key)] = {"patient": StringName(row["patient"]), "healer": StringName(row["healer"]), "since": int(since)}
	var summons: Dictionary[StringName, StringName] = {}
	for key: Variant in saved["summons"]:
		var patient: Variant = saved["summons"][key]
		if not key is String or String(key).is_empty() or not patient is String or String(patient).is_empty():
			return false
		summons[StringName(key)] = StringName(patient)
	_errands = errands
	_summons = summons
	return true


# Ends bystander's errand when the patient recovered or died, the bystander is downed, or the
# healer can no longer be fetched.
func _review(bystander: StringName) -> void:
	if not _errands.has(bystander):
		return
	var patient := StringName(_errands[bystander]["patient"])
	var healer := StringName(_errands[bystander]["healer"])
	if _dead(patient):
		_end(bystander, &"dead")
	elif urgency(patient) <= 0.0:
		_end(bystander, &"recovered")
	elif health.is_downed(bystander):
		_end(bystander, &"bystander_downed")
	elif not healers_for(patient).has(healer):
		_end(bystander, &"no_healer")


func _end(bystander: StringName, reason: StringName) -> void:
	var patient := StringName(_errands[bystander]["patient"])
	_errands.erase(bystander)
	errand_ended.emit(bystander, patient, reason)


# True when bystander could set off now: a known agent, with a port, not on an errand, downed,
# dead or busy.
func _can_go(bystander: StringName) -> bool:
	return bystander != &"" and health != null and health.ports != null and not _errands.has(bystander) \
		and not health.is_downed(bystander) and not _dead(bystander) and not _busy(bystander)


func _dead(id: StringName) -> bool:
	return is_dead.is_valid() and _Warn.as_bool(is_dead.call(id), false, "BustleFetchHealer.is_dead")


func _busy(id: StringName) -> bool:
	return is_busy.is_valid() and _Warn.as_bool(is_busy.call(id), false, "BustleFetchHealer.is_busy")


# A 0..1 setting: clamped, or 1 (with one warning) when it isn't a number.
func _unit(value: float, name: String) -> float:
	if is_finite(value):
		return clampf(value, 0.0, 1.0)
	_Warn.warn("BustleFetchHealer." + name, "BustleFetchHealer: %s isn't a number; using 1" % name)
	return 1.0


# A number setting: as it is, or 15 (with one warning) when it isn't finite.
func _finite(value: float, name: String) -> float:
	if is_finite(value):
		return value
	_Warn.warn("BustleFetchHealer." + name, "BustleFetchHealer: %s isn't a number; using 15" % name)
	return 15.0
