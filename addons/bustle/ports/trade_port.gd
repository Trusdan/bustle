# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTradePort
extends RefCounted

## Money and buying, in one abstract unit (whole numbers): what the unit is, and any currencies
## behind it, is the host's business. A host extends this to use its own wallets and shops. The
## standalone default keeps in-memory balances and a price list. It never creates or loses money:
## a payment moves an exact positive amount between two different, named agents who can afford it,
## and anything else fails without changing a balance.
## [br][br]
## Stock belongs to the host: the default sells any listed item without limit. A host that keeps
## stock (or lends credit) overrides [method can_buy] and [method buy] together, so an item is only
## offered when [method buy] would go through, and [method can_take] and [method take] together for
## an owner using its own stock.
## @experimental

## Item id → price, for the default's [method buy]. An item not listed can't be bought.
var prices: Dictionary[StringName, int] = {}

var _balances: Dictionary[StringName, int] = {}


## What [param id] has. 0 for an unknown agent.
## @experimental
func balance(id: StringName) -> int:
	return _balances.get(id, 0)


## Sets what [param id] has (the default's data). False for an empty id or a negative amount.
## @experimental
func set_balance(id: StringName, amount: int) -> bool:
	if id == &"" or amount < 0:
		return false
	_balances[id] = amount
	return true


## Moves [param amount] from [param from] to [param to]. False, changing nothing, when the amount
## isn't positive, an id is empty, they are the same, or [param from] can't afford it.
## @experimental
func pay(from: StringName, to: StringName, amount: int) -> bool:
	if amount <= 0 or from == &"" or to == &"" or from == to or balance(from) < amount:
		return false
	_balances[from] = balance(from) - amount
	_balances[to] = balance(to) + amount
	return true


## What [param item] costs from [param seller], or -1 when it isn't sold. Default: its listed
## price, -1 when unlisted or negative.
## @experimental
func price_of(item: StringName, _seller: StringName) -> int:
	var price: int = prices.get(item, -1)
	return price if price >= 0 else -1


## True when [method buy] would go through: [param item] is sold, the ids are two different named
## agents, and [param id] can pay [method price_of]. It changes nothing.
## @experimental
func can_buy(id: StringName, item: StringName, seller: StringName) -> bool:
	var price := price_of(item, seller)
	return price >= 0 and id != &"" and seller != &"" and id != seller and balance(id) >= price


## [param id] buys [param item] from [param seller] at [method price_of]. False, changing nothing,
## when [method can_buy] says no. A price of 0 succeeds without moving money.
## @experimental
func buy(id: StringName, item: StringName, seller: StringName) -> bool:
	if not can_buy(id, item, seller):
		return false
	var price := price_of(item, seller)
	return true if price == 0 else pay(id, seller, price)


## True when [method take] would go through: [param id] may take one [param item] from its own
## stock. It changes nothing. Default: any named agent may, for any item.
## @experimental
func can_take(id: StringName, _item: StringName) -> bool:
	return id != &""


## [param id] takes one [param item] from its own stock, without paying: no money moves. False,
## changing nothing, when [method can_take] says no. A host that keeps stock takes one off here.
## @experimental
func take(id: StringName, item: StringName) -> bool:
	return can_take(id, item)


## The default's balances as plain data (ids → amounts). Prices are configuration, not saved.
## @experimental
func export_state() -> Dictionary:
	var ids: Array[StringName] = _balances.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var balances := {}
	for id: StringName in ids:
		balances[String(id)] = _balances[id]
	return {"balances": balances}


## Restores [method export_state]. False (and nothing changes) when malformed: not a dictionary, an
## empty id, or an amount that isn't a whole number of at least 0.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not (saved as Dictionary).get("balances") is Dictionary:
		return false
	var staged: Dictionary[StringName, int] = {}
	var balances: Dictionary = saved["balances"]
	for key: Variant in balances:
		var amount: Variant = balances[key]
		if amount is float and is_finite(amount) and amount == floorf(amount) and absf(amount) < 9.0e15:
			amount = int(amount)
		if not key is String or String(key).is_empty() or not amount is int or int(amount) < 0:
			return false
		staged[StringName(key)] = amount
	_balances = staged
	return true
