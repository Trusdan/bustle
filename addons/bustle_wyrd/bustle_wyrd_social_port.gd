# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWyrdSocialPort
extends BustleSocialPort

## The social port, answered by Wyrd. Installed by [method BustleWyrdBridge.install], it replaces
## the default port and the built-in [BustleSocialStore] (and with it [BustleRelationshipRules]), so
## Wyrd is the one source of opinions, relationship kinds, deeds and what each agent knows of them.
##
## @experimental
## Every call goes to Wyrd by name, so this script compiles with no Wyrd in the project.
## [method record_deed] uses Wyrd's stable [code]deeds.record[/code]. The reads use Wyrd's
## experimental surface, which [method BustleWyrdBridge.is_supported] pins to one exact release:
## [code]social.disposition[/code] for opinions, the kinds Wyrd's social state stores, and the deed
## log's rows for knowledge and reasons. [method share_news] passes first-hand deeds one hop by
## noting the listener as a believer of each, with no roll. A deed's key is
## [code]deed_<Wyrd deed id>[/code]. Ids are opaque: an actor, target or witness needn't be an agent.

## The start of every deed key this port returns.
const KEY_PREFIX := "deed_"

var _wyrd: Object


## A port over [param wyrd]: Wyrd's facade, or anything with the same members.
func _init(wyrd: Object = null) -> void:
	_wyrd = wyrd


## How [param a] regards [param b], from 0 to 100: Wyrd's disposition of [param a] toward
## [param b]. [constant BustleSocialPort.NEUTRAL_OPINION] when either id is empty.
## @experimental
func opinion(a: StringName, b: StringName) -> int:
	var social := _member(&"social")
	if social == null or a == &"" or b == &"":
		return NEUTRAL_OPINION
	return clampi(int(social.call(&"disposition", a, b)), 0, 100)


## The kinds of relationship [param a] holds toward [param b] in Wyrd, sorted.
## @experimental
func kinds_between(a: StringName, b: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var social := _member(&"social")
	if social == null or a == &"" or b == &"":
		return out
	var state: Dictionary = social.call(&"export_state")
	for row: Variant in state.get("kinds", []):
		if row is Dictionary and str(row.get("source", "")) == String(a) and str(row.get("target", "")) == String(b):
			out.append(str(row.get("kind", "")))
	out.sort()
	return out


## Up to [param limit] of the deeds behind [param a]'s opinion of [param b], newest first: the deeds
## [param b] did that [param a] was the target or a witness of, which are the deeds Wyrd's
## disposition counts. Each is [code]{deed, verb, minute, as}[/code], where [code]as[/code] is
## [code]target[/code] or [code]witness[/code].
## @experimental
func reasons(a: StringName, b: StringName, limit: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var deeds := _member(&"deeds")
	if deeds == null or a == &"" or b == &"" or a == b or limit <= 0:
		return out
	var rows: PackedInt32Array = deeds.call(&"actor_indexes", b)
	for i: int in range(rows.size() - 1, -1, -1):
		var row := rows[i]
		var as_target: bool = deeds.call(&"target_at", row) == a
		if not as_target and not deeds.call(&"witnessed", row, a):
			continue
		out.append({
			"deed": key_of(int(deeds.call(&"id_at", row))), "verb": deeds.call(&"verb_at", row),
			"minute": int(deeds.call(&"minute_at", row)), "as": &"target" if as_target else &"witness",
		})
		if out.size() >= limit:
			break
	return out


## Records the deed in Wyrd ([code]deeds.record[/code]) with the witnesses' ids as an explicit
## list. Returns its key, or empty when the actor or verb is empty or Wyrd refuses it.
## @experimental
func record_deed(actor: StringName, verb: StringName, target: StringName, place: StringName,
		witnesses: Array[Dictionary]) -> StringName:
	var deeds := _member(&"deeds")
	if deeds == null or actor == &"" or verb == &"":
		return &""
	var ids := PackedStringArray()
	for witness: Dictionary in witnesses:
		var id: Variant = witness.get("id")
		if (id is StringName or id is String) and String(id) != "" and not ids.has(String(id)):
			ids.append(String(id))
	var deed_id := int(deeds.call(&"record", verb, actor, target, place, PackedStringArray(), 1.0, ids))
	return key_of(deed_id) if deed_id > 0 else &""


## True when [param agent] knows the deed [param key]: it did the deed, witnessed it, or believes it
## (from [method share_news] or one of Wyrd's rumours). False for an unknown key, or one Wyrd has
## since merged away by compacting its log.
## @experimental
func knows(agent: StringName, key: StringName) -> bool:
	var deeds := _member(&"deeds")
	var deed_id := id_of(key)
	if deeds == null or agent == &"" or deed_id <= 0:
		return false
	var row := int(deeds.call(&"index_of", deed_id))
	if row < 0:
		return false
	if deeds.call(&"actor_at", row) == agent or deeds.call(&"witnessed", row, agent):
		return true
	return (deeds.call(&"believer_index", agent) as Dictionary).has(deed_id)


## [param teller] tells [param listener] the deeds the teller knows first-hand (did or witnessed)
## and the listener doesn't know yet, oldest first. Each is noted in Wyrd as believed by the
## listener at Wyrd's current minute, so the listener knows it second-hand and can't pass it on.
## Returns how many. [param _place] is not used.
## @experimental
func share_news(teller: StringName, listener: StringName, _place: StringName) -> int:
	var deeds := _member(&"deeds")
	if deeds == null or teller == &"" or listener == &"" or teller == listener:
		return 0
	var rows := {}
	for row: int in deeds.call(&"actor_indexes", teller):
		rows[row] = true
	for row: int in deeds.call(&"witness_indexes", teller):
		rows[row] = true
	var order: Array = rows.keys()
	order.sort()
	var now := int(_wyrd.call(&"now_minutes")) if _wyrd.has_method(&"now_minutes") else 0
	var told := 0
	for row: int in order:
		var deed_id := int(deeds.call(&"id_at", row))
		if knows(listener, key_of(deed_id)):
			continue
		deeds.call(&"note_believer", deed_id, listener, now)
		told += 1
	return told


## The key of Wyrd deed [param deed_id].
## @experimental
static func key_of(deed_id: int) -> StringName:
	return StringName(KEY_PREFIX + str(deed_id))


## The Wyrd deed id in [param key], or 0 when it isn't one of this port's keys.
## @experimental
static func id_of(key: StringName) -> int:
	var text := String(key)
	if not text.begins_with(KEY_PREFIX) or not text.substr(KEY_PREFIX.length()).is_valid_int():
		return 0
	return int(text.substr(KEY_PREFIX.length()))


func _member(member: StringName) -> Object:
	return _wyrd.get(member) as Object if _wyrd != null else null
