# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The trade port: prices, buying and saving balances; hungry agents buying food they can afford
## from a stall whose stock the host keeps; wages arriving and being spent; and a host lending
## credit through the same two methods.

const STALL := "res://demo/trade/food_stall.tres"


## A host port that keeps stock: an item is offered only while some is left, and buying takes one.
class StockedTrade:
	extends BustleTradePort
	var stock: Dictionary[StringName, int] = {}

	func can_buy(id: StringName, item: StringName, seller: StringName) -> bool:
		return stock.get(item, 0) > 0 and super(id, item, seller)

	func buy(id: StringName, item: StringName, seller: StringName) -> bool:
		if not can_buy(id, item, seller) or not super(id, item, seller):
			return false
		stock[item] -= 1
		return true


## A host port that lets agents run up a debt for staples they can't pay for.
class CreditTrade:
	extends BustleTradePort
	var staples: Array[StringName] = []
	var debts: Dictionary[StringName, int] = {}

	func can_buy(id: StringName, item: StringName, seller: StringName) -> bool:
		return super(id, item, seller) or (staples.has(item) and price_of(item, seller) >= 0 and id != seller)

	func buy(id: StringName, item: StringName, seller: StringName) -> bool:
		if super(id, item, seller):
			return true
		if not can_buy(id, item, seller):
			return false
		debts[id] = debts.get(id, 0) + price_of(item, seller)
		return true


func test_the_default_port_prices_buys_and_saves() -> void:
	var trade := BustleTradePort.new()
	trade.prices = {&"bread": 3, &"cake": 0, &"bad": -2}
	trade.set_balance(&"baker", 0)
	trade.set_balance(&"smith", 5)
	assert_eq([trade.price_of(&"bread", &"baker"), trade.price_of(&"cake", &"baker"), trade.price_of(&"bad", &"baker"), trade.price_of(&"stone", &"baker")], [3, 0, -1, -1])
	assert_true(trade.can_buy(&"smith", &"bread", &"baker"))
	assert_false(trade.can_buy(&"smith", &"stone", &"baker"), "not sold")
	assert_false(trade.can_buy(&"smith", &"bread", &"smith"), "not from oneself")
	assert_true(trade.buy(&"smith", &"bread", &"baker"))
	assert_eq([trade.balance(&"smith"), trade.balance(&"baker")], [2, 3], "the price moved")
	assert_false(trade.can_buy(&"smith", &"bread", &"baker"), "2 is less than 3")
	assert_false(trade.buy(&"smith", &"bread", &"baker"))
	assert_eq([trade.balance(&"smith"), trade.balance(&"baker")], [2, 3], "a refused buy changes nothing")
	assert_true(trade.buy(&"smith", &"cake", &"baker"), "free things need no money")
	var saved: Variant = JSON.parse_string(JSON.stringify(trade.export_state()))
	var loaded := BustleTradePort.new()
	assert_true(loaded.import_state(saved))
	assert_eq(loaded.export_state(), trade.export_state())
	assert_eq(loaded.balance(&"baker"), 3)
	for bad: Variant in [null, {}, {"balances": {"": 1}}, {"balances": {"a": -1}}, {"balances": {"a": 1.5}}, {"balances": {"a": "1"}}]:
		assert_false(loaded.import_state(bad), str(bad))
	assert_eq(loaded.balance(&"baker"), 3, "bad data changes nothing")


