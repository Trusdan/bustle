# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSocialPort
extends RefCounted

## How agents feel about each other and what they know of each other's deeds. A host (or a bridge
## to a social engine) extends this and overrides every method. The standalone default has no
## opinions or relationship kinds, and keeps a small in-memory list of deeds: the actor and the
## named witnesses know a deed first-hand, and [method share_news] passes only first-hand deeds,
## one hop, so nothing spreads further on its own.
## @experimental

## The opinion everyone has of everyone in the default (0 to 100).
const NEUTRAL_OPINION := 50

# deed key → {actor, verb, target, place, first_hand: Array[StringName], knowers: Dictionary}
var _deeds: Dictionary = {}
var _next_deed: int = 1


## How [param a] regards [param b], from 0 to 100. Default: [constant NEUTRAL_OPINION].
## @experimental
func opinion(_a: StringName, _b: StringName) -> int:
	return NEUTRAL_OPINION


## The kinds of relationship between [param a] and [param b] (for example friend). Default: none.
## @experimental
func kinds_between(_a: StringName, _b: StringName) -> PackedStringArray:
	return PackedStringArray()


## Up to [param max] reasons behind [param a]'s opinion of [param b], each a dictionary. Default:
## none.
## @experimental
func reasons(_a: StringName, _b: StringName, _max: int = 3) -> Array[Dictionary]:
	return []


## Records that [param actor] did [param verb] to [param target] at [param place], seen by
## [param witnesses] (each a dictionary with an [code]id[/code]; entries without one are ignored).
## [param magnitude] is how much the deed moved the target (an interaction passes its outcome for
## the recipient), and [param return_magnitude] how much it moved the actor (the outcome for the
## initiator). A port that weighs deeds itself can use them; the default and the built-in store
## keep neither. Returns the deed's key, or empty when the actor or verb is empty.
## @experimental
func record_deed(actor: StringName, verb: StringName, target: StringName, place: StringName,
		witnesses: Array[Dictionary], _magnitude: float = 1.0, _return_magnitude: float = 0.0) -> StringName:
	if actor == &"" or verb == &"":
		return &""
	var key := StringName("deed_%d" % _next_deed)
	_next_deed += 1
	var knowers := {actor: true}
	for witness: Dictionary in witnesses:
		var id: Variant = witness.get("id")
		if (id is StringName or id is String) and String(id) != "":
			knowers[StringName(id)] = true
	_deeds[key] = {
		"actor": actor, "verb": verb, "target": target, "place": place,
		"first_hand": knowers.keys(), "knowers": knowers,
	}
	return key


## True when [param agent] knows the deed [param key]. Unknown keys: false.
## @experimental
func knows(agent: StringName, key: StringName) -> bool:
	return _deeds.has(key) and (_deeds[key]["knowers"] as Dictionary).has(agent)


## [param teller] tells [param listener] the deeds the teller knows first-hand and the listener
## doesn't know yet. Returns how many. The listener knows them second-hand, so can't pass them on.
## The default ignores [param _place].
## @experimental
func share_news(teller: StringName, listener: StringName, _place: StringName) -> int:
	if teller == &"" or listener == &"" or teller == listener:
		return 0
	var told := 0
	var keys: Array = _deeds.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for key: StringName in keys:
		var deed: Dictionary = _deeds[key]
		if (deed["first_hand"] as Array).has(teller) and not (deed["knowers"] as Dictionary).has(listener):
			(deed["knowers"] as Dictionary)[listener] = true
			told += 1
	return told
