# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleStuckWatch
extends RefCounted

## Tells a stuck agent from one in a legitimate long activity, from one observation per agent per
## step. A host, a soak or a bench feeds it: [method observe] takes what the caller saw, and
## [method observe_agent] reads what it can from a [BustleNpcState] and asks the hooks for the rest.
## It only reads; it never changes an agent, and it makes no random rolls.
## [br][br]
## [b]Legitimate long activity[/b] (never stuck): sleep, attending a schedule block that hasn't
## ended (including being away for it), travel still closing on its destination
## ([member travel_hook]), an order or other lock in force, a mental state inside its duration,
## waiting on or using an affordance, and off-screen catch-up still advancing
## [member BustleNpcState.last_update_minute] (unless [member check_offscreen_progress]). The caller
## decides the rest and passes [code]legit[/code].
## [br][br]
## [b]Stuck[/b]: more than [member bound_minutes] in a row with no legitimate activity and no
## progress (same goal and step, nothing consumed, and the position within [member move_epsilon]
## of where the run began, or for an off-screen agent the same place with no hop pending). Also
## stuck, whatever the goal: the same goal failing [member fail_loop] steps in a row, or a mental
## state still active past its end.
## @experimental: Development tool. The bound, the epsilon and the loop count are proposed defaults, not tuning, and the rule may change in any minor release.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")

## Game minutes without progress before an agent counts as stuck.
var bound_minutes: int = 120
## How far an agent must move (metres) to count as progress.
var move_epsilon: float = 0.5
## Failed steps of the same goal in a row that count as a failure loop.
var fail_loop: int = 3
## The ring settings [method observe_agent] reads the off-screen interval from
## ([member BustleSimRingConfig.offscreen_interval_game_minutes]). Set it to the rings' own
## [member BustleSimRings.config] so a change there applies here too.
var ring_config: BustleSimRingConfig = BustleSimRingConfig.new()
## When false (the default), off-screen catch-up that is still advancing counts as legitimate, as
## for any long activity. When true, it doesn't: an OFF_SCREEN agent seen through
## [method observe_agent] has to show progress like any other (a new goal or step, a new place, a
## hop pending, something consumed, or [member offscreen_progress_hook]), so an agent the rings
## keep up to date but that never gets anywhere is found.
var check_offscreen_progress: bool = false
## [code]func(agent: StringName, now: int) -> bool[/code]: true while [param agent]'s travel is still
## closing on its destination (its remaining path or time is going down), which is legitimate.
## Asked by [method observe_agent]. Empty: no travel counts.
var travel_hook: Callable = Callable()
## [code]func(agent: StringName, now: int) -> bool[/code]: true when the host's own off-screen
## simulation moved OFF_SCREEN [param agent] on since the last observation (a hop made, a task
## advanced), which is progress. Asked by [method observe_agent] for OFF_SCREEN agents only.
## Empty: only what the agent's state shows counts.
var offscreen_progress_hook: Callable = Callable()

# agent → {since, still, anchor, place, key, fails, fail_goal, stuck, reason, longest}
var _rows: Dictionary[StringName, Dictionary] = {}
# Every stuck spell, oldest first: {agent, since, reason, minutes} (minutes -1 while it lasts).
var _spells: Array[Dictionary] = []
# agent → the last intent observe_agent() saw, so one failed think counts once.
var _intents: Dictionary[StringName, BustleIntent] = {}


## Notes what [param agent] did over the [param minutes] ending at game minute [param now].
## [param seen] holds [code]goal[/code] and [code]step[/code] (what it's doing),
## [code]legit[/code] (in a legitimate long activity), [code]consumed[/code] (something met a
## need), [code]progress[/code] (other progress the caller saw), [code]position[/code] (Vector3)
## or [code]place[/code] (StringName, off-screen), [code]hop_pending[/code], [code]failed[/code]
## (its goal failed this step) and [code]state_overdue[/code] (a mental state past its end); any
## may be left out. Returns a change to report: empty, or
## [code]{event: "stuck", reason, since}[/code] or [code]{event: "unstuck", reason, minutes}[/code].
func observe(agent: StringName, now: int, minutes: int, seen: Dictionary) -> Dictionary:
	return _observe(agent, now, minutes, seen, false)


