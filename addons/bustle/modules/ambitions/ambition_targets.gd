# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAmbitionTargets
extends RefCounted

## Who the courting and feud ambitions are about, from the society and its social port: fills the
## inputs [BustleAmbitions] reads for [code]court_someone[/code] and [code]settle_feud[/code].
## [br][br]
## [b]Courting[/b] ([code]court_target[/code]): another agent of the society in the same settlement
## ([member settlement_of]), not family
## ([member BustleAmbitionConfig.family_kinds]) and not gone for good ([member is_gone]), whose
## opinion is at least [member BustleAmbitionConfig.like_line]; the one it likes most, ties by id.
## The current target is kept while it still qualifies. [code]court_target_gone[/code] is set only
## when the current target is gone for good and nobody else qualifies; when someone else does,
## the ambition simply turns to them.
## [br][b]Feuds[/b] ([code]rival[/code]): someone it counts as a rival (the social port's
## [code]rival[/code] kind), not gone for good; the current one is kept, else the lowest opinion,
## ties by id. [code]rival_cleared[/code] once the current rival no longer has the rival kind, and
## [code]rival_gone[/code] once they're gone for good.
## @experimental

## The agents and the social port.
var society: BustleSociety
## The like line and family kinds.
var config: BustleAmbitionConfig
## (id) → true when that person is dead or gone for good. Empty: when they're no longer an agent
## of the society.
var is_gone: Callable = Callable()
## (id) → the settlement that agent lives in. Empty: its area.
var settlement_of: Callable = Callable()


func _init(p_society: BustleSociety = null, p_config: BustleAmbitionConfig = null) -> void:
	society = p_society if p_society != null else BustleSociety.new()
	config = p_config if p_config != null else BustleAmbitionConfig.new()


## Adds the courting and feud inputs for [param agent] to [param inputs], given its current
## ambition [param active] (from [method BustleAmbitions.active], or empty).
## @experimental
func fill(agent: StringName, active: Dictionary, inputs: Dictionary) -> void:
	var social := society.ports.social
	var current := StringName(str(active.get("target", "")))
	var courting: bool = active.get("id", "") == "court_someone"
	var court := current if courting and _can_court(agent, current) else court_target(agent)
	inputs["has_court_target"] = court != &""
	inputs["court_target_gone"] = courting and current != &"" and _gone(current) and court == &""
	if court != &"":
		inputs["court_target"] = String(court)
		inputs["court_opinion"] = float(social.opinion(agent, court))
		inputs["court_friend"] = social.kinds_between(agent, court).has("friend")
	var feuding: bool = active.get("id", "") == "settle_feud"
	var rival := current if feuding and current != &"" else rival_of(agent)
	inputs["has_rival"] = rival_of(agent) != &""
	if rival != &"":
		inputs["rival"] = String(rival)
		inputs["rival_opinion"] = float(social.opinion(agent, rival))
		inputs["rival_cleared"] = not social.kinds_between(agent, rival).has("rival")
		inputs["rival_gone"] = feuding and _gone(rival)


## The person [param agent] would court now, or empty (see the class notes).
## @experimental
func court_target(agent: StringName) -> StringName:
	var best := &""
	var best_opinion := 0.0
	for other: StringName in _known(agent):
		if not _can_court(agent, other):
			continue
		var opinion := float(society.ports.social.opinion(agent, other))
		if best == &"" or opinion > best_opinion or (opinion == best_opinion and String(other) < String(best)):
			best = other
			best_opinion = opinion
	return best


## [param agent]'s rival to settle with now, or empty: the lowest opinion among its rivals still
## here, ties by id.
## @experimental
func rival_of(agent: StringName) -> StringName:
	var social := society.ports.social
	var best := &""
	var best_opinion := 0.0
	for other: StringName in _known(agent):
		if _gone(other) or not social.kinds_between(agent, other).has("rival"):
			continue
		var opinion := float(social.opinion(agent, other))
		if best == &"" or opinion < best_opinion or (opinion == best_opinion and String(other) < String(best)):
			best = other
			best_opinion = opinion
	return best


func _can_court(agent: StringName, other: StringName) -> bool:
	if other == &"" or other == agent or _gone(other) or _settlement(other) != _settlement(agent):
		return false
	var social := society.ports.social
	for kind: String in social.kinds_between(agent, other):
		if config.family_kinds.has(StringName(kind)):
			return false
	return float(social.opinion(agent, other)) >= config.like_line


# The other agents of the society, by id.
func _known(agent: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for other: StringName in society.agent_ids():
		if other != agent:
			out.append(other)
	out.sort()
	return out


func _gone(id: StringName) -> bool:
	if is_gone.is_valid():
		return bool(is_gone.call(id))
	return society.get_agent(id) == null


func _settlement(id: StringName) -> StringName:
	if settlement_of.is_valid():
		return StringName(settlement_of.call(id))
	var state := society.get_agent(id)
	return state.area if state != null else &""
