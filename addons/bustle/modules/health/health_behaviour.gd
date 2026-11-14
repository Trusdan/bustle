# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthBehaviour
extends RefCounted

## The health behaviour: agents react to the host's health. The host owns bodies, harm, illness and
## treatment and reports them through [BustleHealthPort]; this reads the port each tick and keeps
## nothing of its own, so no wound, illness or body state lives in Bustle.
## [br][br]
## [method tick] (or its three parts) for each agent:
## [br]- [method apply]: capacities below full scale modifier keys by [member BustleHealthConfig.effects]
## ([code]work.speed[/code], [code]move.speed[/code], and [code]capacity.<name>[/code]), under
## source [constant SOURCE]. At full health nothing is written.
## [br]- [method sync]: holds the pain thought for the current pain and a tag thought for each
## visible tag, and drops the rest, so they clear when the port does.
## [br]- [method fill_inputs]: [code]health.pain[/code], [code]health.needs_care[/code],
## [code]fact.downed[/code] and [code]fact.contagious[/code], set only while non-zero.
## [br][br]
## A downed agent ([method BustleHealthPort.is_incapacitated]) chooses no work and doesn't travel:
## set [member BustleBrain.gate] to [method allows]. With the default port everyone is healthy and a
## tick does nothing. Nothing is random: the same readings give the same results.
## @experimental

## The modifier source its effects are set under.
const SOURCE := &"health"
## The pain input, 0 to 1.
const INPUT_PAIN := &"health.pain"
## The care input: how urgently care is needed, 0 to 1.
const INPUT_CARE := &"health.needs_care"
## 1 while downed.
const INPUT_DOWNED := &"fact.downed"
## 1 while contagious.
const INPUT_CONTAGIOUS := &"fact.contagious"

## The effects, thoughts and downed blocks. Invalid ones ([method BustleHealthConfig.validate])
## make the behaviour do nothing.
var config: BustleHealthConfig
## The ports it reads: [code]health[/code]. Null: everyone is healthy.
var ports: BustlePorts


## Starts with [param p_config] (the experimental defaults when null), reading [param p_ports].
func _init(p_config: BustleHealthConfig = null, p_ports: BustlePorts = null) -> void:
	config = p_config if p_config != null else BustleHealthConfig.defaults()
	ports = p_ports


## [param id]'s amount of capacity [param name], clamped to 0..1 (1 with no port or an unusable
## reading).
## @experimental
func capacity(id: StringName, name: StringName) -> float:
	var port := _port()
	return _unit(port.capacity(id, name), 1.0) if port != null else 1.0


## [param id]'s pain, clamped to 0..1.
## @experimental
func pain(id: StringName) -> float:
	var port := _port()
	return _unit(port.pain(id), 0.0) if port != null else 0.0


## True while [param id] is downed.
## @experimental
func is_downed(id: StringName) -> bool:
	var port := _port()
	return port != null and port.is_incapacitated(id)


## Applies [param id]'s capacities to [param modifiers]: it removes what [constant SOURCE] wrote
## before, then writes [code]capacity.<name>[/code] and each effect's key for capacities below
## full (effects on one key multiply). Nothing is written at full health.
## @experimental
func apply(id: StringName, modifiers: BustleModifierSet) -> void:
	if modifiers == null:
		return
	modifiers.remove_source(SOURCE)
	if config.validate() != "":
		return
	var mults: Dictionary[StringName, float] = {}
	var names: Array[StringName] = []
	for effect: BustleHealthEffect in config.effects:
		var amount := capacity(id, effect.capacity)
		if amount < 1.0:
			mults[effect.key] = mults.get(effect.key, 1.0) * effect.mult(amount)
			if not names.has(effect.capacity):
				names.append(effect.capacity)
	for name: StringName in names:
		var key := StringName("capacity." + String(name))
		if BustleModifierSet.is_valid_key(key):
			modifiers.set_source(SOURCE, key, 0.0, capacity(id, name))
	for key: StringName in mults:
		modifiers.set_source(SOURCE, key, 0.0, mults[key])


