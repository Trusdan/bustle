# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConflict
extends RefCounted

## Fight, flee or fetch help, in the CRITICAL band. An agent that [method notice]s someone it
## regards as hostile (by the disposition port, never by opinion) takes a stance from its
## personality: bold or hot-tempered agents fight, timid ones fetch a nearby ally or flee.
## [method fill_inputs] writes the stance as the scorer's [code]threat.fight[/code],
## [code]threat.flee[/code] and [code]threat.fetch_help[/code] inputs, which the goals from
## [method goal_defs] read; the [code]fight[/code], [code]flee[/code] and [code]fetch_help[/code]
## actions carry them out. When a conflict ends, its inputs go and the agent's usual goals (its
## schedule) win again.
## [br][br]
## A fight is a scuffle unless a seeded roll against [member BustleConflictConfig.lethal_chance]
## makes it lethal; a scuffle never kills ([method filter_damage]). Every fight that ends emits
## [signal assaulted], and one that killed also [signal killed], so a host can apply consequences.
## A [method quarrel] can turn into a scuffle without making anyone hostile.
## @experimental

## [param attacker] fought [param victim]. [param circumstances]:
## [code]{cause, lethal, killed, at}[/code], where [code]cause[/code] is [code]hostile[/code],
## [code]quarrel[/code] or [code]help[/code].
signal assaulted(attacker: StringName, victim: StringName, circumstances: Dictionary)
## [param attacker] killed [param victim] (after [signal assaulted]).
signal killed(attacker: StringName, victim: StringName, circumstances: Dictionary)

## Stances.
const FIGHT := &"fight"
const FLEE := &"flee"
const FETCH_HELP := &"fetch_help"
## Every stance, in input order.
const STANCES: Array[StringName] = [FIGHT, FLEE, FETCH_HELP]

## Who regards whom as hostile or friendly.
var disposition: BustleDispositionPort
## Where fights are carried out.
var combat: BustleCombatPort
## The numbers.
var config: BustleConflictConfig
## The world seed, for the lethal and quarrel rolls.
var world_seed: int = 0
## (id) → that agent's [BustlePersonality], or null (neutral sliders).
var personality_of: Callable = Callable()
## (id) → that agent's group (for the disposition port). Empty: no groups.
var group_of: Callable = Callable()
## (id) → that agent's position (a [Vector3]), or null. Empty: nobody has one, so allies can't be
## found and fleeing ends at once.
var position_of: Callable = Callable()

var _conflicts: Dictionary[StringName, Dictionary] = {}


func _init(p_disposition: BustleDispositionPort = null, p_combat: BustleCombatPort = null,
		p_config: BustleConflictConfig = null, p_world_seed: int = 0) -> void:
	disposition = p_disposition if p_disposition != null else BustleDispositionPort.new()
	combat = p_combat if p_combat != null else BustleCombatPort.new()
	config = p_config if p_config != null else BustleConflictConfig.new()
	world_seed = p_world_seed


## [param agent] notices [param other] at minute [param now]. Only when it regards [param other]
## as hostile does it take a stance, which it returns ([constant FIGHT], [constant FLEE] or
## [constant FETCH_HELP]; a fetcher picks the nearest ally in [param nearby]). Empty otherwise,
## or when it's already in a conflict.
## @experimental
func notice(agent: StringName, other: StringName, now: int, nearby: Array[StringName] = []) -> StringName:
	if agent == &"" or other == &"" or agent == other or _conflicts.has(agent):
		return &""
	if disposition.disposition(agent, _group(agent), other, _group(other)) != BustleDispositionPort.Disposition.HOSTILE:
		return &""
	return _begin(agent, other, &"hostile", now, nearby)


## [param a] quarrels with [param b] at minute [param now]. With a chance of
## [member BustleConflictConfig.quarrel_chance] scaled by [param a]'s temper, it becomes a scuffle:
## [param a] fights, and [param b] takes its own stance. Nobody becomes hostile. True when it did.
## @experimental
func quarrel(a: StringName, b: StringName, now: int, nearby: Array[StringName] = []) -> bool:
	if a == &"" or b == &"" or a == b or _conflicts.has(a):
		return false
	if _roll(["quarrel", a, b, now]) >= config.quarrel_chance * _slider(a, &"temper") / 100.0:
		return false
	_conflicts[a] = {"threat": String(b), "stance": String(FIGHT), "cause": "quarrel", "helper": ""}
	if not _conflicts.has(b):
		_begin(b, a, &"quarrel", now, nearby)
	return true