## [method observe] for [param state], filling in what the state shows: the goal and step from its
## brain, a failure only when the brain thought again, and its position (FULL or LIGHT, when known)
## or its area (OFF_SCREEN). An observation of the same intent as last time neither adds to nor
## resets the failure run, so a failure loop is found however often the agent is watched between
## thinks. [member travel_hook] can make it legitimate. For an OFF_SCREEN agent, catch-up
## still advancing within [member ring_config]'s off-screen interval is legitimate unless
## [member check_offscreen_progress], and [member offscreen_progress_hook] can report progress.
## Anything in [param seen] (the keys [method observe] takes) is used as given, and
## [code]legit[/code] or [code]progress[/code] there adds to what the watch finds.
## Refuses a null [param state]: it warns once and returns an empty change.
func observe_agent(state: BustleNpcState, now: int, minutes: int, seen: Dictionary = {}) -> Dictionary:
	if state == null:
		_Warn.warn("BustleStuckWatch.no_agent", "BustleStuckWatch: observe_agent() got no agent; nothing was observed")
		return {}
	var out := seen.duplicate()
	var brain := state.brain
	var intent: BustleIntent = brain.last_intent if brain != null else null
	if not out.has("goal"):
		out["goal"] = intent.goal_id if intent != null else &""
	if not out.has("step"):
		out["step"] = brain.runner.step_index if brain != null and brain.runner != null else 0
	# The same intent as last time: no new think, so the failure run stays as it is.
	var same_think := not out.has("failed") and _intents.has(state.id) and _intents[state.id] == intent
	if not out.has("failed"):
		out["failed"] = intent != null and not intent.failure.is_empty() and not same_think
	_intents[state.id] = intent
	var legit := bool(out.get("legit", false))
	if travel_hook.is_valid():
		legit = _Warn.as_bool(travel_hook.call(state.id, now), false, "BustleStuckWatch.travel_hook") or legit
	if state.sim_ring == BustleSimRings.Ring.OFF_SCREEN:
		if not out.has("place"):
			out["place"] = state.area
		if not check_offscreen_progress:
			legit = legit or (state.last_update_minute >= 0 and now - state.last_update_minute <= _offscreen_interval())
		if offscreen_progress_hook.is_valid() and _Warn.as_bool(offscreen_progress_hook.call(state.id, now), false,
				"BustleStuckWatch.offscreen_progress_hook"):
			out["progress"] = true
	elif not out.has("position") and state.has_position:
		out["position"] = state.position
	out["legit"] = legit
	return _observe(state.id, now, minutes, out, same_think)


# observe()'s rule. With keep_fails, the failure run is left as it was (no new think was seen).
func _observe(agent: StringName, now: int, minutes: int, seen: Dictionary, keep_fails: bool) -> Dictionary:
	var row: Dictionary = _rows.get(agent, {})
	if row.is_empty():
		row = {"since": now, "still": 0, "anchor": seen.get("position", Vector3.ZERO), "place": seen.get("place", &""),
			"key": "", "fails": 0, "fail_goal": &"", "stuck": false, "reason": "", "longest": 0}
		_rows[agent] = row
	var key := "%s|%s" % [seen.get("goal", &""), seen.get("step", 0)]
	var position: Vector3 = seen.get("position", row["anchor"])
	var anchor: Vector3 = row["anchor"]
	var moved: bool = position.distance_to(anchor) > move_epsilon \
		or StringName(seen.get("place", row["place"])) != StringName(row["place"]) or bool(seen.get("hop_pending", false))
	var progress: bool = bool(seen.get("legit", false)) or bool(seen.get("consumed", false)) \
		or bool(seen.get("progress", false)) or moved or key != row["key"]
	if progress:
		row["still"] = 0
		row["since"] = now
		row["anchor"] = position
		row["place"] = seen.get("place", row["place"])
	else:
		row["still"] = int(row["still"]) + minutes
		row["longest"] = maxi(int(row["longest"]), int(row["still"]))
	row["key"] = key
	if not keep_fails:
		var goal := StringName(seen.get("goal", &""))
		row["fails"] = (int(row["fails"]) + 1 if goal == row["fail_goal"] else 1) if bool(seen.get("failed", false)) else 0
		row["fail_goal"] = goal if bool(seen.get("failed", false)) else &""
	var reason := ""
	if bool(seen.get("state_overdue", false)):
		reason = "state_overdue"
	elif int(row["fails"]) >= fail_loop:
		reason = "fail_loop"
	elif int(row["still"]) > bound_minutes:
		reason = "still"
	if reason != "" and not row["stuck"]:
		row["stuck"] = true
		row["reason"] = reason
		_spells.append({"agent": agent, "since": int(row["since"]), "reason": reason, "minutes": -1})
		return {"event": "stuck", "reason": reason, "since": int(row["since"])}
	if reason == "" and row["stuck"]:
		row["stuck"] = false
		var spell := _open_spell(agent)
		spell["minutes"] = now - int(spell["since"])
		return {"event": "unstuck", "reason": row["reason"], "minutes": spell["minutes"]}
	return {}


## True while [param agent] is stuck.
func is_stuck(agent: StringName) -> bool:
	return bool(_rows.get(agent, {}).get("stuck", false))


## The longest run of game minutes [param agent] has gone with no legitimate activity and no
## progress (stuck or not).
func longest_still(agent: StringName) -> int:
	return int(_rows.get(agent, {}).get("longest", 0))


## Every stuck spell so far, oldest first: [code]{agent, since, reason, minutes}[/code], minutes -1
## while it lasts.
func spells() -> Array[Dictionary]:
	return _spells.duplicate(true)


# The off-screen interval in game minutes, from ring_config (at least 1).
func _offscreen_interval() -> int:
	if ring_config == null:
		_Warn.warn("BustleStuckWatch.no_ring_config", "BustleStuckWatch: ring_config is null; using the default off-screen interval")
		return maxi(BustleSimRingConfig.new().offscreen_interval_game_minutes, 1)
	return maxi(ring_config.offscreen_interval_game_minutes, 1)


func _open_spell(agent: StringName) -> Dictionary:
	for i: int in range(_spells.size() - 1, -1, -1):
		if _spells[i]["agent"] == agent and int(_spells[i]["minutes"]) < 0:
			return _spells[i]
	return {"since": 0}
