# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSchedule
extends RefCounted

## One agent's routine in play: which block of its [BustleScheduleDef] is current, the scorer's
## [code]schedule.*[/code] inputs, and attendance. A block is on time when the agent turns up within
## its lateness tolerance, late when it turns up after that, and missed when it never turns up
## before the block ends. Time is whole game minutes from the clock port; the season is the clock
## port's [method BustleClockPort.season] (a block carried over from the night before is read in
## the current season, and [method report] reads a past day in the season it is given, so pass
## that day's season across a change of season).
## [br][br]
## [b]Wages.[/b] A block with a [member BustleScheduleBlock.wage] pays it once, after it ends, if
## it was attended (on time or late): [method settle] pays every such block through a
## [BustleTradePort]. Its payer is the block's own, else the [member employer] when it was
## attended, fixed then and saved. A missed block pays nothing; a payment the payer can't make stays
## owed (kept past the attendance window) and is tried again on every settle until paid.
## @experimental

## Attended within the tolerance.
const ON_TIME := &"on_time"
## Attended after the tolerance.
const LATE := &"late"
## The input that is 1 while no block is current.
const FREE_TIME := &"schedule.free_time"
## How many days of attendance are kept.
const KEEP_DAYS := 7

## The routine.
var def: BustleScheduleDef
## Who pays wages for blocks that name no payer (the employer of the agent's job). A roster keeps it
## up to date; it is fixed into each block when attended.
var employer: StringName = &""

# Block start (absolute minute) → {activity: String, arrived: int, end: int, wage: int,
# payer: String, paid: bool}. The wage, its payer and the end are kept from the block attended, so
# a shift worked before a change of routine is still paid.
var _attended: Dictionary[int, Dictionary] = {}
# Activities of routines this schedule has swapped away from: fill_inputs erases them.
var _retired: Array[StringName] = []


func _init(p_def: BustleScheduleDef = null) -> void:
	def = p_def if p_def != null else BustleScheduleDef.new()


## Swaps the routine for [param new_def] (a new job, say), keeping attendance. The old routine's
## activity inputs are erased by the next [method fill_inputs].
## @experimental
func set_def(new_def: BustleScheduleDef) -> void:
	for activity: StringName in activities():
		if not _retired.has(activity):
			_retired.append(activity)
	def = new_def if new_def != null else BustleScheduleDef.new()
	for activity: StringName in activities():
		_retired.erase(activity)


## The block current at minute [param now]: [code]{block, start, end, day}[/code] with absolute
## minutes and the game day it belongs to, or an empty dictionary. A block carried over from the
## night before wins over one starting today.
## @experimental
func block_at(now: int, season: StringName = &"") -> Dictionary:
	var today := floori(float(now) / 1440.0)
	for day_index: int in [today - 1, today]:
		for occurrence: Dictionary in _occurrences(day_index, season):
			if int(occurrence["start"]) <= now and now < int(occurrence["end"]):
				return occurrence
	return {}


## The blocks of game day [param day_index] (those starting that day), in order, as
## [code]{block, start, end, day}[/code]. Invalid blocks are skipped.
## @experimental
func occurrences(day_index: int, season: StringName = &"") -> Array[Dictionary]:
	return _occurrences(day_index, season)


## Every activity the routine uses, sorted.
## @experimental
func activities() -> Array[StringName]:
	var out: Array[StringName] = []
	var plans: Array = [def.day]
	plans.append_array(def.weekdays.values())
	plans.append_array(def.seasons.values())
	for plan: Variant in plans:
		if plan == null:
			continue
		for block: BustleScheduleBlock in (plan as BustleScheduleDay).blocks:
			if block != null and block.is_valid() and not out.has(block.activity):
				out.append(block.activity)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Writes the scorer's inputs for minute [param now]: [code]schedule.<activity>[/code] is 1 for the
## current block, and [constant FREE_TIME] is 1 when there is none. The routine's other activity
## inputs (and free time, while a block is current) are erased; other inputs are left alone.
## @experimental
func fill_inputs(inputs: Dictionary[StringName, float], now: int, season: StringName = &"") -> void:
	for activity: StringName in _retired:
		inputs.erase(StringName("schedule.%s" % activity))
	for activity: StringName in activities():
		inputs.erase(StringName("schedule.%s" % activity))
	inputs.erase(FREE_TIME)
	var current := block_at(now, season)
	if current.is_empty():
		inputs[FREE_TIME] = 1.0
	else:
		inputs[StringName("schedule.%s" % (current["block"] as BustleScheduleBlock).activity)] = 1.0


