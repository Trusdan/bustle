# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSociety
extends RefCounted

## The registry of a population: every agent's [BustleNpcState], independent of any scene, the
## ports the host plugs in, and saving and loading the whole population.
##
## - **Archetypes.** A host registers each archetype once ([method register_archetype]) with the
##   goal library and scoring config its agents share. An agent is added with an archetype; saves
##   store only the archetype's id, never a resource path, so loading never loads files.
## - **Bodies** are optional and come and go ([method BustleNpcState.attach_body]); the state stays.
## - **Saving.** [method export_state] gives plain data with a [constant SCHEMA] version and the
##   agents sorted by id. 64-bit numbers (the world seed and each brain's [code]world_seed[/code]
##   and [code]rng_state[/code]) are written as decimal strings so they stay exact through JSON;
##   on import they may be decimal strings or ints. [method import_state] checks everything first and then replaces the
##   population all at once; anything wrong (a malformed payload, another schema version, a repeated
##   id, an unknown archetype, a brain state that doesn't fit) returns a [BustleImportReport] and
##   changes nothing. Only the current schema is accepted; older versions have no migration yet.
## - [method state_hash] is a SHA-256 of the canonical export, for checking round trips.
## @experimental

## The saved-state schema version.
const SCHEMA := 1

## The ports. Every one starts as its standalone default; replace them with [method set_port].
var ports := BustlePorts.new()
## The world seed agents' brains are seeded from.
var world_seed: int = 0

var _agents: Dictionary[StringName, BustleNpcState] = {}
# archetype id → [library, config]
var _archetypes: Dictionary[StringName, Array] = {}


func _init(p_world_seed: int = 0) -> void:
	world_seed = p_world_seed


## Registers (or replaces) archetype [param id] with the goals and scoring its agents share.
## @experimental
func register_archetype(id: StringName, library: BustleGoalLibrary, config: BustleScoringConfig = null) -> void:
	if id == &"" or library == null:
		push_error("BustleSociety: an archetype needs an id and a library")
		return
	_archetypes[id] = [library, config if config != null else BustleScoringConfig.new()]


## True when archetype [param id] is registered.
## @experimental
func has_archetype(id: StringName) -> bool:
	return _archetypes.has(id)


## Replaces port [param port_name] (one of [constant BustlePorts.NAMES]) with [param port]. False
## when the name is unknown or the port isn't the right kind.
## @experimental
func set_port(port_name: StringName, port: RefCounted) -> bool:
	if not BustlePorts.NAMES.has(String(port_name)) or port == null:
		return false
	var current: Variant = ports.get(port_name)
	if current != null and not is_instance_of(port, (current as RefCounted).get_script()):
		return false
	ports.set(port_name, port)
	return true


## Adds agent [param id] made from [param archetype_id]. Null (with an error) when the id is empty
## or taken, or the archetype isn't registered.
## @experimental
func add_agent(id: StringName, archetype_id: StringName, group: StringName = &"") -> BustleNpcState:
	if id == &"" or _agents.has(id) or not _archetypes.has(archetype_id):
		push_error("BustleSociety: can't add agent %s (%s)" % [id, archetype_id])
		return null
	var state := _make(id, archetype_id, group)
	_agents[id] = state
	return state


## Removes agent [param id]. Its body, if any, is left to the host.
## @experimental
func remove_agent(id: StringName) -> void:
	_agents.erase(id)


## Agent [param id]'s state, or null.
## @experimental
func get_agent(id: StringName) -> BustleNpcState:
	return _agents.get(id, null)


## Every agent's id, sorted.
## @experimental
func agent_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_agents.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Gives agent [param agent_id] [param order] (see [method BustleBrain.order]). Returns an empty
## reason when it was queued, otherwise why not ([code]no_agent[/code] for an unknown agent).
## @experimental
func order(agent_id: StringName, p_order: BustleOrder) -> StringName:
	var state := get_agent(agent_id)
	return state.brain.order(p_order) if state != null else &"no_agent"


## Cancels agent [param agent_id]'s order [param order_id], queued or running. False when there is
## no such agent or order.
## @experimental
func cancel_order(agent_id: StringName, order_id: StringName) -> bool:
	var state := get_agent(agent_id)
	return state != null and state.brain.orders.cancel(order_id)


## The population's state as plain data. Attached bodies' positions are copied in first.
## @experimental
func export_state() -> Dictionary:
	var agents: Array = []
	for id: StringName in agent_ids():
		var state := _agents[id]
		state.sync_from_body()
		agents.append({
			"id": String(id), "archetype": String(state.archetype), "group": String(state.group),
			"area": String(state.area),
			"position": [state.position.x, state.position.y, state.position.z] if state.has_position else null,
			"data": state.data.duplicate(true), "brain": _brain_out(state.brain.export_state()),
		})
	return {"schema": SCHEMA, "world_seed": str(world_seed), "agents": agents}


