# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePropertyPort
extends RefCounted

## Who owns which things, and where they are. A host extends this to use its own items. The
## standalone default keeps an in-memory register.
## [br][br]
## An item is a plain record: [code]{id, owner_id, place, relieves, protected}[/code], where
## [code]relieves[/code] is need → amount (what having it would ease) and [code]protected[/code]
## marks something that can never be taken (a host marks its own: keepsakes, things a story needs).
## [method transfer] only ever moves an existing item from its owner to someone else; nothing here
## creates or destroys an item.
## @experimental

var _items: Dictionary[StringName, Dictionary] = {}


## Registers [param id], owned by [param owner_id] at [param place]. False (nothing changes) when
## the id or owner is empty, the id is taken, or [param relieves] isn't need → finite amount.
## @experimental
func register(id: StringName, owner_id: StringName, place: StringName, relieves: Dictionary = {},
		protected: bool = false) -> bool:
	if id == &"" or owner_id == &"" or _items.has(id) or not _valid_relief(relieves):
		return false
	var relief := {}
	for need: Variant in relieves:
		relief[String(need)] = float(relieves[need])
	_items[id] = {"id": String(id), "owner_id": String(owner_id), "place": String(place), "relieves": relief,
		"protected": protected}
	return true


## [param id]'s record (a copy), or empty when unknown.
## @experimental
func item(id: StringName) -> Dictionary:
	return _items[id].duplicate(true) if _items.has(id) else {}


## Who owns [param id], or empty when unknown.
## @experimental
func owner_of(id: StringName) -> StringName:
	return StringName(_items[id]["owner_id"]) if _items.has(id) else &""


## The records of every item at [param place], by id.
## @experimental
func items_at(place: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _sorted_ids():
		if StringName(_items[id]["place"]) == place:
			out.append(_items[id].duplicate(true))
	return out


## The records of every item [param owner_id] owns, wherever they are, by id.
## @experimental
func items_of(owner_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _sorted_ids():
		if StringName(_items[id]["owner_id"]) == owner_id:
			out.append(_items[id].duplicate(true))
	return out


## True when [param id] can never be taken.
## @experimental
func is_protected(id: StringName) -> bool:
	return _items.has(id) and bool(_items[id]["protected"])


## Marks [param id] protected (or not). False when unknown.
## @experimental
func set_protected(id: StringName, protected: bool) -> bool:
	if not _items.has(id):
		return false
	_items[id]["protected"] = protected
	return true


## Moves [param id] from [param from] to [param to]. Only the owner changes: the item stays at its
## place until the host moves it. False, changing nothing, when the item is
## unknown, protected, not owned by [param from], or [param to] is empty or [param from].
## @experimental
func transfer(id: StringName, from: StringName, to: StringName) -> bool:
	if not _items.has(id) or is_protected(id) or owner_of(id) != from or to == &"" or to == from:
		return false
	_items[id]["owner_id"] = String(to)
	return true


## The register as plain data, by id.
## @experimental
func export_state() -> Dictionary:
	var items: Array = []
	for id: StringName in _sorted_ids():
		items.append(_items[id].duplicate(true))
	return {"items": items}


## Restores [method export_state]. False (and nothing changes) when malformed.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("items") is Array:
		return false
	var staged: Dictionary[StringName, Dictionary] = {}
	for row: Variant in saved["items"]:
		if not row is Dictionary:
			return false
		for field: String in ["id", "owner_id", "place"]:
			if not (row as Dictionary).get(field) is String:
				return false
		var id := StringName(row["id"])
		if id == &"" or String(row["owner_id"]).is_empty() or staged.has(id) \
				or not (row as Dictionary).get("protected") is bool or not _valid_relief(row.get("relieves")):
			return false
		staged[id] = {"id": row["id"], "owner_id": row["owner_id"], "place": row["place"],
			"relieves": (row["relieves"] as Dictionary).duplicate(), "protected": row["protected"]}
	_items = staged
	return true


func _sorted_ids() -> Array[StringName]:
	var ids: Array[StringName] = _items.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


static func _valid_relief(relieves: Variant) -> bool:
	if not relieves is Dictionary:
		return false
	for need: Variant in relieves:
		var amount: Variant = relieves[need]
		if not (need is String or need is StringName) or String(need).is_empty() \
				or not (amount is float or amount is int) or not is_finite(float(amount)):
			return false
	return true