## The agent is doing [param activity] at minute [param now]. When that is the current block's
## activity, records its arrival (the first one counts) and returns [constant ON_TIME] or
## [constant LATE]; otherwise returns empty.
## @experimental
func attend(now: int, activity: StringName, season: StringName = &"") -> StringName:
	var current := block_at(now, season)
	if current.is_empty() or (current["block"] as BustleScheduleBlock).activity != activity:
		return &""
	var start: int = current["start"]
	if not _attended.has(start):
		var block: BustleScheduleBlock = current["block"]
		_attended[start] = {"activity": String(activity), "arrived": now, "end": int(current["end"]),
			"wage": block.wage, "payer": String(block.payer if block.payer != &"" else employer), "paid": false}
	_prune(now)
	return _verdict(current, int(_attended[start]["arrived"]))


## How game day [param day_index] went by minute [param now]:
## [code]{on_time, late, missed, pending}[/code] counts of its blocks. A block that hasn't ended
## and wasn't attended is pending, not missed.
## @experimental
func report(day_index: int, now: int, season: StringName = &"") -> Dictionary:
	var out := {"on_time": 0, "late": 0, "missed": 0, "pending": 0}
	for occurrence: Dictionary in _occurrences(day_index, season):
		var start: int = occurrence["start"]
		var record: Dictionary = _attended.get(start, {})
		if not record.is_empty() and record["activity"] == String((occurrence["block"] as BustleScheduleBlock).activity):
			out[String(_verdict(occurrence, int(record["arrived"])))] += 1
		elif int(occurrence["end"]) <= now:
			out["missed"] += 1
		else:
			out["pending"] += 1
	return out


## Pays [param agent]'s wages for every attended block that has ended by minute [param now] and
## isn't paid yet, through [param trade]. Each payer was fixed when the block was attended;
## [param employer] only pays records saved without one.
## Returns one [code]{start, activity, amount, payer, paid}[/code] per wage tried, in start order;
## an unpaid one stays owed.
## @experimental
func settle(now: int, agent: StringName, trade: BustleTradePort, employer: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var starts: Array[int] = _attended.keys()
	starts.sort()
	for start: int in starts:
		var record := _attended[start]
		var wage: int = record.get("wage", 0)
		if record.get("paid", false) or wage <= 0 or int(record.get("end", 0)) > now:
			continue
		var payer := StringName(record.get("payer", "")) if record.get("payer", "") != "" else employer
		var paid := trade != null and trade.pay(payer, agent, wage)
		record["paid"] = paid
		out.append({"start": start, "activity": StringName(record["activity"]), "amount": wage, "payer": payer, "paid": paid})
	return out


## The attendance as plain data: [code]{"attended": {start: {activity, arrived, end, wage, payer, paid}}}[/code].
## @experimental
func export_state() -> Dictionary:
	var keys: Array[int] = _attended.keys()
	keys.sort()
	var out := {}
	for start: int in keys:
		out[str(start)] = _attended[start].duplicate()
	return {"attended": out}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("attended") is Dictionary:
		return false
	var staged: Dictionary[int, Dictionary] = {}
	var data: Dictionary = saved["attended"]
	for key: Variant in data:
		var record: Variant = data[key]
		if not key is String or not String(key).is_valid_int() or not record is Dictionary:
			return false
		var arrived: Variant = _int(record.get("arrived"))
		var end: Variant = _int(record.get("end", 0))
		var wage: Variant = _int(record.get("wage", 0))
		if not record.get("activity") is String or arrived == null or end == null or wage == null or int(wage) < 0 \
				or not record.get("payer", "") is String or not record.get("paid", false) is bool:
			return false
		staged[String(key).to_int()] = {"activity": record["activity"], "arrived": arrived, "end": end,
			"wage": wage, "payer": record.get("payer", ""), "paid": record.get("paid", false)}
	_attended = staged
	return true


func _occurrences(day_index: int, season: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var plan := def.plan_for(day_index, season)
	if plan == null:
		return out
	for block: BustleScheduleBlock in plan.blocks:
		if block == null or not block.is_valid():
			continue
		var start := day_index * 1440 + block.start_minute
		out.append({"block": block, "start": start, "end": start + block.length(), "day": day_index})
	return out


func _verdict(occurrence: Dictionary, arrived: int) -> StringName:
	var block: BustleScheduleBlock = occurrence["block"]
	var tolerance := block.late_minutes if block.late_minutes >= 0 else maxi(def.late_minutes, 0)
	return ON_TIME if arrived - int(occurrence["start"]) <= tolerance else LATE


func _prune(now: int) -> void:
	for start: int in _attended.keys():
		var record := _attended[start]
		var owed: bool = int(record.get("wage", 0)) > 0 and not record.get("paid", false)
		if start < now - KEEP_DAYS * 1440 and not owed:
			_attended.erase(start)


static func _int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return null
