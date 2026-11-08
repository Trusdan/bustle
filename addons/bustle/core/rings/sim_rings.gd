# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSimRings
extends RefCounted

## Sorts a society's agents into simulation rings by where they are relative to the player, using
## the society's world and clock ports, and runs each ring. Areas come first, metres second. A ring
## change touches only the agent's [member BustleNpcState.sim_ring] and, with
## [member BustleSimRingConfig.manage_bodies], its body (which may move its saved position to where
## the body was or appears); [method tick] and [method catch_up] also let its brain think and set
## [member BustleNpcState.last_update_minute]. Nothing else in its state changes.
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
## - **Leaving OFF_SCREEN** (in [method update] as in [method tick]): the agent is caught up
##   ([method catch_up]) as it changes ring, before its body appears.
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
## Agent [param id] was caught up; see [method catch_up] for [param report].
signal caught_up(id: StringName, report: Dictionary)

## [code]func(id: StringName, ring: Ring, minute: int) -> BustleSenses[/code], what an agent senses
## when its brain thinks in [method tick] or [method catch_up]. Unset: senses with only the time.
var senses_provider: Callable = Callable()
## [code]func(id: StringName, report: Dictionary) -> void[/code], called when catch-up skipped time
## beyond the cap, so modules can apply what the skipped time did in summary.
var summary_hook: Callable = Callable()
## Microseconds the last [method tick] spent on each ring's thinking:
## [code]{FULL, LIGHT, OFF_SCREEN}[/code].
var last_timings: Dictionary = {"FULL": 0, "LIGHT": 0, "OFF_SCREEN": 0}

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


## Re-sorts every agent (see [method update]) and then lets each think as its ring allows:
## FULL every 1 / [member BustleSimRingConfig.full_brain_hz] real seconds, LIGHT every
## 1 / [member BustleSimRingConfig.light_rate_hz], and OFF_SCREEN once each
## [member BustleSimRingConfig.offscreen_interval_game_minutes] of game time, at a fixed phase per
## agent so they don't all think in the same frame (FULL and LIGHT are staggered the same way). Each
## think sets [member BustleNpcState.last_update_minute].
## @experimental
func tick(delta: float) -> void:
	if society == null:
		return
	update(delta)
	var now := society.ports.clock.now_minutes()
	var spent := {"FULL": 0, "LIGHT": 0, "OFF_SCREEN": 0}
	for id: StringName in society.agent_ids():
		var entry: Dictionary = _agents.get(id, {})
		if entry.is_empty():
			continue
		var state := society.get_agent(id)
		var ring: int = entry["ring"]
		var started := Time.get_ticks_usec()
		if ring == Ring.OFF_SCREEN:
			if state.last_update_minute < 0:
				state.last_update_minute = now - _phase(id)
			if now - state.last_update_minute >= config.offscreen_interval_game_minutes:
				state.last_update_minute += config.offscreen_interval_game_minutes
				_think(state, Ring.OFF_SCREEN, state.last_update_minute, config.offscreen_interval_game_minutes * 60.0)
		else:
			var hz := config.full_brain_hz if ring == Ring.FULL else config.light_rate_hz
			var wait := 1.0 / maxf(hz, 0.001)
			if not entry.has("think"):
				# A fixed per-agent offset so agents in a ring don't all think in the same frame.
				entry["think"] = wait * (1.0 - posmod(BustleBrain.seed_for(society.world_seed, id), 1000) / 1000.0)
			entry["think"] = float(entry["think"]) + maxf(delta, 0.0)
			if float(entry["think"]) >= wait - 1e-9:
				entry["think"] = 0.0
				state.last_update_minute = now
				_think(state, ring, now, wait)
		spent[Ring.keys()[ring]] += Time.get_ticks_usec() - started
	last_timings = spent


## Brings agent [param id] up to the clock's minute with OFF_SCREEN thinking from its
## [member BustleNpcState.last_update_minute]: one think per
## [member BustleSimRingConfig.offscreen_interval_game_minutes], for at most
## [member BustleSimRingConfig.catch_up_cap_game_days]. The most recent time is simulated; anything
## older is summarised (passed to [member summary_hook]) rather than run. Deterministic for the same
## state and senses. Returns [code]{agent, from, to, ticks, simulated_minutes, skipped_minutes}[/code]
## and emits [signal caught_up] when anything happened.
## @experimental
func catch_up(id: StringName) -> Dictionary:
	var state := society.get_agent(id) if society != null else null
	var now := society.ports.clock.now_minutes() if society != null else 0
	var report := {"agent": id, "from": -1, "to": now, "ticks": 0, "simulated_minutes": 0, "skipped_minutes": 0}
	if state == null:
		return report
	var interval := maxi(config.offscreen_interval_game_minutes, 1)
	if state.last_update_minute < 0:
		state.last_update_minute = now
		return report
	report["from"] = state.last_update_minute
	var elapsed := now - state.last_update_minute
	if elapsed < interval:
		return report
	var ticks := mini(elapsed / interval, maxi(config.catch_up_cap_game_days, 0) * 1440 / interval)
	var skipped := elapsed - elapsed % interval - ticks * interval
	var minute := state.last_update_minute + skipped
	for i in ticks:
		minute += interval
		_think(state, Ring.OFF_SCREEN, minute, interval * 60.0)
	state.last_update_minute = minute
	report["ticks"] = ticks
	report["simulated_minutes"] = ticks * interval
	report["skipped_minutes"] = skipped
	if skipped > 0 and summary_hook.is_valid():
		summary_hook.call(id, report)
	caught_up.emit(id, report)
	return report


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


func _think(state: BustleNpcState, ring: int, minute: int, seconds: float) -> void:
	var senses: BustleSenses = null
	if senses_provider.is_valid():
		senses = senses_provider.call(state.id, ring, minute)
	if senses == null:
		senses = BustleSenses.new()
	senses.now_minutes = minute
	state.brain.tick(seconds, senses)


# A fixed per-agent offset (in game minutes) so OFF_SCREEN agents don't all think together.
func _phase(id: StringName) -> int:
	var interval := maxi(config.offscreen_interval_game_minutes, 1)
	return posmod(BustleBrain.seed_for(society.world_seed, id), interval)


# Records the ring on the state and spawns or frees the body to match.
func _set_ring(state: BustleNpcState, old: int, new: int, player: Vector3) -> void:
	state.sim_ring = new
	if old == Ring.OFF_SCREEN and new != Ring.OFF_SCREEN:
		catch_up(state.id)
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