## Replaces the population with [param saved], all or nothing. Bodies attached to agents that are
## still there stay attached and move to the loaded positions. See the class description for what is refused.
## @experimental
func import_state(saved: Variant) -> BustleImportReport:
	var report := BustleImportReport.new()
	if not saved is Dictionary:
		report.fail("the payload isn't a dictionary")
		return report
	var payload := saved as Dictionary
	var schema: Variant = payload.get("schema")
	if typeof(schema) == TYPE_FLOAT and is_finite(schema) and schema == floorf(schema) and absf(schema) < 1e9:
		schema = int(schema) # JSON reads whole numbers back as floats
	if typeof(schema) != TYPE_INT:
		report.fail("no schema version")
		return report
	report.schema = schema
	if report.schema != SCHEMA:
		report.fail("schema %d isn't supported (this is %d)" % [report.schema, SCHEMA])
		return report
	var seed: Variant = to_int64(payload.get("world_seed"))
	if seed == null or not payload.get("agents") is Array:
		report.fail("world_seed or agents is missing or malformed")
		return report
	var staged: Dictionary[StringName, BustleNpcState] = {}
	var index := 0
	for entry: Variant in payload["agents"]:
		var state := _stage(entry, seed, report, index)
		index += 1
		if state == null:
			continue
		if staged.has(state.id):
			report.fail("agent %d: id %s is repeated" % [index - 1, state.id])
			continue
		staged[state.id] = state
	if not report.errors.is_empty():
		return report
	for id: StringName in staged:
		var old := get_agent(id)
		if old != null and old.body() != null:
			staged[id].attach_body(old.body())
	world_seed = seed
	_agents = staged
	report.ok = true
	return report


## A SHA-256 of the canonical export: sorted keys, full precision, and whole-number floats up to
## 2^53 written as ints, so a state that went through JSON (which reads whole numbers back as
## floats) hashes the same.
## @experimental
func state_hash() -> String:
	return JSON.stringify(_canonical_value(export_state()), "", true, true).sha256_text()


func _make(id: StringName, archetype_id: StringName, group: StringName) -> BustleNpcState:
	var state := BustleNpcState.new()
	state.id = id
	state.archetype = archetype_id
	state.group = group
	var parts: Array = _archetypes[archetype_id]
	state.brain = BustleBrain.new(id, parts[0], parts[1], world_seed)
	return state


# One saved agent checked and built, or null with its reasons in the report.
func _stage(entry: Variant, seed: int, report: BustleImportReport, index: int) -> BustleNpcState:
	var where := "agent %d" % index
	if not entry is Dictionary:
		report.fail("%s isn't a dictionary" % where)
		return null
	var saved := entry as Dictionary
	for key: String in ["id", "archetype", "group", "area"]:
		if not saved.get(key) is String:
			report.fail("%s: %s is missing or not text" % [where, key])
			return null
	var id := StringName(saved["id"])
	var archetype_id := StringName(saved["archetype"])
	if id == &"":
		report.fail("%s: the id is empty" % where)
		return null
	if not _archetypes.has(archetype_id):
		report.fail("%s (%s): archetype %s isn't registered" % [where, id, archetype_id])
		return null
	if not saved.get("data") is Dictionary or not saved.get("brain") is Dictionary:
		report.fail("%s (%s): data or brain is missing" % [where, id])
		return null
	var position: Variant = saved.get("position")
	var has_position := position != null
	if has_position and not _is_position(position):
		report.fail("%s (%s): the position isn't three finite numbers" % [where, id])
		return null
	var previous := world_seed
	world_seed = seed
	var state := _make(id, archetype_id, StringName(saved["group"]))
	world_seed = previous
	state.area = StringName(saved["area"])
	state.data = (saved["data"] as Dictionary).duplicate(true)
	if has_position:
		state.position = Vector3(position[0], position[1], position[2])
		state.has_position = true
	var brain := (saved["brain"] as Dictionary).duplicate(true)
	for key: String in ["world_seed", "rng_state"]:
		if brain.has(key):
			var value: Variant = to_int64(brain[key])
			if value == null:
				report.fail("%s (%s): the brain's %s isn't a 64-bit integer" % [where, id, key])
				return null
			brain[key] = value
	if not state.brain.import_state(brain):
		report.fail("%s (%s): the brain state doesn't fit its archetype" % [where, id])
		return null
	return state


## [param value] as a 64-bit int when it is an int or a decimal string of one (an optional minus
## and digits, in range); otherwise null.
## @experimental
static func to_int64(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if not value is String:
		return null
	var text := value as String
	var digits := text.trim_prefix("-")
	if digits.is_empty() or not digits.is_valid_int() or digits.begins_with("+") or digits.begins_with("-") \
			or digits.length() > 19:
		return null
	var number := text.to_int()
	return number if str(number) == _canonical(text) else null


static func _canonical(text: String) -> String:
	var negative := text.begins_with("-")
	var digits := text.trim_prefix("-").lstrip("0")
	if digits.is_empty():
		return "0"
	return ("-" if negative else "") + digits


static func _canonical_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			return int(f) if is_finite(f) and f == floorf(f) and absf(f) <= 9007199254740992.0 else f
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				out[key] = _canonical_value(value[key])
			return out
		TYPE_ARRAY:
			return (value as Array).map(_canonical_value)
	return value


static func _brain_out(state: Dictionary) -> Dictionary:
	for key: String in ["world_seed", "rng_state"]:
		if typeof(state.get(key)) == TYPE_INT:
			state[key] = str(state[key])
	return state


static func _is_position(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for n: Variant in value:
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(n)):
			return false
	return true
