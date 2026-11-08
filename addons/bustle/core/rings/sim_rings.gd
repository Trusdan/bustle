# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSimRings
extends RefCounted

## Sorts a society's agents into simulation rings by where they are relative to the player, using
## the society's world and clock ports. It only classifies: a ring change touches nothing in the
## agent's state.
##
## - **FULL:** in the player's area and within [member BustleSimRingConfig.full_radius] of the
##   player.
## - **LIGHT:** in the player's area but farther (or with no known position), or in an area next to
##   the player's.
## - **OFF_SCREEN:** anywhere else.
## - **Hysteresis:** a FULL agent stays FULL until it is beyond the radius plus
##   [member BustleSimRingConfig.hysteresis].
## - **Dwell:** after a change, an agent keeps its ring for
##   [member BustleSimRingConfig.min_dwell_seconds] whatever happens. A new agent gets its ring at
##   once.
## @experimental

## The rings.
enum Ring { FULL, LIGHT, OFF_SCREEN }

## Agent [param id] moved from ring [param old] to [param new].
signal ring_changed(id: StringName, old: Ring, new: Ring)

## The society it sorts.
var society: BustleSociety
## The thresholds.
var config: BustleSimRingConfig

# id → {ring, held (seconds since the last change), entered (clock minute)}
var _agents: Dictionary[StringName, Dictionary] = {}


func _init(p_society: BustleSociety = null, p_config: BustleSimRingConfig = null) -> void:
	society = p_society
	config = p_config if p_config != null else BustleSimRingConfig.new()


## Re-sorts every agent after [param delta] real seconds.
## @experimental
func update(delta: float) -> void:
	if society == null:
		return
	var world := society.ports.world
	var now := society.ports.clock.now_minutes()
	var player_area := world.player_area()
	var near := world.neighbour_areas(player_area)
	var player := world.player_position()
	var present := {}
	for id: StringName in society.agent_ids():
		present[id] = true
		var state := society.get_agent(id)
		var entry: Dictionary = _agents.get(id, {})
		var current: int = entry.get("ring", -1)
		var wanted := _wanted(state, world.area_of(id), player_area, near, player, current)
		if entry.is_empty():
			_agents[id] = {"ring": wanted, "held": 0.0, "entered": now}
			continue
		entry["held"] = float(entry["held"]) + maxf(delta, 0.0)
		if wanted != current and float(entry["held"]) >= config.min_dwell_seconds - 1e-9:
			entry["ring"] = wanted
			entry["held"] = 0.0
			entry["entered"] = now
			ring_changed.emit(id, current as Ring, wanted as Ring)
	for id: StringName in _agents.keys():
		if not present.has(id):
			_agents.erase(id)


## Agent [param id]'s ring. OFF_SCREEN for an agent not sorted yet.
## @experimental
func ring_of(id: StringName) -> Ring:
	return int(_agents.get(id, {}).get("ring", Ring.OFF_SCREEN)) as Ring


## The clock minute agent [param id] entered its ring, or -1 for an agent not sorted yet.
## @experimental
func entered_minutes(id: StringName) -> int:
	return int(_agents.get(id, {}).get("entered", -1))


## How many agents are in each ring: [code]{FULL: n, LIGHT: n, OFF_SCREEN: n}[/code].
## @experimental
func counts() -> Dictionary:
	var out := {"FULL": 0, "LIGHT": 0, "OFF_SCREEN": 0}
	for entry: Dictionary in _agents.values():
		out[Ring.keys()[entry["ring"]]] += 1
	return out


func _wanted(state: BustleNpcState, area: StringName, player_area: StringName, near: Array[StringName],
		player: Vector3, current: int) -> int:
	if area == player_area:
		if not state.has_position:
			return Ring.LIGHT
		var reach := config.full_radius + (config.hysteresis if current == Ring.FULL else 0.0)
		return Ring.FULL if state.position.distance_to(player) <= reach else Ring.LIGHT
	return Ring.LIGHT if near.has(area) else Ring.OFF_SCREEN
