# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAffordance
extends RefCounted

## One placed smart object: a [BustleAffordanceDef] at a place, perhaps owned. It advertises to
## agents ([method advertise]) and is used through reservations:
## [method reserve] → the host walks the agent there and plays the use → [method use], which
## applies the def's need effects (leisure scaled by tolerance), takes payment and releases.
## [br][br]
## [b]Capacity:[/b] at most [member BustleAffordanceDef.capacity] agents hold it at once; a
## reservation lapses after [member BustleAffordanceDef.hold_minutes]. [b]Ownership:[/b] an owned
## affordance scores others at [member BustleAffordanceDef.others_mult] (0 refuses them), unless
## [member access_hook] says otherwise. [b]Cost:[/b] each use costs [member cost_hook]'s price
## (the def's price by default; free to the owner), paid to the owner (or [member payee]) through
## a [BustleTradePort]. [b]Buying:[/b] when the def names an [member BustleAffordanceDef.item],
## each use buys it from the owner (or payee) with [method BustleTradePort.buy] instead, offered
## only while [method BustleTradePort.can_buy] says yes; the owner takes it without buying. Time
## is whole game minutes, given by the caller.
## @experimental

## Why [method reserve] or [method use] said no.
const REFUSED_ACCESS := &"no_access"
## Every place is held by someone else.
const REFUSED_FULL := &"full"
## The agent can't pay.
const REFUSED_PRICE := &"cannot_pay"
## A use that went through.
const OK := &"ok"

## Its id (unique among placed affordances).
var id: StringName = &""
## What it is.
var def: BustleAffordanceDef
## Its area.
var area: StringName = &""
## Where it is in its area.
var position := Vector3.ZERO
## Its owner, or empty for anyone's.
var owner: StringName = &""
## Who is paid when nobody owns it, or empty (then a priced use can't be paid).
var payee: StringName = &""
## (agent id, affordance) → a multiplier from 0 (refused) to 1. Empty: the ownership rule above.
var access_hook: Callable = Callable()
## (agent id, affordance) → the price of one use. Empty: the def's price, 0 for the owner.
var cost_hook: Callable = Callable()

var _holds: Dictionary[StringName, int] = {}


func _init(p_id: StringName = &"", p_def: BustleAffordanceDef = null, p_area: StringName = &"", p_position := Vector3.ZERO) -> void:
	id = p_id
	def = p_def if p_def != null else BustleAffordanceDef.new()
	area = p_area
	position = p_position


## How welcome [param agent] is, from 0 (refused) to 1. Results that aren't finite count as 0.
## @experimental
func access(agent: StringName) -> float:
	var out := 1.0
	if access_hook.is_valid():
		out = float(access_hook.call(agent, self))
	elif owner != &"" and agent != owner:
		out = def.others_mult
	return clampf(out, 0.0, 1.0) if is_finite(out) else 0.0


## What one use costs [param agent]. Never negative.
## @experimental
func price_for(agent: StringName) -> int:
	if cost_hook.is_valid():
		return maxi(int(cost_hook.call(agent, self)), 0)
	return 0 if owner != &"" and agent == owner else maxi(def.price, 0)


## The agents holding it at minute [param now] (lapsed holds are dropped), sorted.
## @experimental
func holders(now: int) -> Array[StringName]:
	_lapse(now)
	var out: Array[StringName] = _holds.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## True when [param agent] holds it at minute [param now].
## @experimental
func is_held_by(agent: StringName, now: int) -> bool:
	_lapse(now)
	return _holds.has(agent)


## True when a place is free (or [param agent] already holds one) at minute [param now].
## @experimental
func has_room(agent: StringName, now: int) -> bool:
	_lapse(now)
	return _holds.has(agent) or _holds.size() < def.capacity


## Holds a place for [param agent] from minute [param now] for the def's hold time (holding again
## renews it). Returns [constant OK], [constant REFUSED_ACCESS] or [constant REFUSED_FULL].
## @experimental
func reserve(agent: StringName, now: int) -> StringName:
	if agent == &"" or not def.is_valid() or access(agent) <= 0.0:
		return REFUSED_ACCESS
	if not has_room(agent, now):
		return REFUSED_FULL
	_holds[agent] = now + def.hold_minutes
	return OK


## Lets go of [param agent]'s place.
## @experimental
func release(agent: StringName) -> void:
	_holds.erase(agent)


