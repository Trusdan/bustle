# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Affordances: needs fall on use, capacity and reservations, ownership, cost through the trade
## port, leisure tolerance, the real scorer choosing between them, and saving.

var _needs: BustleNeedSet


func before_each() -> void:
	_needs = BustleNeedSet.new()
	for id: StringName in [&"rest", &"hunger", &"leisure", &"company"]:
		var def := BustleNeedDef.new()
		def.id = id
		def.start = 0.8
		_needs.add_need(def)


func test_using_an_affordance_lowers_its_needs_and_raises_its_side_effects() -> void:
	var bench := _place(&"bench", {&"rest": 0.3}, {&"hunger": 0.1})
	assert_eq(bench.reserve(&"baker", 0), BustleAffordance.OK)
	assert_eq(bench.use(&"baker", 20, _needs), BustleAffordance.OK)
	assert_almost_eq(_needs.pressure(&"rest"), 0.5, 1e-6, "rest fell by its relief")
	assert_almost_eq(_needs.pressure(&"hunger"), 0.9, 1e-6, "hunger rose by its side effect")
	assert_eq(bench.holders(20), [] as Array[StringName], "the place is released")
	assert_eq(bench.use(&"smith", 30, _needs), BustleAffordance.OK, "a free place needs no reservation")


func test_capacity_and_reservations_lapse_renew_and_release() -> void:
	var table := _place(&"table", {&"hunger": 0.5})
	table.def.capacity = 2
	table.def.hold_minutes = 30
	assert_eq(table.reserve(&"baker", 0), BustleAffordance.OK)
	assert_eq(table.reserve(&"smith", 5), BustleAffordance.OK)
	assert_eq(table.reserve(&"miller", 10), BustleAffordance.REFUSED_FULL, "two places, both held")
	assert_null(table.advertise(&"miller", 10), "a full affordance isn't offered")
	assert_not_null(table.advertise(&"baker", 10), "but the holder still sees it")
	assert_eq(table.use(&"miller", 10, _needs), BustleAffordance.REFUSED_FULL)
	assert_almost_eq(_needs.pressure(&"hunger"), 0.8, 1e-6, "a refused use changes nothing")
	assert_eq(table.reserve(&"baker", 25), BustleAffordance.OK, "holding again renews")
	assert_eq(table.holders(40), [&"baker"] as Array[StringName], "the smith's hold lapsed at 35")
	assert_eq(table.reserve(&"miller", 40), BustleAffordance.OK)
	table.release(&"baker")
	assert_eq(table.holders(40), [&"miller"] as Array[StringName])
	assert_true(table.has_room(&"smith", 40))


func test_an_owned_affordance_refuses_or_discounts_others() -> void:
	var bed := _place(&"bed", {&"rest": 0.6})
	bed.owner = &"baker"
	assert_eq(bed.access(&"baker"), 1.0)
	assert_eq(bed.reserve(&"smith", 0), BustleAffordance.REFUSED_ACCESS, "others_mult 0: refused")
	assert_null(bed.advertise(&"smith", 0))
	assert_eq(bed.use(&"smith", 0, _needs), BustleAffordance.REFUSED_ACCESS)
	bed.def.others_mult = 0.5
	var offered := bed.advertise(&"smith", 0)
	assert_almost_eq(offered.relief[&"rest"], 0.3, 1e-6, "a guest's score is halved")
	assert_almost_eq(bed.advertise(&"baker", 0).relief[&"rest"], 0.6, 1e-6, "the owner's isn't")
	bed.access_hook = func(agent: StringName, _a: BustleAffordance) -> float: return 1.0 if agent == &"smith" else NAN
	assert_eq(bed.access(&"smith"), 1.0, "a hook decides instead")
	assert_eq(bed.access(&"baker"), 0.0, "and a result that isn't finite refuses")


func test_a_priced_use_is_paid_through_the_trade_port() -> void:
	var trade := BustleTradePort.new()
	trade.set_balance(&"smith", 5)
	trade.set_balance(&"miller", 1)
	var stall := _place(&"stall", {&"hunger": 0.4})
	stall.def.price = 3
	stall.owner = &"baker"
	stall.def.others_mult = 1.0
	assert_null(stall.advertise(&"smith", 0), "no trade port: a priced option isn't offered")
	assert_not_null(stall.advertise(&"smith", 0, 0.0, trade))
	assert_null(stall.advertise(&"miller", 0, 0.0, trade), "can't afford it")
	assert_eq(stall.use(&"miller", 0, _needs, null, trade), BustleAffordance.REFUSED_PRICE)
	assert_almost_eq(_needs.pressure(&"hunger"), 0.8, 1e-6, "nothing changed")
	assert_eq(stall.use(&"smith", 0, _needs, null, trade), BustleAffordance.OK)
	assert_eq([trade.balance(&"smith"), trade.balance(&"baker")], [2, 3], "paid to the owner")
	assert_eq(stall.price_for(&"baker"), 0, "free to the owner")
	var well := _place(&"well", {&"hunger": 0.1})
	well.def.price = 1
	assert_null(well.advertise(&"smith", 0, 0.0, trade), "nobody to pay")
	well.payee = &"miller"
	assert_eq(well.use(&"smith", 0, _needs, null, trade), BustleAffordance.OK)
	assert_eq(trade.balance(&"miller"), 2)
	well.cost_hook = func(_agent: StringName, _a: BustleAffordance) -> int: return -4
	assert_eq(well.price_for(&"smith"), 0, "a hook's price is never negative")


