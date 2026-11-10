# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCrimeWatch
extends RefCounted

## What becomes of each theft: who perceived it, who it's reported to, and the deed it leaves when
## nobody did. Every [signal BustleCrime.theft] becomes a record, and every record is either
## witnessed or a deed (an open trace that its owner finds later, and that the stolen goods
## themselves point to). Each witness, and an owner who finds a deed, remembers it and then decides
## what to do about it: one of [constant BustleWitnessJudge.OUTCOMES] ([member should_report]).
## [br][br]
## There are no made-up witnesses: an agent witnesses a theft only when [member perceives] says it
## perceived it. By default that's every other agent in the place who isn't incapacitated (the
## health port). The thief's own judgement ([member BustleCrime.is_observed]) can be wrong when the
## host gives it one, for example an onlooker the thief didn't notice, so a theft can have
## witnesses. With both defaults, a thief only steals where nobody can perceive it, so every theft
## is a deed.
## [br][br]
## Reports go to a role ([member authority_role]), never to a named agent: the host decides who
## holds it (the roles port) and what follows. Reporting, telling the victim and gossiping are
## errands: the word counts only when the agent reaches whoever it's for, face to face
## ([method deliver], run by the [code]deliver[/code] goal in the guarded band). Until then the
## errand can wait (nobody holds the role), pause ([member can_travel]), be forgotten (its
## memory fades) or be dropped under [method intimidate]. Whoever hears it second-hand learns of
## the theft and decides in turn. [member instant] delivers at once instead, for developers and
## tests only. A confrontation is words, never a fight or an intent to harm. Nothing here
## punishes, fines or harms anyone.
## @experimental

## [param witness] perceived [param thief] taking [param item]. [param record]: see [method record].
signal witnessed(witness: StringName, thief: StringName, item: StringName, record: Dictionary)
## [param reporter] reported a theft to [param role]. [param report]: the record as the reporter
## knows it, plus [code]reporter[/code], [code]role[/code], [code]authority[/code] (the role's
## holder it reached, maybe empty only when [member instant]), [code]source[/code] (one of
## [constant SOURCES]) and [code]reported_at[/code]. The thief is empty when the reporter doesn't
## know who it was.
signal crime_reported(reporter: StringName, role: StringName, report: Dictionary)
## [param finder], the owner, found [param item] gone: a deed came to light.
signal deed_found(finder: StringName, item: StringName, record: Dictionary)
## [param agent] decided [param outcome] (one of [constant BustleWitnessJudge.OUTCOMES]) about
## a record it knows of.
signal decided(agent: StringName, outcome: StringName, record: Dictionary)
## [param witness] accused [param thief] to its face. Words only.
signal confronted(witness: StringName, thief: StringName, record: Dictionary)
## [param witness] told [param owner_id] what it saw.
signal victim_told(witness: StringName, owner_id: StringName, record: Dictionary)
## [param teller] told [param listener] about the theft.
signal gossiped(teller: StringName, listener: StringName, record: Dictionary)
## [param agent] gave up [param errand] (see [method errands_of]): [code]forgot[/code] or
## [code]intimidated[/code]. It still knows of the theft.
signal errand_dropped(agent: StringName, errand: Dictionary, reason: StringName)

## The default role reports go to.
const AUTHORITY := &"authority"
## The project setting a developer or a test turns [member instant] on with (default off). It
## isn't a game option.
const INSTANT_SETTING := "bustle/simulation/instant_crime_reports"
## The brain input that's 1 while the agent has an errand it can go on.
const INPUT := &"fact.errand"
## The reporter saw it.
const EYEWITNESS := &"eyewitness"
## The reporter heard it from someone (the victim it was told to, or gossip).
const SECONDHAND := &"secondhand"
## The reporter is the owner who found it gone, not knowing the thief.
const OWNER_DEED := &"owner_deed"
## Where a report's knowledge came from.
const SOURCES: Array[StringName] = [EYEWITNESS, SECONDHAND, OWNER_DEED]
const _ERRANDS: Array[StringName] = [&"report", &"tell_victim", &"gossip"]

