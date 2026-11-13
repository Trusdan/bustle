# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAspirations
extends RefCounted

## The aspirations module, for one agent: short-lived wants and event-formed fears. It is separate
## from ambitions, which keep working the same with it on or off.
## [br][br]
## [b]Wants.[/b] Each [method update], an active want whose [method BustleWantDef.is_done] holds is
## fulfilled: its satisfaction thought goes to the mood. One that has reached its expiry minute
## instead expires, with no thought. Then, while fewer than
## [member BustleAspirationConfig.auto_wants] automatic wants are active, the eligible want with the
## highest score is taken (ties to the lower id). The host may also post wants
## ([method post_want]); all wants together stay within [member BustleAspirationConfig.want_cap].
## [br][br]
## A fulfilled want also earns its [member BustleWantDef.points]. Points only accumulate: the host
## spends them ([method spend_points]), for example from [member on_points]. Bustle defines no
## rewards. An active want may boost the goals it names ([method boost]), never past
## [member BustleAspirationConfig.max_want_boost] and never a [code]never_boost[/code] goal.
## [br][br]
## [b]Fears.[/b] An event passed to [method update] forms each fear it triggers, or renews one already
## formed. While formed, a fear multiplies the scores of the goals and options it avoids
## ([method avoidance], for [member BustleBrain.score_boost]); it only lowers scores. It ends after
## its duration, or when its clearing fact is true.
## [br][br]
## Nothing is random: wants and fears come only from causes and state.
## @experimental

## A want was taken; [param info] is its row ([method wants]).
signal want_added(agent: StringName, id: StringName, info: Dictionary)
## A want was fulfilled, and its thought added (with a mood).
signal want_fulfilled(agent: StringName, id: StringName, info: Dictionary)
## A want expired unfulfilled.
signal want_expired(agent: StringName, id: StringName, info: Dictionary)
## A fear formed, or was renewed by its trigger ([code]info.renewed[/code]).
signal fear_formed(agent: StringName, id: StringName, info: Dictionary)
## A fear ended: [param reason] is [code]expired[/code] or [code]cleared[/code].
signal fear_ended(agent: StringName, id: StringName, reason: StringName)
## Points changed by [param amount] (negative when spent) for [param reason]; [param total] is the
## new total.
signal points_changed(agent: StringName, amount: int, reason: StringName, total: int)

## The agent.
var agent_id: StringName
## The library and numbers.
var config: BustleAspirationConfig
## The host's reward hook, [code]func(agent, amount, reason)[/code], called after points are earned
## (with the new total already counted). It may spend them with [method spend_points]. Unset: points
## only accumulate.
var on_points: Callable = Callable()

var _points: int = 0

## Want id → {id, since, expires, source}.
var _wants: Dictionary[StringName, Dictionary] = {}
## Fear id → {id, since, until, target}.
var _fears: Dictionary[StringName, Dictionary] = {}
## Want id → the game minute it last ended.
var _ended: Dictionary[StringName, int] = {}


## For agent [param p_agent], with [param p_config] (an empty library when null).
func _init(p_agent: StringName = &"", p_config: BustleAspirationConfig = null) -> void:
	agent_id = p_agent
	config = p_config if p_config != null else BustleAspirationConfig.new()


## Brings wants and fears up to game minute [param now]: fulfils wants whose
## [method BustleWantDef.is_done] holds in [param inputs] (adding their thought to [param mood],
## anything with [code]add_thought(def, details)[/code]), expires wants that have run out, ends fears
## that have run out or are cleared, forms fears from [param events], and fills the automatic want
## slot from [param personality] and [param inputs].
## @experimental
func update(now: int, personality: BustlePersonality = null, inputs: Dictionary = {}, events: Array[StringName] = [],
		mood: Object = null) -> void:
	for id: StringName in _sorted(_wants.keys()):
		var def := config.find_want(id)
		if def != null and def.is_done(inputs):
			fulfill(id, now, mood)
		elif def == null or now >= int(_wants[id]["expires"]):
			var info := _wants[id].duplicate()
			_end_want(id, now)
			want_expired.emit(agent_id, id, info)
	for id: StringName in _sorted(_fears.keys()):
		var def := config.find_fear(id)
		if def == null or (def.cleared_fact != &"" and bool(inputs.get(def.cleared_fact, false))):
			_fears.erase(id)
			fear_ended.emit(agent_id, id, &"cleared")
		elif int(_fears[id]["until"]) >= 0 and now >= int(_fears[id]["until"]):
			_fears.erase(id)
			fear_ended.emit(agent_id, id, &"expired")
	for event: StringName in events:
		for def: BustleFearDef in config.fears:
			if def != null and def.is_valid() and def.trigger == event:
				_form(def, now, inputs, mood)
	while _count(&"auto") < config.auto_wants and _wants.size() < config.want_cap:
		var chosen := choose(now, personality, inputs)
		if chosen == null:
			break
		_add_want(chosen, now, &"auto")


