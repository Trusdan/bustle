# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConflict
extends RefCounted

## Fight, flee or fetch help, in the CRITICAL band. Nothing here is left to chance: every fight
## starts from a cause, and every intent to kill has a reason.
## [br][br]
## [b]Causes.[/b] An agent that [method notice]s someone it regards as hostile (by the disposition
## port, never by opinion) is in a conflict. A [method quarrel] the host starts comes to blows only
## when its provocation and the agent's grudge reach a threshold set by temper and mood. A fetched
## ally fights for whoever fetched it.
## [br][br]
## [b]Stances.[/b] Bold or hot-tempered agents fight; timid ones fetch a nearby ally, or flee.
## [method fill_inputs] writes the stance as the scorer's [code]threat.fight[/code],
## [code]threat.flee[/code] and [code]threat.fetch_help[/code] inputs, which the goals from
## [method goal_defs] read, and the [code]fight[/code], [code]flee[/code] and
## [code]fetch_help[/code] actions carry them out. When a conflict ends, its inputs go and the
## agent's usual goals (its schedule) win again.
## [br][br]
## [b]Intent.[/b] A fighter means to [constant SUBDUE] unless it has a reason to [constant KILL]:
## [code]defend_life[/code] (its threat means to kill it, and it is cornered or its life is
## threatened; checked again every fight tick, so a fight can escalate), or a reason the host gives
## through [member lethal_reason_of]. [signal intent_changed] reports every change with its reason.
## [br][br]
## [b]Events.[/b] Every fight that ends emits [signal assaulted], and one in which the target died
## also [signal killed], whatever the intent: a subdue fight can still kill. Each carries
## [code]{act, cause, cause_detail, intent, intent_reason, killed, at}[/code]. [code]act[/code] is
## a fixed id for the fight (attacker, victim and the minute it started); a host stores it on the
## wounds it causes, so a victim who dies later of them can be traced to the fight.
## @experimental

## [param attacker] fought [param victim]. See the class description for [param circumstances].
signal assaulted(attacker: StringName, victim: StringName, circumstances: Dictionary)
## [param victim] died in [param attacker]'s fight (after [signal assaulted]).
signal killed(attacker: StringName, victim: StringName, circumstances: Dictionary)
## [param agent]'s intent towards [param threat] changed to [param intent], for [param reason].
signal intent_changed(agent: StringName, threat: StringName, intent: StringName, reason: StringName)

## Stances.
const FIGHT := &"fight"
const FLEE := &"flee"
const FETCH_HELP := &"fetch_help"
## Every stance, in input order.
const STANCES: Array[StringName] = [FIGHT, FLEE, FETCH_HELP]
## Intents.
const SUBDUE := &"subdue"
const KILL := &"kill"
## The intent reason for killing in self-defence.
const DEFEND_LIFE := &"defend_life"
## The intent reason when there's no reason to kill.
const NO_REASON := &"none"

## Who regards whom as hostile or friendly.
var disposition: BustleDispositionPort
## Where fights are carried out.
var combat: BustleCombatPort
## Whose life is in danger.
var health: BustleHealthPort
## Opinions, for grudges. Null: nobody holds one.
var social: BustleSocialPort
## The numbers.
var config: BustleConflictConfig
## (id) → that agent's [BustlePersonality], or null (neutral sliders).
var personality_of: Callable = Callable()
## (id) → that agent's mood (anything with a [code]mood[/code] number), or null.
var mood_of: Callable = Callable()
## (id) → that agent's group (for the disposition port). Empty: no groups.
var group_of: Callable = Callable()
## (id) → that agent's position (a [Vector3]), or null. Empty: nobody has one, so allies can't be
## found and fleeing ends at once.
var position_of: Callable = Callable()
## (agent, threat) → true when [param agent] can't get away from [param threat]. Empty: never.
var cornered_of: Callable = Callable()
## (agent, threat, cause) → the host's reason for [param agent] to kill [param threat], or empty
## for none. Empty: the host never gives one.
var lethal_reason_of: Callable = Callable()

var _conflicts: Dictionary[StringName, Dictionary] = {}


func _init(p_disposition: BustleDispositionPort = null, p_combat: BustleCombatPort = null,
		p_config: BustleConflictConfig = null, p_health: BustleHealthPort = null) -> void:
	disposition = p_disposition if p_disposition != null else BustleDispositionPort.new()
	combat = p_combat if p_combat != null else BustleCombatPort.new()
	config = p_config if p_config != null else BustleConflictConfig.new()
	health = p_health if p_health != null else BustleHealthPort.new()


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
	return _begin(agent, other, &"hostile", {"disposition": "hostile"}, now, nearby, &"")