## The crime whose thefts this follows.
var crime: BustleCrime
## The role reports go to.
var authority_role: StringName = AUTHORITY
## (agent, thief, place) → true when [code]agent[/code] perceived [code]thief[/code] stealing at
## [code]place[/code]. Empty: any agent in that place who isn't incapacitated.
var perceives: Callable = Callable()
## (id) → that agent's [BustleMemory], or null. Witnesses note the thief and the item there; an
## owner who finds a deed notes the item where it was taken.
var memory_of: Callable = Callable()
## The default decision.
var judge: BustleWitnessJudge
## (agent, case) → one of [constant BustleWitnessJudge.OUTCOMES]. Empty: [member judge]. The case
## is [code]{record, thief, owner_id, place, can_confront, gossip_to}[/code]; a thief the agent
## doesn't know is empty. Anything else means silent.
var should_report: Callable = Callable()
## (agent, other) → true when [code]agent[/code] can reach [code]other[/code] now. Empty: both are
## agents in the same area.
var can_reach: Callable = Callable()
## (agent, record) → who [code]agent[/code] would gossip to, or empty (then it can't).
## Empty: nobody.
var gossip_to: Callable = Callable()
## True: reports, telling the victim and gossip are delivered the moment they're decided, without
## travel. For developers and tests; off unless [constant INSTANT_SETTING] is on.
var instant: bool = bool(ProjectSettings.get_setting(INSTANT_SETTING, false))
## (agent, now) → false while the agent can't go on its errands (night, fear: the host's call).
## Empty: it always can.
var can_travel: Callable = Callable()
## (id) → where that agent or person is now (a [Vector3]), or null. Empty: the world port's
## position of its area.
var where: Callable = Callable()
## The movement gear an errand asks for ([code]gear[/code] in the action output).
var travel_gear: StringName = &"hurry"

var _records: Dictionary[int, Dictionary] = {}
var _errands: Array[Dictionary] = []
var _next_id: int = 1


func _init(p_crime: BustleCrime = null) -> void:
	crime = p_crime if p_crime != null else BustleCrime.new()
	crime.theft.connect(_on_theft)
	judge = BustleWitnessJudge.new(crime.society)


## Record [param id] (a copy): [code]{id, thief, owner_id, item, place, at, witnesses, known_by,
## decisions, reporters, deed, found_at}[/code]. [code]deed[/code] is true when nobody witnessed
## it; [code]decisions[/code] is agent → outcome; [code]found_at[/code] is the minute its owner
## found it, or -1. Empty when unknown.
## @experimental
func record(id: int) -> Dictionary:
	return _records[id].duplicate(true) if _records.has(id) else {}


## Every record, by id.
## @experimental
func records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _sorted_ids():
		out.append(record(id))
	return out


## The deeds nobody has found yet, by id: the traces the host's law can follow.
## @experimental
func open_deeds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _sorted_ids():
		if _records[id]["deed"] and int(_records[id]["found_at"]) < 0:
			out.append(record(id))
	return out


