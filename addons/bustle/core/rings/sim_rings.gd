# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSimRings
extends RefCounted

## Sorts a society's agents into simulation rings by where they are relative to the player, using
## the society's world and clock ports. It only classifies: a ring change touches nothing in the
## agent's state. Areas come first, metres second.
##
## - **FULL:** in the player's area, and either within [member BustleSimRingConfig.full_radius]
##   of the player (outdoors) or anywhere in it (an interior, with
##   [member BustleSimRingConfig.full_whole_interior]).
## - **LIGHT:** in the player's outdoor area but farther (or with no known position), or in an
##   area next to the player's.
## - **OFF_SCREEN:** anywhere else.
## - **By distance** (outdoors, in the player's area): a FULL agent stays FULL until it is beyond
##   the radius plus [member BustleSimRingConfig.hysteresis], and a change waits until
##   [member BustleSimRingConfig.min_dwell_seconds] have passed since the last one.
## - **By area** (the agent's area relative to the player's changed): the change applies at once,
##   FULL to OFF_SCREEN included, except LIGHT to OFF_SCREEN, which waits until the area has been
##   out of reach for [member BustleSimRingConfig.light_to_offscreen_delay_seconds].
## - A new agent gets its ring at once, or the ring it was saved with
##   ([member BustleNpcState.sim_ring]), so after a load an agent in the hysteresis band stays FULL.
## - **Bodies** (with [member BustleSimRingConfig.manage_bodies]): an agent that becomes FULL gets a
##   body from [method BustleWorldPort.spawn_body] at its last position. If that spot is within
##   [member BustleSimRingConfig.no_pop_in_distance] of the player and in view
##   ([method BustleWorldPort.is_in_view]), the body appears at the nearest spot out of view
##   within that distance of it instead (checked at 8 bearings and 4 distances, nearest first);
##   if there is none, or the agent has no known position, the spawn waits and is retried on later
##   updates. An agent that stops being FULL has its position kept and its body freed
##   ([method BustleWorldPort.free_body]).
## @experimental

## The rings.
enum Ring { FULL, LIGHT, OFF_SCREEN }

## Agent [param id] moved from ring [param old] to [param new].
signal ring_changed(id: StringName, old: Ring, new: Ring)
## Agent [param id] got a body at [param position]; [param moved] when that isn't its last
## position (it would have appeared in view).
signal body_spawned(id: StringName, position: Vector3, moved: bool)
## Agent [param id]'s body was freed.
signal body_freed(id: StringName)

## The society it sorts.
var society: BustleSociety
## The thresholds.
var config: BustleSimRingConfig

# Where an agent's area is relative to the player's.
enum _Zone { HERE, NEAR, AWAY }

# id → {ring, zone (when the ring was last set), held (s since the last change), away (s out of reach), entered}
var _agents: Dictionary[StringName, Dictionary] = {}


func _init(p_society: BustleSociety = null, p_config: BustleSimRingConfig = null) -> void:
	society = p_society
	config = p_config if p_config != null else BustleSimRingConfig.new()


## Re-sorts every agent after [param delta] real seconds.
## @experimental
func update(delta: float) -> void:
	if society == null:
		return
	var step := maxf(delta, 0.0)
	var world := society.ports.world
	var now := society.ports.clock.now_minutes()
	var player_area := world.player_area()
	var interior := config.full_whole_interior and world.is_interior(player_area)
	var near := world.neighbour_areas(player_area)
	var player := world.player_position()
	var present := {}
	for id: StringName in society.agent_ids():
		present[id] = true
		var state := society.get_agent(id)
		var area := world.area_of(id)
		var zone := _Zone.HERE if area == player_area else (_Zone.NEAR if near.has(area) else _Zone.AWAY)
		var entry: Dictionary = _agents.get(id, {})
		var current: int = entry.get("ring", -1)
		var wanted := _wanted(state, zone, interior, player, current)
		if entry.is_empty() and state.sim_ring >= Ring.FULL and state.sim_ring <= Ring.OFF_SCREEN:
			entry = {"ring": state.sim_ring, "zone": zone, "held": config.min_dwell_seconds,
				"away": config.light_to_offscreen_delay_seconds, "entered": now}
			_agents[id] = entry
			current = state.sim_ring
			wanted = _wanted(state, zone, interior, player, current)
		elif entry.is_empty():
			_agents[id] = {"ring": wanted, "zone": zone, "held": 0.0, "away": 0.0, "entered": now}
			_set_ring(state, -1, wanted, player)
			continue
		entry["held"] = float(entry["held"]) + step
		entry["away"] = float(entry["away"]) + step if zone == _Zone.AWAY else 0.0
		if wanted == current:
			entry["zone"] = zone
			_set_ring(state, current, current, player)
			continue
		var allowed: bool
		if current == Ring.LIGHT and wanted == Ring.OFF_SCREEN:
			allowed = float(entry["away"]) >= config.light_to_offscreen_delay_seconds - 1e-9
		elif zone == _Zone.HERE and entry["zone"] == _Zone.HERE and not interior:
			allowed = float(entry["held"]) >= config.min_dwell_seconds - 1e-9
		else:
			allowed = true
		if allowed:
			entry["ring"] = wanted
			entry["zone"] = zone
			entry["held"] = 0.0
			entry["entered"] = now
			_set_ring(state, current, wanted, player)
			ring_changed.emit(id, current as Ring, wanted as Ring)
		else:
			_set_ring(state, current, current, player)
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


# Records the ring on the state and spawns or frees the body to match.
func _set_ring(state: BustleNpcState, old: int, new: int, player: Vector3) -> void:
	state.sim_ring = new
	if not config.manage_bodies:
		return
	if new == Ring.FULL and state.body() == null:
		_spawn(state, player)
	elif new != Ring.FULL and old == Ring.FULL and state.body() != null:
		state.detach_body()
		society.ports.world.free_body(state.id)
		body_freed.emit(state.id)


func _spawn(state: BustleNpcState, player: Vector3) -> void:
	if not state.has_position:
		return
	var world := society.ports.world
	var spot := state.position
	var moved := false
	if spot.distance_to(player) <= config.no_pop_in_distance and world.is_in_view(spot):
		var found := false
		for ring_index in range(1, 5):
			var reach := config.no_pop_in_distance * ring_index / 4.0
			for bearing in 8:
				var angle := bearing * TAU / 8.0
				var candidate := state.position + Vector3(cos(angle), 0.0, sin(angle)) * reach
				if not world.is_in_view(candidate):
					spot = candidate
					found = true
					break
			if found:
				break
		if not found:
			return
		moved = true
	var body := world.spawn_body(state.id, Transform3D(Basis(), spot))
	if body == null:
		return
	state.position = spot
	state.has_position = true
	state.attach_body(body)
	body_spawned.emit(state.id, spot, moved)


func _wanted(state: BustleNpcState, zone: _Zone, interior: bool, player: Vector3, current: int) -> int:
	if zone == _Zone.NEAR:
		return Ring.LIGHT
	if zone == _Zone.AWAY:
		return Ring.OFF_SCREEN
	if interior:
		return Ring.FULL
	if not state.has_position:
		return Ring.LIGHT
	var reach := config.full_radius + (config.hysteresis if current == Ring.FULL else 0.0)
	return Ring.FULL if state.position.distance_to(player) <= reach else Ring.LIGHT