func test_hungry_agents_buy_food_they_can_afford_and_stock_goes_down() -> void:
	var trade := StockedTrade.new()
	trade.prices = {&"bread": 4}
	trade.stock = {&"bread": 2}
	trade.set_balance(&"smith", 10)
	var stall := BustleAffordance.new(&"stall_1", load(STALL), &"square")
	stall.owner = &"baker"
	var needs := _hungry()
	var ad := stall.advertise(&"smith", 0, 0.0, trade)
	assert_not_null(ad, "offered to someone who can pay")
	assert_almost_eq(ad.relief[&"food"], 0.6, 1e-6)
	assert_eq(stall.reserve(&"smith", 0), BustleAffordance.OK)
	assert_eq(stall.use(&"smith", 5, needs, null, trade), BustleAffordance.OK)
	assert_eq([trade.balance(&"smith"), trade.balance(&"baker"), trade.stock[&"bread"]], [6, 4, 1], "paid, and the stock went down")
	assert_almost_eq(needs.pressure(&"food"), 0.3, 1e-6, "and they ate")
	trade.set_balance(&"miller", 3)
	assert_null(stall.advertise(&"miller", 10, 0.0, trade), "not offered to someone who can't pay")
	assert_eq(stall.use(&"miller", 10, _hungry(), null, trade), BustleAffordance.REFUSED_PRICE)
	assert_eq([trade.balance(&"miller"), trade.stock[&"bread"]], [3, 1], "a refused use changes nothing")
	assert_eq(stall.use(&"smith", 20, needs, null, trade), BustleAffordance.OK)
	assert_null(stall.advertise(&"smith", 30, 0.0, trade), "nothing left to sell")
	assert_eq(stall.use(&"smith", 30, needs, null, trade), BustleAffordance.REFUSED_PRICE)
	assert_eq(trade.balance(&"smith"), 2)
	assert_not_null(stall.advertise(&"baker", 30, 0.0, trade), "the owner takes without buying")
	assert_eq(stall.use(&"baker", 30, _hungry(), null, trade), BustleAffordance.OK)
	assert_eq(trade.balance(&"baker"), 8)
	var unowned := BustleAffordance.new(&"stall_2", load(STALL))
	assert_null(unowned.advertise(&"smith", 0, 0.0, trade), "with nobody to sell, it isn't offered")


func test_wages_arrive_and_are_spent() -> void:
	var trade := StockedTrade.new()
	trade.prices = {&"bread": 4}
	trade.stock = {&"bread": 10}
	trade.set_balance(&"guild", 50)
	var schedule := BustleSchedule.new(_routine(&"forge", 480, 960, 12))
	var stall := BustleAffordance.new(&"stall_1", load(STALL))
	stall.owner = &"baker"
	var needs := _hungry()
	assert_null(stall.advertise(&"smith", 470, 0.0, trade), "nothing to spend before work")
	assert_eq(schedule.attend(480, &"forge"), BustleSchedule.ON_TIME)
	assert_eq(schedule.settle(960, &"smith", trade, &"guild")[0]["paid"], true)
	assert_eq(trade.balance(&"smith"), 12, "the wage arrived")
	var bought := 0
	while stall.advertise(&"smith", 1000, 0.0, trade) != null and stall.use(&"smith", 1000, needs, null, trade) == BustleAffordance.OK:
		bought += 1
	assert_eq(bought, 3, "and was spent on bread")
	assert_eq([trade.balance(&"smith"), trade.balance(&"baker"), trade.balance(&"guild"), trade.stock[&"bread"]], [0, 12, 38, 7], "no money made or lost")


func test_a_host_can_lend_credit_through_the_same_methods() -> void:
	var trade := CreditTrade.new()
	trade.prices = {&"bread": 4, &"cake": 9}
	trade.staples = [&"bread"]
	var stall := BustleAffordance.new(&"stall_1", load(STALL))
	stall.owner = &"baker"
	assert_not_null(stall.advertise(&"smith", 0, 0.0, trade), "a broke agent is still offered a staple")
	assert_eq(stall.use(&"smith", 0, _hungry(), null, trade), BustleAffordance.OK)
	assert_eq([trade.balance(&"smith"), trade.debts[&"smith"]], [0, 4], "on credit, with the debt kept")
	assert_false(trade.can_buy(&"smith", &"cake", &"baker"), "but not anything else")


func _hungry() -> BustleNeedSet:
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = 0.9
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	return needs


func _routine(activity: StringName, start: int, end: int, wage: int) -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = activity
	block.start_minute = start
	block.end_minute = end
	block.wage = wage
	var routine := BustleScheduleDef.new()
	routine.id = activity
	routine.day = BustleScheduleDay.new()
	routine.day.blocks.append(block)
	return routine
