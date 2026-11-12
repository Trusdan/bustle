# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## Tells a stuck agent from one in a legitimate long activity, one observation per agent per step.
## The demo harness feeds it; a bench can feed it the same way.
##
## [b]Legitimate long activity[/b] (never stuck): sleep, attending a schedule block that hasn't ended
## (including being away for it), travel still closing on its destination, an order or other lock
## in force, a mental state inside its duration, waiting on or using an affordance, and off-screen
## catch-up still advancing. The observer decides that and passes [code]legit[/code].
##
## [b]Stuck[/b]: more than [member bound_minutes] in a row with no legitimate activity and no
## progress (same goal and step, nothing consumed, and the position within [member move_epsilon]
## of where the run began, or for an off-screen agent the same place with no hop pending). Also
## stuck, whatever the goal: the same goal failing [member fail_loop] steps in a row, or a mental
## state still active past its end. The bound, the epsilon and the loop count are experimental
## defaults, not tuning.

## Game minutes without progress before an agent counts as stuck.
var bound_minutes: int = 120
## How far an agent must move (metres) to count as progress.
var move_epsilon: float = 0.5
## Failed steps of the same goal in a row that count as a failure loop.
var fail_loop: int = 3

# agent → {since, still, anchor, place, key, fails, fail_goal, stuck, reason, longest}
var _rows: Dictionary[StringName, Dictionary] = {}
# Every stuck spell, oldest first: {agent, since, reason, minutes} (minutes -1 while it lasts).
var _spells: Array[Dictionary] = []


## Notes what [param agent] did over the [param minutes] ending at game minute [param now].
## [param seen] holds [code]goal[/code] and [code]step[/code] (what it's doing),
## [code]legit[/code] (in a legitimate long activity), [code]consumed[/code] (something met a
## need), [code]position[/code] (Vector3) or [code]place[/code] (StringName, off-screen),
## [code]hop_pending[/code], [code]failed[/code] (its goal failed this step) and
## [code]state_overdue[/code] (a mental state past its end). Returns a change to report: empty, or
## [code]{event: "stuck", reason, since}[/code] or [code]{event: "unstuck", reason, minutes}[/code].
func observe(agent: StringName, now: int, minutes: int, seen: Dictionary) -> Dictionary:
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
	var progress: bool = bool(seen.get("legit", false)) or bool(seen.get("consumed", false)) or moved or key != row["key"]
	if progress:
		row["still"] = 0
		row["since"] = now
		row["anchor"] = position
		row["place"] = seen.get("place", row["place"])
	else:
		row["still"] = int(row["still"]) + minutes
		row["longest"] = maxi(int(row["longest"]), int(row["still"]))
	row["key"] = key
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


func _open_spell(agent: StringName) -> Dictionary:
	for i: int in range(_spells.size() - 1, -1, -1):
		if _spells[i]["agent"] == agent and int(_spells[i]["minutes"]) < 0:
			return _spells[i]
	return {"since": 0}
