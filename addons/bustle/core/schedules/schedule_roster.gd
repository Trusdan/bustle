# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScheduleRoster
extends RefCounted

## Every agent's [BustleSchedule], chosen by job. An agent's job is the first role it holds (in
## the roles port's sorted order) that [BustleRoleSchedules] has a routine for; it follows that
## routine, or its own ([method set_own]) when it has no job. When a role's holder changes, the old
## and new holders' routines swap at once ([signal schedule_changed]); attendance and owed wages
## stay with the agent. [method settle] pays every agent's ended shifts through the trade port.
## @experimental

## [param id]'s routine changed from [param old_def] to [param new_def] (either may be null).
signal schedule_changed(id: StringName, old_def: BustleScheduleDef, new_def: BustleScheduleDef)

## Who holds which role.
var roles: BustleRolesPort
## The routines and employers of jobs.
var jobs: BustleRoleSchedules

var _own: Dictionary[StringName, BustleScheduleDef] = {}
var _schedules: Dictionary[StringName, BustleSchedule] = {}


func _init(p_roles: BustleRolesPort = null, p_jobs: BustleRoleSchedules = null) -> void:
	roles = p_roles if p_roles != null else BustleRolesPort.new()
	jobs = p_jobs if p_jobs != null else BustleRoleSchedules.new()
	roles.holder_changed.connect(_on_holder_changed)


## Adds agent [param id], with its own routine [param own] for when it has no job.
## @experimental
func add_agent(id: StringName, own: BustleScheduleDef = null) -> void:
	if id == &"":
		return
	_own[id] = own
	_refresh(id)


## Removes agent [param id].
## @experimental
func remove_agent(id: StringName) -> void:
	_own.erase(id)
	_schedules.erase(id)


## Sets agent [param id]'s own routine (used when it has no job).
## @experimental
func set_own(id: StringName, own: BustleScheduleDef) -> void:
	if _own.has(id):
		_own[id] = own
		_refresh(id)


## The agents, sorted.
## @experimental
func ids() -> Array[StringName]:
	var out: Array[StringName] = _schedules.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## [param id]'s job: the first role it holds that has a routine, or empty.
## @experimental
func job_of(id: StringName) -> StringName:
	for role: String in roles.roles_of(id):
		if jobs.schedules.has(StringName(role)) and jobs.schedules[StringName(role)] != null:
			return StringName(role)
	return &""


## [param id]'s schedule, or null for an unknown agent.
## @experimental
func schedule_of(id: StringName) -> BustleSchedule:
	return _schedules.get(id)


## Pays every agent's ended, attended, unpaid shifts at minute [param now] through [param trade].
## A block with no payer is paid by the employer of the agent's current job. Returns
## [code]{agent, start, activity, amount, payer, paid}[/code] per wage tried, by agent then start.
## @experimental
func settle(now: int, trade: BustleTradePort) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in ids():
		var employer: StringName = jobs.employers.get(job_of(id), &"")
		for payment: Dictionary in _schedules[id].settle(now, id, trade, employer):
			payment["agent"] = id
			out.append(payment)
	return out


## Every agent's attendance as plain data, by id.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for id: StringName in ids():
		out[String(id)] = _schedules[id].export_state()
	return {"schedules": out}


## Restores [method export_state] for the agents it has (others are skipped). False, changing
## nothing, when any entry is malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("schedules") is Dictionary:
		return false
	var entries: Dictionary = saved["schedules"]
	for key: Variant in entries:
		if not key is String:
			return false
		var live := schedule_of(StringName(key))
		if live != null and not BustleSchedule.new(live.def).import_state(entries[key]):
			return false
	for key: Variant in entries:
		var live := schedule_of(StringName(key))
		if live != null:
			live.import_state(entries[key])
	return true


func _on_holder_changed(_role: StringName, old: StringName, new: StringName) -> void:
	for id: StringName in [old, new]:
		if id != &"" and _own.has(id):
			_refresh(id)


func _refresh(id: StringName) -> void:
	var job := job_of(id)
	var def: BustleScheduleDef = jobs.schedules[job] if job != &"" else _own.get(id)
	var schedule: BustleSchedule = _schedules.get(id)
	if schedule == null:
		_schedules[id] = BustleSchedule.new(def)
		schedule_changed.emit(id, null, def)
	elif schedule.def != def:
		var old := schedule.def
		schedule.set_def(def)
		schedule_changed.emit(id, old, def)
