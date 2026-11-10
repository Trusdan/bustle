# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCrimeWatch
extends RefCounted

## What becomes of each theft: who perceived it, who it's reported to, and the deed it leaves when
## nobody did. Every [signal BustleCrime.theft] becomes a record, and every record is either
## witnessed (each witness remembers it and reports it) or a deed (an open trace that its owner
## finds later, and that the stolen goods themselves point to).
## [br][br]
## There are no made-up witnesses: an agent witnesses a theft only when [member perceives] says it
## perceived it. By default that's every other agent in the place who isn't incapacitated (the
## health port). The thief's own judgement ([member BustleCrime.is_observed]) can be wrong when the
## host gives it one, for example an onlooker the thief didn't notice, so a theft can have
## witnesses. With both defaults, a thief only steals where nobody can perceive it, so every theft
## is a deed.
## [br][br]
## Reports go to a role ([member authority_role]), never to a named agent: the host decides who
## holds it (the roles port) and what follows. Nothing here punishes, fines or harms anyone.
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

## The default role reports go to.
const AUTHORITY := &"authority"

## The crime whose thefts this follows.
var crime: BustleCrime
## The role reports go to.
var authority_role: StringName = AUTHORITY
## (agent, thief, place) → true when [code]agent[/code] perceived [code]thief[/code] stealing at
## [code]place[/code]. Empty: any agent in that place who isn't incapacitated.
var perceives: Callable = Callable()
## (id) → that agent's [BustleMemory], or null. Witnesses note the thief and the item there.
var memory_of: Callable = Callable()

var _records: Dictionary[int, Dictionary] = {}
var _next_id: int = 1


func _init(p_crime: BustleCrime = null) -> void:
	crime = p_crime if p_crime != null else BustleCrime.new()
	crime.theft.connect(_on_theft)


## Record [param id] (a copy): [code]{id, thief, owner_id, item, place, at, witnesses, known_by,
## reporters, deed, found_at}[/code]. [code]deed[/code] is true when nobody witnessed it;
## [code]found_at[/code] is the minute its owner found it, or -1. Empty when unknown.
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
## and nobody saw go: each such deed is found, the owner knows of it, [signal deed_found] is
## emitted and the owner reports it (not knowing the thief). Returns the record ids found.
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
		found.append(id)
		deed_found.emit(owner_id, StringName(row["item"]), record(id))
		_report(row, owner_id, false, now)
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
		"place": String(place), "at": now, "witnesses": witnesses, "known_by": [], "reporters": [],
		"deed": witnesses.is_empty(), "found_at": -1}
	_records[_next_id] = row
	_next_id += 1
	for witness: String in witnesses:
		_learn(row, StringName(witness))
		_remember(StringName(witness), thief, item, place, now)
		witnessed.emit(StringName(witness), thief, item, record(int(row["id"])))
		_report(row, StringName(witness), true, now)


func _perceived(agent: StringName, thief: StringName, place: StringName) -> bool:
	if perceives.is_valid():
		return bool(perceives.call(agent, thief, place))
	var state := crime.society.get_agent(agent)
	return state != null and state.area == place and not crime.society.ports.health.is_incapacitated(agent)


func _learn(row: Dictionary, agent: StringName) -> void:
	if not (row["known_by"] as Array).has(String(agent)):
		(row["known_by"] as Array).append(String(agent))


func _remember(witness: StringName, thief: StringName, item: StringName, place: StringName, now: int) -> void:
	var found: Variant = memory_of.call(witness) if memory_of.is_valid() else null
	if found is BustleMemory:
		(found as BustleMemory).note(BustleMemory.PERSON, thief, place, null, BustleMemory.SAW, now)
		(found as BustleMemory).note(BustleMemory.ITEM, item, place, null, BustleMemory.SAW, now)


func _report(row: Dictionary, reporter: StringName, knows_thief: bool, now: int) -> void:
	(row["reporters"] as Array).append(String(reporter))
	var report := record(int(row["id"]))
	if not knows_thief:
		report["thief"] = ""
	report.erase("known_by")
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
	return row.get("id") is int and int(row["id"]) > 0 and row.get("at") is int and row.get("found_at") is int \
		and row.get("deed") is bool and bool(row["deed"]) == (row["witnesses"] as Array).is_empty()