## The stance [param agent] takes against a threat: [constant FIGHT] when the average of its
## boldness and temper reaches [member BustleConflictConfig.fight_threshold], else
## [constant FETCH_HELP] when [param has_help], else [constant FLEE].
## @experimental
func stance_for(agent: StringName, has_help: bool) -> StringName:
	if (_slider(agent, &"boldness") + _slider(agent, &"temper")) / 2.0 >= config.fight_threshold:
		return FIGHT
	return FETCH_HELP if has_help else FLEE


## The nearest ally of [param agent] in [param nearby] within
## [member BustleConflictConfig.help_radius], not in a conflict of its own, or empty. An ally
## regards [param agent] as friendly, or shares its group without regarding it as hostile.
## @experimental
func nearest_ally(agent: StringName, nearby: Array[StringName], exclude: StringName = &"") -> StringName:
	var here: Variant = where(agent)
	if here == null:
		return &""
	var best: StringName = &""
	var best_distance := INF
	for other: StringName in nearby:
		if other == agent or other == exclude or other == &"" or _conflicts.has(other):
			continue
		var there: Variant = where(other)
		if there == null:
			continue
		var distance := (here as Vector3).distance_to(there)
		var view := disposition.disposition(other, _group(other), agent, _group(agent))
		var ally := view == BustleDispositionPort.Disposition.FRIENDLY \
				or (view != BustleDispositionPort.Disposition.HOSTILE and _group(agent) != &"" and _group(agent) == _group(other))
		if ally and distance <= config.help_radius and (distance < best_distance or (distance == best_distance and String(other) < String(best))):
			best = other
			best_distance = distance
	return best


## The agent [param agent] is in conflict with, or empty.
## @experimental
func threat_of(agent: StringName) -> StringName:
	return StringName(_conflicts[agent]["threat"]) if _conflicts.has(agent) else &""


## [param agent]'s stance, or empty.
## @experimental
func stance_of(agent: StringName) -> StringName:
	return StringName(_conflicts[agent]["stance"]) if _conflicts.has(agent) else &""


## The ally [param agent] is fetching, or empty.
## @experimental
func helper_of(agent: StringName) -> StringName:
	return StringName(_conflicts[agent]["helper"]) if _conflicts.has(agent) else &""


## Writes [param agent]'s stance into [param inputs]: 1 for its stance and 0 for the others, or
## no [code]threat.*[/code] stance inputs at all when it's in no conflict.
## @experimental
func fill_inputs(agent: StringName, inputs: Dictionary[StringName, float]) -> void:
	var stance := stance_of(agent)
	for each: StringName in STANCES:
		var key := StringName("threat." + String(each))
		if stance == &"":
			inputs.erase(key)
		else:
			inputs[key] = 1.0 if each == stance else 0.0


## [param helper] answers [param agent]'s call: it fights [param agent]'s threat, and
## [param agent] is out of the conflict. False when [param agent] has no threat or [param helper]
## is busy.
## @experimental
func call_help(helper: StringName, agent: StringName) -> bool:
	var threat := threat_of(agent)
	if threat == &"" or helper == &"" or helper == threat or _conflicts.has(helper):
		return false
	_conflicts[helper] = {"threat": String(threat), "stance": String(FIGHT), "cause": "help", "helper": ""}
	_conflicts.erase(agent)
	return true


## Whether [param attacker]'s fight with [param victim] at minute [param now] is lethal: a seeded
## roll against [member BustleConflictConfig.lethal_chance], the same every time.
## @experimental
func is_lethal(attacker: StringName, victim: StringName, now: int) -> bool:
	return _roll(["lethal", attacker, victim, now]) < config.lethal_chance


## [param damage] to a victim with [param health], as a fight should deal it: unchanged when
## [param lethal], else cut so the victim keeps at least
## [member BustleConflictConfig.scuffle_floor]. Never negative.
## @experimental
func filter_damage(damage: float, health: float, lethal: bool) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	if lethal:
		return damage
	return clampf(damage, 0.0, maxf(health - config.scuffle_floor, 0.0))


