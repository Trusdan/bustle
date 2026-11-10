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
## holds it (the roles port) and what follows. A report is made at once. Confronting, telling the
## victim and gossiping are only events: a confrontation is words, never a fight or an intent to
## harm. Nothing here punishes, fines or harms anyone.
## @experimental

## [param witness] perceived [param thief] taking [param item]. [param record]: see [method record].
signal witnessed(witness: StringName, thief: StringName, item: StringName, record: Dictionary)
## [param reporter] reported a theft to [param role]. [param report]: the record as the reporter
## knows it, plus [code]reporter[/code], [code]role[/code], [code]authority[/code] (the role's
## holder then, maybe empty) and [code]reported_at[/code]. The thief is empty when the reporter
## doesn't know who it was.
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

## The default role reports go to.
const AUTHORITY := &"authority"

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

var _records: Dictionary[int, Dictionary] = {}
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
		_decide(row, owner_id, false, now)
	return found


## The records as plain data, by id.
## @experimental
func export_state() -> Dictionary:
	return {"next_id": _next_id, "records": records()}


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
	_records = staged
	_next_id = int(saved["next_id"])
	return true


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
		_decide(row, StringName(witness), true, now)


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


func _decide(row: Dictionary, agent: StringName, knows_thief: bool, now: int) -> void:
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
	match outcome:
		BustleWitnessJudge.REPORT:
			_report(row, agent, knows_thief, now)
		BustleWitnessJudge.TELL_VICTIM:
			victim_told.emit(agent, owner_id, record(int(row["id"])))
		BustleWitnessJudge.CONFRONT:
			confronted.emit(agent, thief, record(int(row["id"])))
		BustleWitnessJudge.GOSSIP:
			gossiped.emit(agent, StringName(case["gossip_to"]), record(int(row["id"])))


func _reaches(agent: StringName, other: StringName) -> bool:
	if can_reach.is_valid():
		return bool(can_reach.call(agent, other))
	var a := crime.society.get_agent(agent)
	var b := crime.society.get_agent(other)
	return a != null and b != null and a.area == b.area


func _report(row: Dictionary, reporter: StringName, knows_thief: bool, now: int) -> void:
	(row["reporters"] as Array).append(String(reporter))
	var report := record(int(row["id"]))
	if not knows_thief:
		report["thief"] = ""
	report.erase("known_by")
	report.erase("decisions")
	report.erase("reporters")
	report["reporter"] = String(reporter)
	report["role"] = String(authority_role)
	report["authority"] = String(crime.society.ports.roles.holder_of(authority_role))
	report["reported_at"] = now
	crime_reported.emit(reporter, authority_role, report)


func _sorted_ids() -> Array[int]:
	var ids: Array[int] = _records.keys()
	ids.sort()
	return ids


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