## [param a] quarrels with [param b] at minute [param now], provoked by [param provocation] (0 to
## 1, from the host: a harsh word, a shove). It comes to blows only when the provocation plus
## [method grudge] reaches [method quarrel_threshold]; then [param a] fights and [param b] takes its
## own stance. Nobody becomes hostile. True when it came to blows.
## @experimental
func quarrel(a: StringName, b: StringName, now: int, provocation: float, nearby: Array[StringName] = []) -> bool:
	if a == &"" or b == &"" or a == b or _conflicts.has(a) or not is_finite(provocation):
		return false
	var held := grudge(a, b)
	var threshold := quarrel_threshold(a)
	if clampf(provocation, 0.0, 1.0) + held < threshold:
		return false
	var detail := {"provocation": clampf(provocation, 0.0, 1.0), "grudge": held, "threshold": threshold}
	_begin(a, b, &"quarrel", detail, now, nearby, FIGHT)
	if not _conflicts.has(b):
		_begin(b, a, &"quarrel", detail, now, nearby, &"")
	return true


## How much [param a] holds against [param b], from 0 to 1: the sum of [param a]'s negative
## opinion entries about [param b] (most come from deeds) over
## [member BustleConflictConfig.grudge_scale].
## @experimental
func grudge(a: StringName, b: StringName) -> float:
	if social == null or config.grudge_scale <= 0.0:
		return 0.0
	var total := 0.0
	for entry: Dictionary in social.reasons(a, b, 1000):
		total += maxf(-float(entry.get("value", 0.0)), 0.0)
	return clampf(total / config.grudge_scale, 0.0, 1.0)


## What a quarrel must reach for [param agent] to come to blows: from the config's calm, middle and
## hot thresholds by its temper, lowered by a low mood.
## @experimental
func quarrel_threshold(agent: StringName) -> float:
	var temper := _slider(agent, &"temper")
	var base := lerpf(config.quarrel_threshold_calm, config.quarrel_threshold, temper / 50.0) if temper < 50.0 \
			else lerpf(config.quarrel_threshold, config.quarrel_threshold_hot, (temper - 50.0) / 50.0)
	var low := clampf((50.0 - _mood(agent)) / 50.0, 0.0, 1.0) if _mood(agent) >= 0.0 else 0.0
	return base * maxf(1.0 - config.quarrel_mood_scale * low, 0.0)


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


## [param agent]'s intent ([constant SUBDUE] or [constant KILL]), or empty when it's in no conflict.
## @experimental
func intent_of(agent: StringName) -> StringName:
	return StringName(_conflicts[agent]["intent"]) if _conflicts.has(agent) else &""


## Why [param agent] has its intent ([constant NO_REASON] for subduing), or empty.
## @experimental
func intent_reason_of(agent: StringName) -> StringName:
	return StringName(_conflicts[agent]["intent_reason"]) if _conflicts.has(agent) else &""


## The whole of [param agent]'s conflict as plain data (a copy), or empty.
## @experimental
func conflict_of(agent: StringName) -> Dictionary:
	return _conflicts[agent].duplicate(true) if _conflicts.has(agent) else {}


## Works out [param agent]'s intent again (see the class description), emitting
## [signal intent_changed] when it changed. Returns the intent, or empty with no conflict.
## @experimental
func update_intent(agent: StringName) -> StringName:
	if not _conflicts.has(agent):
		return &""
	var row := _conflicts[agent]
	var threat := StringName(row["threat"])
	var reason := _kill_reason(agent, threat, StringName(row["cause"]))
	var intent := KILL if reason != NO_REASON else SUBDUE
	if intent != StringName(row["intent"]) or reason != StringName(row["intent_reason"]):
		row["intent"] = String(intent)
		row["intent_reason"] = String(reason)
		intent_changed.emit(agent, threat, intent, reason)
	return intent


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


## [param helper] answers [param agent]'s call at minute [param now]: it fights [param agent]'s
## threat, whatever its own personality, and [param agent] is out of the conflict. False when
## [param agent] has no threat or [param helper] is busy.
## @experimental
func call_help(helper: StringName, agent: StringName, now: int) -> bool:
	var threat := threat_of(agent)
	if threat == &"" or helper == &"" or helper == threat or _conflicts.has(helper):
		return false
	_conflicts.erase(agent)
	_begin(helper, threat, &"help", {"for": String(agent)}, now, [], FIGHT)
	return true


## [param agent] gives up fetching help and flees instead.
## @experimental
func switch_to_flee(agent: StringName) -> void:
	if _conflicts.has(agent):
		_conflicts[agent]["stance"] = String(FLEE)
		_conflicts[agent]["helper"] = ""