## Ends [param agent]'s fight at minute [param now] from the combat port's
## [method BustleCombatPort.outcome]: emits [signal assaulted], and [signal killed] when the
## target died, then clears the conflict and disengages.
## @experimental
func finish(agent: StringName, now: int, lethal: bool) -> void:
	var threat := threat_of(agent)
	var cause := String(_conflicts[agent]["cause"]) if _conflicts.has(agent) else ""
	var result := combat.outcome(agent)
	clear(agent)
	combat.disengage(agent)
	if threat == &"":
		return
	var circumstances := {"cause": cause, "lethal": lethal, "killed": bool(result.get("killed", false)), "at": now}
	assaulted.emit(agent, threat, circumstances)
	if circumstances["killed"]:
		killed.emit(agent, threat, circumstances)


## Ends [param agent]'s conflict without a fight (it got away, or the host ended it).
## @experimental
func clear(agent: StringName) -> void:
	_conflicts.erase(agent)


## The conflicts in progress as plain data.
## @experimental
func export_state() -> Dictionary:
	var out := {}
	for agent: StringName in _conflicts:
		out[String(agent)] = _conflicts[agent].duplicate()
	return {"conflicts": out}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("conflicts") is Dictionary:
		return false
	var staged: Dictionary[StringName, Dictionary] = {}
	var rows: Dictionary = saved["conflicts"]
	for key: Variant in rows:
		var row: Variant = rows[key]
		if not key is String or String(key).is_empty() or not row is Dictionary:
			return false
		for field: String in ["threat", "stance", "cause", "helper"]:
			if not (row as Dictionary).get(field) is String:
				return false
		if not STANCES.has(StringName(row["stance"])) or String(row["threat"]).is_empty():
			return false
		staged[StringName(key)] = {"threat": row["threat"], "stance": row["stance"], "cause": row["cause"], "helper": row["helper"]}
	_conflicts = staged
	return true


## The three CRITICAL goals: [code]fight[/code], [code]flee[/code] and [code]fetch_help[/code],
## each eligible only while its [code]threat.*[/code] input is 1, each running its one action.
## @experimental
static func goal_defs() -> Array[BustleGoalDef]:
	var out: Array[BustleGoalDef] = []
	for stance: StringName in STANCES:
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0), 0, 1, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		curve.add_point(Vector2(1, 1), 1, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		var consideration := BustleConsideration.new()
		consideration.input = StringName("threat." + String(stance))
		consideration.curve = curve
		var step := BustleActionStep.new()
		step.action = stance
		var sequence := BustleActionSequence.new()
		sequence.steps.append(step)
		var goal := BustleGoalDef.new()
		goal.id = stance
		goal.band = BustleBands.CRITICAL
		goal.min_score = 0.5
		goal.considerations.append(consideration)
		goal.sequence = sequence
		out.append(goal)
	return out


func _begin(agent: StringName, other: StringName, cause: StringName, _now: int, nearby: Array[StringName]) -> StringName:
	var ally := nearest_ally(agent, nearby, other)
	var stance := stance_for(agent, ally != &"")
	_conflicts[agent] = {"threat": String(other), "stance": String(stance), "cause": String(cause),
		"helper": String(ally) if stance == FETCH_HELP else ""}
	return stance


func _slider(agent: StringName, name: StringName) -> float:
	var found: Variant = personality_of.call(agent) if personality_of.is_valid() else null
	return (found as BustlePersonality).slider(name) if found is BustlePersonality else 50.0


func _group(agent: StringName) -> StringName:
	return StringName(str(group_of.call(agent))) if group_of.is_valid() else &""


## Where [param agent] is (a [Vector3]), or null when [member position_of] doesn't say.
## @experimental
func where(agent: StringName) -> Variant:
	var found: Variant = position_of.call(agent) if position_of.is_valid() else null
	return found if found is Vector3 else null


# 0 to 1, from the world seed and length-prefixed parts.
func _roll(parts: Array) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, world_seed)
	for part: Variant in parts:
		var text := str(part)
		bytes.append_array(("%d:%s|" % [text.length(), text]).to_utf8_buffer())
	var h := -3750763034362895579 # 0xcbf29ce484222325 as a signed 64-bit int
	for byte: int in bytes:
		h = (h ^ byte) * 1099511628211
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng.randf()