## The eligible want with the highest score (ties to the lower id), or null. Eligible: valid,
## automatic, every [member BustleWantDef.requires] true, not already fulfilled by [param inputs],
## not active, and past its cooldown. Changes nothing.
## @experimental
func choose(now: int, personality: BustlePersonality = null, inputs: Dictionary = {}) -> BustleWantDef:
	var best: BustleWantDef = null
	var best_score := -INF
	for def: BustleWantDef in config.wants:
		if def == null or not def.is_valid() or not def.auto or _wants.has(def.id) or def.is_done(inputs):
			continue
		if not def.requires.all(func(fact: StringName) -> bool: return bool(inputs.get(fact, false))):
			continue
		if _ended.has(def.id) and now < _ended[def.id] + int(def.cooldown_hours * 60.0):
			continue
		var value := score_of(def, personality)
		if value > best_score or (value == best_score and String(def.id) < String(best.id)):
			best = def
			best_score = value
	return best


## [param def]'s score for [param personality]: [code]Σ weight × (slider − 50) / 100[/code].
## @experimental
func score_of(def: BustleWantDef, personality: BustlePersonality = null) -> float:
	var total := 0.0
	for slider: StringName in def.weights:
		var value := personality.slider(slider) if personality != null else 50.0
		total += def.weights[slider] * (value - 50.0) / 100.0
	return total


## Gives the agent want [param id] at game minute [param now], posted by the host. False (and no
## change) for an unknown or invalid want, one already active, or a full cap.
## @experimental
func post_want(id: StringName, now: int) -> bool:
	var def := config.find_want(id)
	if def == null or not def.is_valid() or _wants.has(id) or _wants.size() >= config.want_cap:
		return false
	_add_want(def, now, &"posted")
	return true


## Fulfils active want [param id] at game minute [param now] (the host saying so, or
## [method update] finding it done): its thought goes to [param mood]. False when it isn't active.
## @experimental
func fulfill(id: StringName, now: int, mood: Object = null) -> bool:
	if not _wants.has(id):
		return false
	var info := _wants[id].duplicate()
	_end_want(id, now)
	var def := config.find_want(id)
	if def != null and def.thought != null and mood != null and mood.has_method(&"add_thought"):
		mood.call(&"add_thought", def.thought, {"want": String(id)})
	want_fulfilled.emit(agent_id, id, info)
	if def != null and def.points > 0:
		add_points(def.points, StringName("want:" + String(id)))
	return true


## The agent's aspiration points.
## @experimental
func points() -> int:
	return _points


## Adds [param amount] points for [param reason], then calls [member on_points]. False (and no
## change) unless [param amount] is positive.
## @experimental
func add_points(amount: int, reason: StringName) -> bool:
	if amount <= 0:
		return false
	_points += amount
	points_changed.emit(agent_id, amount, reason, _points)
	if on_points.is_valid():
		on_points.call(agent_id, amount, reason)
	return true


## Spends [param amount] points for [param reason] (the host's reward). False (and no change) unless
## [param amount] is positive and no more than the points held.
## @experimental
func spend_points(amount: int, reason: StringName) -> bool:
	if amount <= 0 or amount > _points:
		return false
	_points -= amount
	points_changed.emit(agent_id, -amount, reason, _points)
	return true


## How much the active wants multiply goal [param goal_id]'s score for option [param option_id]:
## the largest boost any active want gives it (wants don't stack), capped by
## [member BustleAspirationConfig.max_want_boost]. 1 for a [code]never_boost[/code] goal, a goal no
## want names, or an option other than a want's [member BustleWantDef.boost_option]. Never below 1.
## @experimental
func boost(goal_id: StringName, option_id: StringName = &"") -> float:
	if config.never_boost.has(goal_id):
		return 1.0
	var best := 1.0
	for id: StringName in _wants:
		var def := config.find_want(id)
		if def == null or not def.boosts.has(goal_id) or (def.boost_option != &"" and option_id != def.boost_option):
			continue
		best = maxf(best, minf(def.boosts[goal_id], maxf(config.max_want_boost, 1.0)))
	return best


## The aspirations' whole effect on a score, for [member BustleBrain.score_boost]:
## [method boost] × [method avoidance]. Multiply it with other boosts, such as an ambition's.
## @experimental
func score(goal_id: StringName, option_id: StringName = &"") -> float:
	return boost(goal_id, option_id) * avoidance(goal_id, option_id)


## The active wants as rows [code]{id, since, expires, source}[/code] (source
## [code]auto[/code] or [code]posted[/code]), sorted by id.
## @experimental
func wants() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _sorted(_wants.keys()):
		out.append(_wants[id].duplicate())
	return out


## The formed fears as rows [code]{id, since, until, target}[/code] ([code]until[/code] −1: until
## cleared), sorted by id.
## @experimental
func fears() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _sorted(_fears.keys()):
		out.append(_fears[id].duplicate())
	return out


