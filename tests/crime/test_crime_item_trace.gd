# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Stolen goods stay traceable after they change hands. deed_of_item() gives the open deed an item
## is from, whoever holds it now (the thief, someone it was passed on to, or nobody once used up);
## stolen_goods_held_by() lists the stolen goods an agent holds, whoever stole them, while
## stolen_goods_of() keeps meaning the thief's own. Both only read: they move, make and destroy
## nothing, and saves are unchanged.

var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _needs: Dictionary[StringName, BustleNeedSet] = {}


func before_each() -> void:
	_society = BustleSociety.new(5)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_crime = BustleCrime.new(_society)
	_needs = {}
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return _needs.get(id)
	_watch = BustleCrimeWatch.new(_crime)
	_watch.instant = true
	_agent(&"drifter", &"market", 1.0)
	_agent(&"baker", &"bakery", 0.0)
	_agent(&"cook", &"bakery", 0.0)
	_agent(&"smith", &"forge", 0.0)
	_society.ports.property.register(&"loaf", &"baker", &"market", {&"food": 0.5})
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


# The drifter steals the baker's loaf at the market with nobody there to see: record 1, a deed.
func _deed() -> void:
	assert_false(_crime.consider(&"drifter", 10).is_empty(), "the drifter picks the loaf")
	assert_true(_crime.steal(&"drifter", 10)["ok"])
	assert_true(_watch.record(1)["deed"])


func _ids(rows: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in rows:
		out.append(int(row["id"]))
	return out


func test_an_item_the_thief_holds_points_to_its_deed() -> void:
	_deed()
	assert_eq(_watch.deed_of_item(&"loaf"), _watch.record(1), "the whole record, as record() gives it")
	assert_eq(_ids(_watch.stolen_goods_held_by(&"drifter")), [1] as Array[int])
	assert_eq(_watch.stolen_goods_held_by(&"drifter"), _watch.stolen_goods_of(&"drifter"),
		"for the thief holding its own theft, both lists agree")
	assert_eq(_watch.stolen_goods_held_by(&"baker"), [] as Array[Dictionary], "the owner holds nothing stolen")


func test_an_item_passed_on_still_points_to_its_deed() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"), "sold on to the cook")
	assert_eq(int(_watch.deed_of_item(&"loaf")["id"]), 1, "the item still points to the deed")
	assert_eq(_watch.stolen_goods_of(&"drifter"), [] as Array[Dictionary], "stolen_goods_of keeps its meaning")
	assert_eq(_watch.stolen_goods_held_by(&"drifter"), [] as Array[Dictionary], "the thief no longer holds it")
	assert_eq(_ids(_watch.stolen_goods_held_by(&"cook")), [1] as Array[int], "the cook does")
	assert_true(_society.ports.property.transfer(&"loaf", &"cook", &"smith"), "and given on again")
	assert_eq(int(_watch.deed_of_item(&"loaf")["id"]), 1)
	assert_eq(_watch.stolen_goods_held_by(&"cook"), [] as Array[Dictionary])
	assert_eq(_ids(_watch.stolen_goods_held_by(&"smith")), [1] as Array[int])


func test_a_used_up_item_keeps_its_trace_and_nobody_holds_it() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"))
	assert_true(_society.ports.property.remove(&"loaf"), "the cook eats it")
	assert_eq(int(_watch.deed_of_item(&"loaf")["id"]), 1, "the deed is still open, and still the loaf's")
	for agent: StringName in [&"drifter", &"baker", &"cook", &"smith"]:
		assert_eq(_watch.stolen_goods_held_by(agent), [] as Array[Dictionary], "nobody holds it: %s" % agent)


func test_a_found_deed_leaves_the_query_but_the_goods_stay_listed() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"))
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int], "the baker finds it gone")
	assert_eq(_watch.deed_of_item(&"loaf"), {}, "a found deed isn't open")
	assert_eq(_ids(_watch.stolen_goods_held_by(&"cook")), [1] as Array[int], "but the cook still holds stolen goods")


func test_a_recovered_deed_closes_the_trace_for_good() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"baker"), "given back")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [] as Array[int])
	assert_eq(_watch.deed_of_item(&"loaf"), {}, "closed as recovered")
	assert_true(_society.ports.property.transfer(&"loaf", &"baker", &"cook"), "the baker sells it, its own to sell")
	assert_eq(_watch.stolen_goods_held_by(&"cook"), [] as Array[Dictionary], "so the cook holds nothing stolen")
	assert_eq(_watch.deed_of_item(&"loaf"), {})


func test_a_witnessed_theft_is_no_deed_but_its_goods_are_stolen() -> void:
	_watch.perceives = func(agent: StringName, _thief: StringName, _place: StringName) -> bool: return agent == &"smith"
	_deed_witnessed()
	assert_eq(_watch.deed_of_item(&"loaf"), {}, "someone saw it: not a deed")
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"))
	assert_eq(_ids(_watch.stolen_goods_held_by(&"cook")), [1] as Array[int])


func _deed_witnessed() -> void:
	assert_false(_crime.consider(&"drifter", 10).is_empty())
	assert_true(_crime.steal(&"drifter", 10)["ok"])
	assert_false(_watch.record(1)["deed"])


func test_an_item_stolen_twice_gives_the_earliest_open_deed() -> void:
	_deed()
	assert_true(_crime.record_theft(&"stranger", &"drifter", &"loaf", {"place": &"alley", "at": 20}),
		"someone outside the society takes it from the drifter where nobody is")
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"stranger"))
	assert_true(_watch.record(2)["deed"])
	assert_eq(int(_watch.deed_of_item(&"loaf")["id"]), 1, "the baker's loss comes first")
	assert_eq(_ids(_watch.stolen_goods_held_by(&"stranger")), [1, 2] as Array[int], "both records, by id")
	assert_eq(_watch.notice_losses(&"baker", &"market", 30), [1] as Array[int])
	assert_eq(int(_watch.deed_of_item(&"loaf")["id"]), 2, "then the drifter's")


func test_empty_and_unknown_ids_give_nothing() -> void:
	_deed()
	assert_eq(_watch.deed_of_item(&""), {})
	assert_eq(_watch.deed_of_item(&"ladle"), {}, "never stolen")
	assert_eq(_watch.stolen_goods_held_by(&""), [] as Array[Dictionary])
	assert_eq(_watch.stolen_goods_held_by(&"nobody"), [] as Array[Dictionary])


func test_the_queries_change_nothing_and_survive_save_and_load() -> void:
	_deed()
	assert_true(_society.ports.property.transfer(&"loaf", &"drifter", &"cook"))
	var watch_before := _watch.export_state()
	var items_before := _society.ports.property.export_state()
	_watch.deed_of_item(&"loaf")
	_watch.stolen_goods_held_by(&"cook")
	assert_eq(_watch.export_state(), watch_before, "no new state, nothing changed")
	assert_eq(_society.ports.property.export_state(), items_before, "no goods moved, made or destroyed")
	var loaded := BustleCrimeWatch.new(_crime)
	assert_true(loaded.import_state(watch_before.duplicate(true)), "loads")
	assert_eq(int(loaded.deed_of_item(&"loaf")["id"]), 1)
	assert_eq(_ids(loaded.stolen_goods_held_by(&"cook")), [1] as Array[int])
	assert_eq(loaded.export_state(), watch_before, "and saves the same again")


func _agent(id: StringName, area: StringName, hunger: float) -> void:
	_society.add_agent(id, &"villager").area = area
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = hunger
	var needs := BustleNeedSet.new()
	needs.add_need(food)
	_needs[id] = needs
