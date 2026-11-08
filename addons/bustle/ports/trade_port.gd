# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTradePort
extends RefCounted

## Money and buying, in the host's smallest unit (whole numbers). A host extends this to use its
## own wallets and shops. The standalone default keeps in-memory balances and a price list. It
## never creates or loses money: a payment moves an exact positive amount between two different,
## named agents who can afford it, and anything else fails without changing a balance.
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


## [param id] buys [param item] from [param seller] at its listed price. False, changing nothing,
## when it has no price, the price is negative, or the payment fails. A price of 0 succeeds without
## moving money.
## @experimental
func buy(id: StringName, item: StringName, seller: StringName) -> bool:
	if not prices.has(item) or prices[item] < 0 or id == &"" or seller == &"" or id == seller:
		return false
	return true if prices[item] == 0 else pay(id, seller, prices[item])