## [param damage] to a victim with [param health], as a fight with [param intent] should deal it
## right away: unchanged for [constant KILL], else cut so the victim keeps at least
## [member BustleConflictConfig.scuffle_floor]. Never negative. A stopgap until a host's health
## system decides what blows do.
## @experimental
func filter_damage(damage: float, current_health: float, intent: StringName) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	if intent == KILL:
		return damage
	return clampf(damage, 0.0, maxf(current_health - config.scuffle_floor, 0.0))


## Ends [param agent]'s fight at minute [param now] from the combat port's
## [method BustleCombatPort.outcome]: emits [signal assaulted], and [signal killed] when the target
## died, then clears the conflict and disengages.
## @experimental
func finish(agent: StringName, now: int) -> void:
	var row := conflict_of(agent)
	var result := combat.outcome(agent)
	clear(agent)
	combat.disengage(agent)
	if row.is_empty():
		return
	var circumstances := {"act": row["act"], "cause": row["cause"], "cause_detail": row["cause_detail"],
		"intent": row["intent"], "intent_reason": row["intent_reason"],
		"killed": bool(result.get("killed", false)), "at": now}
	var victim := StringName(row["threat"])
	assaulted.emit(agent, victim, circumstances)
	if circumstances["killed"]:
		end_involving(victim)
		killed.emit(agent, victim, circumstances)


## Ends [param agent]'s conflict without a fight (it got away, or the host ended it).
## @experimental
func clear(agent: StringName) -> void:
	_conflicts.erase(agent)


## Ends [param agent]'s conflict and every conflict with [param agent] as the threat (for example
## when it dies or leaves).
## @experimental
func end_involving(agent: StringName) -> void:
	_conflicts.erase(agent)
	for other: StringName in _conflicts.keys():
		if StringName(_conflicts[other]["threat"]) == agent:
			_conflicts.erase(other)


## The conflicts in progress as plain data, by agent id in order.
## @experimental
func export_state() -> Dictionary:
	var ids: Array[StringName] = _conflicts.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var out := {}
	for agent: StringName in ids:
		out[String(agent)] = _conflicts[agent].duplicate(true)
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
		for field: String in ["threat", "stance", "cause", "helper", "intent", "intent_reason", "act"]:
			if not (row as Dictionary).get(field) is String:
				return false
		if not (row as Dictionary).get("cause_detail") is Dictionary or not STANCES.has(StringName(row["stance"])) \
				or not [String(SUBDUE), String(KILL)].has(row["intent"]) or String(row["threat"]).is_empty():
			return false
		staged[StringName(key)] = (row as Dictionary).duplicate(true)
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


## Where [param agent] is (a [Vector3]), or null when [member position_of] doesn't say.
## @experimental
func where(agent: StringName) -> Variant:
	var found: Variant = position_of.call(agent) if position_of.is_valid() else null
	return found if found is Vector3 else null


## The fixed id of [param attacker]'s fight with [param victim] that started at minute [param now].
## @experimental
static func act_id(attacker: StringName, victim: StringName, now: int) -> String:
	return "%d:%s|%d:%s|%d" % [String(attacker).length(), attacker, String(victim).length(), victim, now]


func _begin(agent: StringName, other: StringName, cause: StringName, detail: Dictionary, now: int,
		nearby: Array[StringName], forced: StringName) -> StringName:
	var ally := nearest_ally(agent, nearby, other) if forced == &"" else &""
	var stance := forced if forced != &"" else stance_for(agent, ally != &"")
	_conflicts[agent] = {"threat": String(other), "stance": String(stance), "cause": String(cause),
		"cause_detail": detail.duplicate(true), "helper": String(ally) if stance == FETCH_HELP else "",
		"intent": String(SUBDUE), "intent_reason": String(NO_REASON), "act": act_id(agent, other, now)}
	update_intent(agent)
	return stance


func _kill_reason(agent: StringName, threat: StringName, cause: StringName) -> StringName:
	if lethal_reason_of.is_valid():
		var given := StringName(str(lethal_reason_of.call(agent, threat, cause)))
		if given != &"":
			return given
	if threat_of(threat) == agent and intent_of(threat) == KILL \
			and (health.is_life_threatened(agent) or (cornered_of.is_valid() and bool(cornered_of.call(agent, threat)))):
		return DEFEND_LIFE
	return NO_REASON


func _slider(agent: StringName, name: StringName) -> float:
	var found: Variant = personality_of.call(agent) if personality_of.is_valid() else null
	return (found as BustlePersonality).slider(name) if found is BustlePersonality else 50.0


func _mood(agent: StringName) -> float:
	var found: Variant = mood_of.call(agent) if mood_of.is_valid() else null
	if not found is Object or found.get(&"mood") == null:
		return -1.0
	var value := float(found.get(&"mood"))
	return value if is_finite(value) else -1.0


func _group(agent: StringName) -> StringName:
	return StringName(str(group_of.call(agent))) if group_of.is_valid() else &""
