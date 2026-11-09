# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAffordanceDef
extends Resource

## A kind of smart object, as data: what using it does to needs, its tags, how many can use it at
## once, how long a reservation holds and its price. A bed, a bench and a stall are each one def,
## placed many times as [BustleAffordance]s.
## @experimental

## Its id.
@export var id: StringName = &""
## Need → how much one use lowers it (and advertises to the scorer).
@export var relief: Dictionary[StringName, float] = {}
## Need → how much one use raises it (a side effect).
@export var adds: Dictionary[StringName, float] = {}
## Its tags (for tag multipliers, leisure kinds and mood curves).
@export var tags: Array[StringName] = []
## How many agents can use or hold it at once.
@export var capacity: int = 1
## How long a reservation holds, in game minutes, before it lapses.
@export var hold_minutes: int = 60
## What one use costs, in the trade port's unit. 0 is free. Not used when [member item] is set.
@export var price: int = 0
## When set, each use buys this item from the owner (or payee) through
## [method BustleTradePort.buy], at the port's price and from the host's stock, instead of paying
## [member price]. Empty: an ordinary priced use.
@export var item: StringName = &""
## For agents other than the owner: their scores are multiplied by this. 0 refuses them, 1 treats
## them like the owner. Only applies to an owned affordance.
@export_range(0.0, 1.0) var others_mult: float = 0.0


## True when it can be used: an id, finite non-negative effects, a capacity and hold of at least
## 1, a price of at least 0 and [member others_mult] within 0..1.
## @experimental
func is_valid() -> bool:
	if id == &"" or capacity < 1 or hold_minutes < 1 or price < 0 or not is_finite(others_mult) \
			or others_mult < 0.0 or others_mult > 1.0:
		return false
	for effects: Dictionary[StringName, float] in [relief, adds]:
		for amount: float in effects.values():
			if not is_finite(amount) or amount < 0.0:
				return false
	return true