## True while want [param id] is active.
## @experimental
func has_want(id: StringName) -> bool:
	return _wants.has(id)


## True while fear [param id] is formed.
## @experimental
func has_fear(id: StringName) -> bool:
	return _fears.has(id)


## How much the formed fears multiply goal [param goal_id]'s score for option [param option_id]
## (for [member BustleBrain.score_boost]): the product of [member BustleFearDef.avoid_mult] over
## every fear that avoids the goal, the option, or the option named when it formed. 1 with none.
## Never above 1. Combine it with other boosts by multiplying.
## @experimental
func avoidance(goal_id: StringName, option_id: StringName = &"") -> float:
	var mult := 1.0
	for id: StringName in _fears:
		var def := config.find_fear(id)
		if def == null:
			continue
		var target := String(_fears[id]["target"])
		if def.avoid_goals.has(goal_id) or (option_id != &"" and (def.avoid_options.has(option_id)
				or (target != "" and String(option_id) == target))):
			mult *= def.avoid_mult
	return mult


## Active wants, formed fears, when each want last ended and the points, as plain data, with absolute game
## minutes, so expiry carries over a save.
## @experimental
func export_state() -> Dictionary:
	var ended := {}
	for id: StringName in _sorted(_ended.keys()):
		ended[String(id)] = _ended[id]
	return {"wants": wants(), "fears": fears(), "ended": ended, "points": _points}


## Restores [method export_state], replacing everything. False (and nothing changes) when malformed
## or naming a want or fear the config doesn't have. A save without [code]points[/code] has none.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not saved.get("wants") is Array or not saved.get("fears") is Array \
			or not saved.get("ended") is Dictionary:
		return false
	var wants_in: Dictionary[StringName, Dictionary] = {}
	for row: Variant in saved["wants"]:
		if not row is Dictionary or not row.get("id") is String or config.find_want(StringName(row["id"])) == null \
				or not _is_int(row.get("since")) or not _is_int(row.get("expires")) \
				or not ["auto", "posted"].has(row.get("source")) or wants_in.has(StringName(row["id"])):
			return false
		wants_in[StringName(row["id"])] = {"id": row["id"], "since": int(row["since"]),
			"expires": int(row["expires"]), "source": row["source"]}
	var fears_in: Dictionary[StringName, Dictionary] = {}
	for row: Variant in saved["fears"]:
		if not row is Dictionary or not row.get("id") is String or config.find_fear(StringName(row["id"])) == null \
				or not _is_int(row.get("since")) or not _is_int(row.get("until")) or not row.get("target") is String \
				or fears_in.has(StringName(row["id"])):
			return false
		fears_in[StringName(row["id"])] = {"id": row["id"], "since": int(row["since"]), "until": int(row["until"]),
			"target": row["target"]}
	var ended_in: Dictionary[StringName, int] = {}
	for id: Variant in saved["ended"]:
		if not id is String or config.find_want(StringName(id)) == null or not _is_int(saved["ended"][id]):
			return false
		ended_in[StringName(id)] = int(saved["ended"][id])
	var points_in: Variant = saved.get("points", 0)
	if wants_in.size() > config.want_cap or not _is_int(points_in) or int(points_in) < 0:
		return false
	_wants = wants_in
	_fears = fears_in
	_ended = ended_in
	_points = int(points_in)
	return true


func _add_want(def: BustleWantDef, now: int, source: StringName) -> void:
	_wants[def.id] = {"id": String(def.id), "since": now, "expires": now + int(def.duration_hours * 60.0),
		"source": String(source)}
	want_added.emit(agent_id, def.id, _wants[def.id].duplicate())


func _end_want(id: StringName, now: int) -> void:
	_wants.erase(id)
	_ended[id] = now


func _form(def: BustleFearDef, now: int, inputs: Dictionary, mood: Object) -> void:
	var renewed := _fears.has(def.id)
	var target: String = _fears[def.id]["target"] if renewed else ""
	if def.avoid_input != &"" and inputs.get(def.avoid_input) != null and str(inputs[def.avoid_input]) != "":
		target = str(inputs[def.avoid_input])
	_fears[def.id] = {"id": String(def.id), "since": now,
		"until": now + int(def.duration_hours * 60.0) if def.duration_hours > 0.0 else -1, "target": target}
	if def.thought != null and mood != null and mood.has_method(&"add_thought"):
		mood.call(&"add_thought", def.thought, {"fear": String(def.id)})
	var info := _fears[def.id].duplicate()
	info["renewed"] = renewed
	fear_formed.emit(agent_id, def.id, info)


func _count(source: StringName) -> int:
	var total := 0
	for id: StringName in _wants:
		if _wants[id]["source"] == String(source):
			total += 1
	return total


static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


static func _sorted(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ids)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
