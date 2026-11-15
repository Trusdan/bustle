# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDirectorEffects
extends RefCounted

## Applies a fired event's [member BustleEventDef.effects], in order, to exactly the targets each
## names ([BustleEventEffect]). The host supplies who exists and how to reach them through the
## callables below; spawns go only through [method BustleWorldPort.request_spawn]. It keeps nothing.
## Set it as [member BustleDirector.effects].

## One effect was applied: [param target] is the agent (or, for a spawn, the area), [param what]
## the thought, order or spawn kind, and [param done] whether it took (a mood that took the
## thought, a brain that queued the order, a host that made the spawn).
signal applied(event: StringName, kind: StringName, target: StringName, what: StringName, done: bool)

## The ports: [code]world[/code] for areas and spawn requests.
var ports: BustlePorts
## [code]func() -> Array[StringName][/code]: every agent. Unset: only agents named by id.
var agents: Callable = Callable()
## [code]func(id) -> Array[StringName][/code]: an agent's tags. Unset: no tags.
var tags_of: Callable = Callable()
## [code]func(id) -> Object[/code]: an agent's mood (with [code]add_thought(def, details)[/code]), or null.
var mood_of: Callable = Callable()
## [code]func(id) -> BustleBrain[/code]: an agent's brain, or null.
var brain_of: Callable = Callable()


func _init(p_ports: BustlePorts = null) -> void:
	ports = p_ports


## The agents [param effect] targets, in id order: those named, those tagged, those in the area.
## Named agents count only when [member agents] lists them (or [member agents] is unset).
func targets(effect: BustleEventEffect) -> Array[StringName]:
	var known: Array[StringName] = []
	if agents.is_valid():
		known.assign(agents.call())
	var out: Array[StringName] = []
	for id: StringName in effect.target_ids:
		if (not agents.is_valid() or known.has(id)) and not out.has(id):
			out.append(id)
	for id: StringName in known:
		if out.has(id):
			continue
		var tags: Array = tags_of.call(id) if tags_of.is_valid() else []
		var by_tag := effect.target_tag != &"" and tags.has(effect.target_tag)
		var by_area := effect.target_area != &"" and ports != null and ports.world.area_of(id) == effect.target_area
		if by_tag or by_area:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Applies [param def]'s effects as fired at [param now], emitting [signal applied] for each, and
## returns them as [code]{event, kind, target, what, done}[/code] records, in order. An order's id is
## [code]<event>.<minute>[/code] for the event's first order effect, and
## [code]<event>.<minute>.<index>[/code] (the effect's index in [member BustleEventDef.effects]) for
## each later one, so several order effects in one event can all reach the same agent.
func apply(def: BustleEventDef, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var first_order := -1
	for index: int in def.effects.size():
		var effect := def.effects[index]
		if effect.kind == BustleEventEffect.ORDER and first_order < 0:
			first_order = index
		if effect.kind == BustleEventEffect.SPAWN:
			var done := ports != null and ports.world.request_spawn(effect.spawn_kind, effect.spawn_area, effect.count, def.id)
			out.append(_note(def.id, effect.kind, effect.spawn_area, effect.spawn_kind, done))
			continue
		for id: StringName in targets(effect):
			if effect.kind == BustleEventEffect.THOUGHT:
				var mood: Variant = mood_of.call(id) if mood_of.is_valid() else null
				var took := mood is Object and (mood as Object).has_method(&"add_thought") \
						and bool((mood as Object).call(&"add_thought", effect.thought, {"event": String(def.id)}))
				out.append(_note(def.id, effect.kind, id, effect.thought.id, took))
			else:
				var brain: Variant = brain_of.call(id) if brain_of.is_valid() else null
				var order := BustleOrder.new(_order_id(def.id, now, index, first_order), effect.sequence)
				order.place = effect.place
				var queued := brain is BustleBrain and (brain as BustleBrain).order(order) == &""
				out.append(_note(def.id, effect.kind, id, order.id, queued))
	return out


# The order id: [code]<event>.<minute>[/code] for the event's first order effect, and
# [code]<event>.<minute>.<index>[/code] for each later one, so they can all queue on one agent.
static func _order_id(event: StringName, now: int, index: int, first_order: int) -> StringName:
	if index == first_order:
		return StringName("%s.%d" % [event, now])
	return StringName("%s.%d.%d" % [event, now, index])


func _note(event: StringName, kind: StringName, target: StringName, what: StringName, done: bool) -> Dictionary:
	applied.emit(event, kind, target, what, done)
	return {"event": event, "kind": kind, "target": target, "what": what, "done": done}