## The ids of the records [param agent] knows about (witnessed, or found its own loss), by id.
## @experimental
func known_by(agent: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in _sorted_ids():
		if (_records[id]["known_by"] as Array).has(String(agent)):
			out.append(id)
	return out


## What [param agent] can tell when questioned at minute [param now], by record id:
## [code]{id, item, owner_id, place, at, thief, outcome}[/code]. The thief is named only when the
## agent witnessed it and still remembers the thief ([member memory_of]; without a memory, it
## does). Silent witnesses can be questioned too.
## @experimental
func question(agent: StringName, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found: Variant = memory_of.call(agent) if memory_of.is_valid() else null
	for id: int in known_by(agent):
		var row := _records[id]
		var thief := String(row["thief"])
		if not (row["witnesses"] as Array).has(String(agent)) or (found is BustleMemory
				and (found as BustleMemory).recall(BustleMemory.PERSON, StringName(thief), now).is_empty()):
			thief = ""
		out.append({"id": id, "item": row["item"], "owner_id": row["owner_id"], "place": row["place"],
			"at": row["at"], "thief": thief, "outcome": (row["decisions"] as Dictionary).get(String(agent), "")})
	return out


## The stolen goods [param agent] still owns, as records by id: evidence the host can find on it.
## @experimental
func stolen_goods_of(agent: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _sorted_ids():
		var row := _records[id]
		if StringName(row["thief"]) == agent and crime.society.ports.property.owner_of(StringName(row["item"])) == agent:
			out.append(record(id))
	return out


## [param owner_id], at [param place] at minute [param now], finds what was stolen from it there
## and nobody saw go: each such deed is found, the owner knows of it and remembers the item there,
## [signal deed_found] is emitted, and the owner decides what to do (not knowing the thief).
## Returns the record ids found.
## @experimental
func notice_losses(owner_id: StringName, place: StringName, now: int) -> Array[int]:
	var found: Array[int] = []
	for id: int in _sorted_ids():
		var row := _records[id]
		if not row["deed"] or int(row["found_at"]) >= 0 or StringName(row["owner_id"]) != owner_id \
				or StringName(row["place"]) != place:
			continue
		row["found_at"] = now
		_learn(row, owner_id)
		_note(owner_id, BustleMemory.ITEM, StringName(row["item"]), place, now)
		found.append(id)
		deed_found.emit(owner_id, StringName(row["item"]), record(id))
		_decide(row, owner_id, false, OWNER_DEED, now)
	return found


## [param agent]'s errands, oldest first: [code]{agent, kind, record, to, source, knows_thief,
## since, target}[/code]. [code]kind[/code] is report, tell_victim or gossip; [code]target[/code] is
## who it must reach now (for a report, the role's holder, empty while nobody holds it).
## @experimental
func errands_of(agent: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for errand: Dictionary in _errands:
		if StringName(errand["agent"]) == agent:
			var copy := errand.duplicate(true)
			copy["target"] = String(_target(errand))
			out.append(copy)
	return out


## Sets [constant INPUT] to 1 while [param agent] has an errand with someone to reach and can go
## on it at minute [param now]; erases it otherwise.
## @experimental
func fill_inputs(agent: StringName, inputs: Dictionary[StringName, float], now: int) -> void:
	inputs.erase(INPUT)
	if can_travel.is_valid() and not bool(can_travel.call(agent, now)):
		return
	for errand: Dictionary in errands_of(agent):
		if errand["target"] != "":
			inputs[INPUT] = 1.0
			return


## [param agent] goes on with its oldest errand that has someone to reach, at minute [param now].
## Errands still waiting (nobody holds the role) are skipped, so they never hold up the rest; any
## errand whose item the agent no longer remembers is dropped on the way, waiting or not.
## Returns [code]{state, target}[/code]: [code]delivered[/code] when it reached the target face
## to face (the event is emitted then), [code]travelling[/code] when it still has to get there,
## [code]forgot[/code] when it dropped a faded errand (nothing emitted), [code]waiting[/code] when
## every errand left is waiting, or [code]none[/code].
## @experimental
func deliver(agent: StringName, now: int) -> Dictionary:
	var memory: Variant = memory_of.call(agent) if memory_of.is_valid() else null
	var waiting := false
	for errand: Dictionary in _errands.duplicate():
		if StringName(errand["agent"]) != agent:
			continue
		if memory is BustleMemory and (memory as BustleMemory).recall(BustleMemory.ITEM,
				StringName(_records[int(errand["record"])]["item"]), now).is_empty():
			_errands.erase(errand)
			errand_dropped.emit(agent, errand, &"forgot")
			return {"state": &"forgot", "target": &""}
		var target := _target(errand)
		if target == &"":
			waiting = true
			continue
		if not _reaches(agent, target):
			return {"state": &"travelling", "target": target}
		_errands.erase(errand)
		_complete(errand, target, now)
		return {"state": &"delivered", "target": target}
	return {"state": &"waiting" if waiting else &"none", "target": &""}


## Where [param id] is now, for moving towards it ([member where]), or null.
## @experimental
func position_of(id: StringName) -> Variant:
	if where.is_valid():
		return where.call(id)
	var state := crime.society.get_agent(id)
	return crime.society.ports.world.place_position(state.area) if state != null else null


## [param thief] faces down [param witness] at minute [param now]: the witness drops its errands
## about that thief's thefts. It still remembers, and can decide again later
## ([method reconsider]). Nothing here harms anyone. Returns how many errands were dropped.
## @experimental
func intimidate(thief: StringName, witness: StringName, _now: int) -> int:
	var dropped := 0
	for errand: Dictionary in _errands.duplicate():
		if StringName(errand["agent"]) == witness and errand["knows_thief"] \
				and StringName(_records[int(errand["record"])]["thief"]) == thief:
			_errands.erase(errand)
			errand_dropped.emit(witness, errand, &"intimidated")
			dropped += 1
	return dropped


## [param agent] decides again about record [param id] at minute [param now], with the same
## judge and today's inputs (fear, opinions). Only for a record it knows of and has no errand
## about. Returns the outcome, or empty when it can't.
## @experimental
func reconsider(agent: StringName, id: int, now: int) -> StringName:
	if not _records.has(id) or not (_records[id]["known_by"] as Array).has(String(agent)) \
			or _errands.any(func(e: Dictionary) -> bool: return StringName(e["agent"]) == agent and int(e["record"]) == id):
		return &""
	var row := _records[id]
	var saw := (row["witnesses"] as Array).has(String(agent))
	var source := EYEWITNESS if saw else (OWNER_DEED if row["deed"] and StringName(row["owner_id"]) == agent else SECONDHAND)
	return _decide(row, agent, saw, source, now)


## The records as plain data, by id.
## @experimental
func export_state() -> Dictionary:
	return {"next_id": _next_id, "records": records(), "errands": _errands.duplicate(true)}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("next_id") is int or not saved.get("records") is Array:
		return false
	var staged: Dictionary[int, Dictionary] = {}
	for row: Variant in saved["records"]:
		if not _valid_record(row) or staged.has(int(row["id"])) or int(row["id"]) >= int(saved["next_id"]):
			return false
		staged[int(row["id"])] = (row as Dictionary).duplicate(true)
	var errands: Variant = saved.get("errands", [])
	if not errands is Array or not (errands as Array).all(func(e: Variant) -> bool: return _valid_errand(e, staged)):
		return false
	_records = staged
	_next_id = int(saved["next_id"])
	_errands.assign((errands as Array).duplicate(true))
	return true


## The goal that runs errands: [code]deliver[/code] in [constant BustleBands.GUARDED], eligible
## while [constant INPUT] is 1, running the [code]deliver[/code] action ([BustleDeliverAction]).
## Urgent self-care outranks it; orders and duty don't.
## @experimental
static func goal_defs() -> Array[BustleGoalDef]:
	var goal: BustleGoalDef = BustleCrime.goal_defs()[0]
	goal.id = &"deliver"
	goal.considerations[0].input = INPUT
	goal.sequence.steps[0].action = &"deliver"
	return [goal]


func _on_theft(thief: StringName, owner_id: StringName, item: StringName, circumstances: Dictionary) -> void:
	var place := StringName(circumstances.get("place", ""))
	var now := int(circumstances.get("at", 0))
	var witnesses: Array[String] = []
	for agent: StringName in crime.society.agent_ids():
		if agent != thief and _perceived(agent, thief, place):
			witnesses.append(String(agent))
	var row := {"id": _next_id, "thief": String(thief), "owner_id": String(owner_id), "item": String(item),
		"place": String(place), "at": now, "witnesses": witnesses, "known_by": [], "decisions": {}, "reporters": [],
		"deed": witnesses.is_empty(), "found_at": -1}
	_records[_next_id] = row
	_next_id += 1
	for witness: String in witnesses:
		_learn(row, StringName(witness))
		_note(StringName(witness), BustleMemory.PERSON, thief, place, now)
		_note(StringName(witness), BustleMemory.ITEM, item, place, now)
		witnessed.emit(StringName(witness), thief, item, record(int(row["id"])))
		_decide(row, StringName(witness), true, EYEWITNESS, now)


func _perceived(agent: StringName, thief: StringName, place: StringName) -> bool:
	if perceives.is_valid():
		return bool(perceives.call(agent, thief, place))
	var state := crime.society.get_agent(agent)
	return state != null and state.area == place and not crime.society.ports.health.is_incapacitated(agent)


func _learn(row: Dictionary, agent: StringName) -> void:
	if not (row["known_by"] as Array).has(String(agent)):
		(row["known_by"] as Array).append(String(agent))


func _note(agent: StringName, kind: StringName, subject: StringName, place: StringName, now: int) -> void:
	var found: Variant = memory_of.call(agent) if memory_of.is_valid() else null
	if found is BustleMemory:
		(found as BustleMemory).note(kind, subject, place, null, BustleMemory.SAW, now)


func _decide(row: Dictionary, agent: StringName, knows_thief: bool, source: StringName, now: int) -> StringName:
	var thief := StringName(row["thief"]) if knows_thief else &""
	var owner_id := StringName(row["owner_id"])
	var case := {"record": record(int(row["id"])), "thief": String(thief), "owner_id": String(owner_id),
		"place": row["place"], "can_confront": thief != &"" and _reaches(agent, thief),
		"gossip_to": String(gossip_to.call(agent, record(int(row["id"])))) if gossip_to.is_valid() else ""}
	var outcome := BustleWitnessJudge.SILENT
	if should_report.is_valid():
		outcome = StringName(should_report.call(agent, case))
	else:
		judge.authority_role = authority_role
		outcome = StringName(judge.decide(agent, case)["outcome"])
	if not BustleWitnessJudge.OUTCOMES.has(outcome):
		outcome = BustleWitnessJudge.SILENT
	(row["decisions"] as Dictionary)[String(agent)] = String(outcome)
	decided.emit(agent, outcome, record(int(row["id"])))
	if outcome == BustleWitnessJudge.CONFRONT:
		confronted.emit(agent, thief, record(int(row["id"])))
	elif _ERRANDS.has(outcome):
		var to := String(owner_id) if outcome == BustleWitnessJudge.TELL_VICTIM else String(case["gossip_to"])
		var errand := {"agent": String(agent), "kind": String(outcome), "record": int(row["id"]),
			"to": "" if outcome == BustleWitnessJudge.REPORT else to, "source": String(source),
			"knows_thief": knows_thief, "since": now}
		if instant:
			_complete(errand, _target(errand), now)
		else:
			_errands.append(errand)
	return outcome


func _target(errand: Dictionary) -> StringName:
	if errand["kind"] == "report":
		return crime.society.ports.roles.holder_of(authority_role)
	return StringName(errand["to"])


func _complete(errand: Dictionary, target: StringName, now: int) -> void:
	var row := _records[int(errand["record"])]
	var agent := StringName(errand["agent"])
	var knows := bool(errand["knows_thief"])
	match StringName(errand["kind"]):
		BustleWitnessJudge.REPORT:
			_report(row, agent, knows, StringName(errand["source"]), target, now)
		BustleWitnessJudge.TELL_VICTIM:
			victim_told.emit(agent, target, record(int(row["id"])))
			_hear(row, target, knows, now)
		BustleWitnessJudge.GOSSIP:
			gossiped.emit(agent, target, record(int(row["id"])))
			_hear(row, target, knows, now)


# Someone told of a theft learns it (once), remembers the item and decides in turn.
func _hear(row: Dictionary, listener: StringName, knows_thief: bool, now: int) -> void:
	if listener == &"" or (row["known_by"] as Array).has(String(listener)):
		return
	_learn(row, listener)
	_note(listener, BustleMemory.ITEM, StringName(row["item"]), StringName(row["place"]), now)
	_decide(row, listener, knows_thief, SECONDHAND, now)


func _reaches(agent: StringName, other: StringName) -> bool:
	if can_reach.is_valid():
		return bool(can_reach.call(agent, other))
	var a := crime.society.get_agent(agent)
	var b := crime.society.get_agent(other)
	return a != null and b != null and a.area == b.area


func _report(row: Dictionary, reporter: StringName, knows_thief: bool, source: StringName, authority: StringName,
		now: int) -> void:
	(row["reporters"] as Array).append(String(reporter))
	var report := record(int(row["id"]))
	if not knows_thief:
		report["thief"] = ""
	report.erase("known_by")
	report.erase("decisions")
	report.erase("reporters")
	report["reporter"] = String(reporter)
	report["role"] = String(authority_role)
	report["authority"] = String(authority)
	report["source"] = String(source)
	report["reported_at"] = now
	crime_reported.emit(reporter, authority_role, report)


func _sorted_ids() -> Array[int]:
	var ids: Array[int] = _records.keys()
	ids.sort()
	return ids


static func _valid_errand(errand: Variant, records: Dictionary[int, Dictionary]) -> bool:
	return errand is Dictionary and errand.get("agent") is String and errand.get("to") is String \
		and _ERRANDS.has(StringName(str(errand.get("kind")))) and errand.get("kind") is String \
		and SOURCES.has(StringName(str(errand.get("source")))) and errand.get("source") is String \
		and errand.get("record") is int and records.has(int(errand["record"])) \
		and errand.get("knows_thief") is bool and errand.get("since") is int


static func _valid_record(row: Variant) -> bool:
	if not row is Dictionary:
		return false
	for field: String in ["thief", "owner_id", "item", "place"]:
		if not row.get(field) is String:
			return false
	for field: String in ["witnesses", "known_by", "reporters"]:
		if not row.get(field) is Array:
			return false
		for entry: Variant in row[field]:
			if not entry is String:
				return false
	if not row.get("decisions") is Dictionary:
		return false
	for agent: Variant in row["decisions"]:
		if not agent is String or not BustleWitnessJudge.OUTCOMES.has(StringName(str(row["decisions"][agent]))) \
				or not row["decisions"][agent] is String:
			return false
	return row.get("id") is int and int(row["id"]) > 0 and row.get("at") is int and row.get("found_at") is int \
		and row.get("deed") is bool and bool(row["deed"]) == (row["witnesses"] as Array).is_empty()