## The advertisement [param agent] sees at minute [param now], [param distance] away, or null when
## it is refused, full, or priced beyond what [param trade] says the agent has. Relief and side
## effects are scaled by [method access]; leisure relief also by [param leisure]'s tolerance.
## @experimental
func advertise(agent: StringName, now: int, distance: float = 0.0, trade: BustleTradePort = null, leisure: BustleLeisure = null) -> BustleAdvertisement:
	var welcome := access(agent)
	if not def.is_valid() or welcome <= 0.0 or not has_room(agent, now):
		return null
	if not _affordable(agent, trade):
		return null
	var relief: Dictionary[StringName, float] = {}
	var adds: Dictionary[StringName, float] = {}
	for need: StringName in def.relief:
		relief[need] = def.relief[need] * welcome
	for need: StringName in def.adds:
		adds[need] = def.adds[need]
	var ad := BustleAdvertisement.new(id, relief, adds, def.tags.duplicate(), distance)
	return leisure.adjust(ad) if leisure != null else ad


## Completes [param agent]'s use at minute [param now]: pays, lowers the def's relief needs in
## [param needs] (leisure relief scaled by [param leisure]'s tolerance, which then rises), raises
## its side effects, and releases the place. Nothing changes unless it returns [constant OK]:
## [constant REFUSED_ACCESS], [constant REFUSED_FULL] (no hold and no room) or
## [constant REFUSED_PRICE] (it can't pay, or can't buy the def's item).
## @experimental
func use(agent: StringName, now: int, needs: BustleNeedSet, leisure: BustleLeisure = null, trade: BustleTradePort = null) -> StringName:
	if agent == &"" or not def.is_valid() or access(agent) <= 0.0:
		return REFUSED_ACCESS
	if not has_room(agent, now):
		return REFUSED_FULL
	if def.item != &"":
		var seller := _paid_to(agent)
		if not _affordable(agent, trade) or (seller != &"" and not trade.buy(agent, def.item, seller)):
			return REFUSED_PRICE
	else:
		var price := price_for(agent)
		if price > 0 and (trade == null or not trade.pay(agent, _paid_to(agent), price)):
			return REFUSED_PRICE
	var kind := leisure.kind_of(BustleAdvertisement.new(id, {}, {}, def.tags)) if leisure != null else &""
	var factor := leisure.use(kind) if kind != &"" else 1.0
	for need: StringName in def.relief:
		var amount := def.relief[need]
		needs.relieve(need, amount * factor if leisure != null and need == leisure.need else amount)
	for need: StringName in def.adds:
		needs.raise(need, def.adds[need])
	release(agent)
	return OK


## Its changing state as plain data: owner, payee and holds.
## @experimental
func export_state() -> Dictionary:
	var holds := {}
	var agents: Array[StringName] = _holds.keys()
	agents.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for agent: StringName in agents:
		holds[String(agent)] = _holds[agent]
	return {"owner": String(owner), "payee": String(payee), "holds": holds}


## Restores [method export_state]. False (and nothing changes) when malformed or over capacity.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var data: Dictionary = saved
	if not data.get("owner") is String or not data.get("payee") is String or not data.get("holds") is Dictionary:
		return false
	var staged: Dictionary[StringName, int] = {}
	for key: Variant in data["holds"]:
		var until: Variant = data["holds"][key]
		if until is float and is_finite(until) and until == floorf(until) and absf(until) < 9.0e15:
			until = int(until)
		if not key is String or String(key).is_empty() or not until is int:
			return false
		staged[StringName(key)] = until
	if staged.size() > def.capacity:
		return false
	owner = StringName(data["owner"])
	payee = StringName(data["payee"])
	_holds = staged
	return true


# Whether the agent could pay for (or buy) one use now. Changes nothing.
func _affordable(agent: StringName, trade: BustleTradePort) -> bool:
	var seller := _paid_to(agent)
	if def.item != &"":
		if seller == &"":
			return owner != &"" and agent == owner
		return trade != null and trade.can_buy(agent, def.item, seller)
	var price := price_for(agent)
	return price <= 0 or (trade != null and trade.balance(agent) >= price and seller != &"")


func _paid_to(agent: StringName) -> StringName:
	var to := owner if owner != &"" else payee
	return to if to != agent else &""


func _lapse(now: int) -> void:
	for agent: StringName in _holds.keys():
		if _holds[agent] <= now:
			_holds.erase(agent)