## The thought rules [param id] meets now: the pain rule with the highest line its pain reaches,
## then each tag rule whose tag it shows, in rule order.
## @experimental
func chosen(id: StringName) -> Array[BustleHealthThought]:
	var out: Array[BustleHealthThought] = []
	if config.validate() != "":
		return out
	var amount := pain(id)
	var port := _port()
	var tags: Array[StringName] = port.visible_tags(id) if port != null else ([] as Array[StringName])
	var by_pain: BustleHealthThought = null
	for rule: BustleHealthThought in config.thoughts:
		if not is_nan(rule.pain_at_least) and amount >= rule.pain_at_least \
				and (by_pain == null or rule.pain_at_least > by_pain.pain_at_least):
			by_pain = rule
	if by_pain != null:
		out.append(by_pain)
	for rule: BustleHealthThought in config.thoughts:
		if rule.tag != &"" and tags.has(rule.tag) and not out.has(rule):
			out.append(rule)
	return out


## Brings [param id]'s health thoughts in line with the port on [param mood] (anything with
## [code]set_held(def, held, details)[/code], such as a [code]BustleMood[/code]; optional): it
## drops every rule thought not chosen, then holds the chosen ones with [code]pain[/code] or
## [code]tag[/code] in their reason. Returns the chosen thought ids, in rule order.
## @experimental
func sync(id: StringName, mood: Object = null) -> Array[StringName]:
	var rules := chosen(id)
	var ids: Array[StringName] = []
	for rule: BustleHealthThought in rules:
		ids.append(rule.thought.id)
	if mood == null or not mood.has_method(&"set_held") or config.validate() != "":
		return ids
	for rule: BustleHealthThought in config.thoughts:
		if not rules.has(rule) and not ids.has(rule.thought.id) \
				and (not mood.has_method(&"count") or int(mood.call(&"count", rule.thought.id)) > 0):
			mood.call(&"set_held", rule.thought, false, {})
	for rule: BustleHealthThought in rules:
		var details := {"pain": pain(id)} if rule.tag == &"" else {"tag": String(rule.tag)}
		mood.call(&"set_held", rule.thought, true, details)
	return ids


## Sets [param id]'s health inputs in [param inputs], each only while non-zero, and erases them
## otherwise: [constant INPUT_PAIN], [constant INPUT_CARE], [constant INPUT_DOWNED] and
## [constant INPUT_CONTAGIOUS].
## @experimental
func fill_inputs(id: StringName, inputs: Dictionary[StringName, float]) -> void:
	for key: StringName in [INPUT_PAIN, INPUT_CARE, INPUT_DOWNED, INPUT_CONTAGIOUS]:
		inputs.erase(key)
	var port := _port()
	if port == null:
		return
	var values := {INPUT_PAIN: pain(id), INPUT_CARE: _unit(port.needs_care(id), 0.0),
		INPUT_DOWNED: 1.0 if port.is_incapacitated(id) else 0.0, INPUT_CONTAGIOUS: 1.0 if port.is_contagious(id) else 0.0}
	for key: StringName in values:
		if values[key] > 0.0:
			inputs[key] = values[key]


## One tick for [param id]: [method apply] on [param modifiers], [method sync] on [param mood] and
## [method fill_inputs] on [param inputs] (each skipped when null).
## @experimental
func tick(id: StringName, modifiers: BustleModifierSet, mood: Object = null, inputs: Variant = null) -> void:
	apply(id, modifiers)
	sync(id, mood)
	if inputs is Dictionary:
		fill_inputs(id, inputs)


## The gate for [member BustleBrain.gate]: false while [param id] is downed and the goal
## ([param goal_tags]: its id and tags) or option ([param option_tags]) carries any of
## [member BustleHealthConfig.downed_blocks]. True otherwise.
## @experimental
func allows(id: StringName, goal_tags: Array[StringName], option_tags: Array[StringName]) -> bool:
	if not is_downed(id):
		return true
	for tag: StringName in config.downed_blocks:
		if goal_tags.has(tag) or option_tags.has(tag):
			return false
	return true


func _port() -> BustleHealthPort:
	return ports.health if ports != null else null


static func _unit(value: float, fallback: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else fallback