func test_leisure_use_builds_tolerance_and_scales_relief() -> void:
	var leisure := BustleLeisure.new()
	leisure.kinds = [&"music"]
	var fiddle := _place(&"fiddle", {&"leisure": 0.4, &"company": 0.2}, {}, [&"social", &"music"])
	fiddle.use(&"baker", 0, _needs, leisure)
	assert_almost_eq(_needs.pressure(&"leisure"), 0.4, 1e-6, "full relief the first time")
	fiddle.use(&"baker", 1, _needs, leisure)
	assert_almost_eq(_needs.pressure(&"leisure"), 0.1, 1e-6, "0.75 of it the second")
	assert_almost_eq(_needs.pressure(&"company"), 0.4, 1e-6, "other needs aren't scaled")
	assert_almost_eq(fiddle.advertise(&"baker", 2, 0.0, null, leisure).relief[&"leisure"], 0.2, 1e-6)


func test_the_scorer_picks_between_affordances_and_skips_full_ones() -> void:
	_needs.set_pressure(&"rest", 0.9)
	_needs.set_pressure(&"hunger", 0.3)
	var set := BustleAffordanceSet.new()
	assert_true(set.add(_place(&"bed", {&"rest": 0.8})))
	assert_true(set.add(_place(&"bench", {&"rest": 0.3})))
	assert_true(set.add(_place(&"oven", {&"hunger": 0.8})))
	assert_false(set.add(_place(&"bed", {})), "ids are unique")
	assert_eq(_pick(set, &"baker"), &"bed", "the strongest relief for the most pressing need")
	set.get_affordance(&"bed").reserve(&"smith", 0)
	assert_eq(_pick(set, &"baker"), &"bench", "the bed is taken, so the bench")
	var only: Array[StringName] = [&"oven"]
	assert_eq(set.advertisements(&"baker", 0, Callable(), null, null, only).size(), 1, "only what it knows of")
	var far := func(a: BustleAffordance) -> float: return 50.0 if a.id == &"bench" else 1.0
	var offered := set.advertisements(&"baker", 0, far)
	assert_eq(offered[0].option_id, &"bench", "in id order (the bed is still held)")
	assert_eq(offered[0].distance, 50.0, "with its distance")


func test_state_round_trips_and_bad_data_changes_nothing() -> void:
	var set := BustleAffordanceSet.new()
	var table := _place(&"table", {&"hunger": 0.5})
	table.def.capacity = 2
	set.add(table)
	table.owner = &"baker"
	table.def.others_mult = 1.0
	table.reserve(&"baker", 10)
	table.reserve(&"smith", 12)
	var saved := set.export_state()
	assert_eq(saved, {"affordances": {"table": {"owner": "baker", "payee": "", "holds": {"baker": 70, "smith": 72}}}})
	var other := BustleAffordanceSet.new()
	var copy := _place(&"table", {&"hunger": 0.5})
	copy.def.capacity = 2
	other.add(copy)
	assert_true(other.import_state(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(other.export_state(), saved)
	var crowded: Dictionary = saved.duplicate(true)
	crowded["affordances"]["table"]["holds"]["miller"] = 80
	assert_false(other.import_state(crowded), "over capacity")
	assert_false(other.import_state({"affordances": {"table": {"owner": 3, "payee": "", "holds": {}}}}))
	assert_false(other.import_state({"affordances": {"table": {"owner": "", "payee": "", "holds": {"x": 1.5}}}}))
	assert_eq(other.export_state(), saved, "refused imports change nothing")


func test_definitions_are_checked() -> void:
	var bad: Array[BustleAffordanceDef] = []
	for i in 5:
		bad.append(_place(&"x", {&"rest": 0.1}).def)
	bad[0].capacity = 0
	bad[1].relief[&"rest"] = -0.2
	bad[2].adds[&"hunger"] = INF
	bad[3].price = -1
	bad[4].others_mult = 2.0
	for def: BustleAffordanceDef in bad:
		assert_false(def.is_valid())
		var placed := BustleAffordance.new(&"x", def)
		assert_eq(placed.reserve(&"baker", 0), BustleAffordance.REFUSED_ACCESS)
		assert_null(placed.advertise(&"baker", 0))
	assert_true(_place(&"ok", {}).def.is_valid())


func _pick(set: BustleAffordanceSet, agent: StringName) -> StringName:
	var goal := BustleGoalDef.new()
	goal.id = &"use_something"
	goal.band = BustleBands.PERSONAL
	goal.uses_advertisements = true
	var library := BustleGoalLibrary.new()
	library.goals.append(goal)
	var context := BustleScoreContext.new()
	_needs.fill_inputs(context.inputs)
	context.advertisements = set.advertisements(agent, 0)
	var candidates := BustleUtilityScorer.new().evaluate(library, context, BustleScoringConfig.new())
	BustleUtilityScorer.sort(candidates)
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and not candidate.fallback:
			return candidate.option_id
	return &""


func _place(id: StringName, relief: Dictionary[StringName, float], adds: Dictionary[StringName, float] = {}, tags: Array[StringName] = []) -> BustleAffordance:
	var def := BustleAffordanceDef.new()
	def.id = id
	def.relief = relief.duplicate()
	def.adds = adds.duplicate()
	def.tags = tags.duplicate()
	return BustleAffordance.new(id, def, &"village", Vector3.ZERO)
