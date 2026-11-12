# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The house demo, headless: three days on their own, orders with autonomy off, an order that
## interrupts and then gives way, traits that change what is chosen, a player-controlled agent that
## never chooses, and the same timeline hash from the same seed.

const House := preload("res://demo/house/house.gd")
const DAY := 1440
const A := House.RESIDENT_A
const B := House.RESIDENT_B
const EATS: Array[String] = ["stove", "table"]
const SOCIAL: Array[String] = ["phone", "table"]


func test_1_three_days_on_their_own_keep_every_need_in_hand() -> void:
	var house := House.build(1)
	house.run(3 * DAY)
	for id: StringName in [A, B]:
		for need: StringName in house.needs_of(id).ids():
			assert_lte(house.dire_minutes(id, need), 60, "%s: %s never above %.2f for more than an hour" % [id, need, house.dire_pressure])
		for day: int in 3:
			var used := _used(house, id, day)
			assert_true(used.any(func(o: String) -> bool: return EATS.has(o)), "%s eats on day %d: %s" % [id, day, used])
			assert_true(used.has("bed"), "%s sleeps on day %d: %s" % [id, day, used])
		var all := _used(house, id)
		assert_true(all.any(func(o: String) -> bool: return SOCIAL.has(o)), "%s socialises: %s" % [id, all])
		assert_eq(house.timeline.of(&"attend", id).size(), 3, "%s goes to work every day" % id)
		for day: int in 3:
			assert_eq(house.schedule_of(id).report(day, 3 * DAY)["missed"], 0, "%s misses no work on day %d" % [id, day])


func test_2_with_autonomy_off_orders_run_in_turn_then_the_agent_idles() -> void:
	var house := House.build(1)
	var brain := house.brain_of(A)
	brain.autonomy = BustleBrain.Autonomy.OFF
	var food := house.needs_of(A).pressure(&"food")
	for i: int in 36:
		var intent: BustleIntent = house.step()[A]
		assert_true(intent.idle, "with no order, nothing is chosen (minute %d)" % (house.now - house.step_minutes))
	assert_gt(house.needs_of(A).pressure(&"food"), food + 0.2, "needs carry on rising")
	assert_eq(_used(house, A), [] as Array[String], "and nothing is used")
	for order: Array in [[&"cook", &"stove"], [&"eat", &"table"], [&"sleep", &"bed"]]:
		assert_eq(brain.order(House.use_order(order[0], order[1])), &"", "%s queued" % order[0])
	var finished := 0
	while finished < 3 and house.now < 2 * DAY:
		house.step()
		finished = house.timeline.of(&"order", A).size()
	var orders := house.timeline.of(&"order", A).map(func(e: Dictionary) -> Array: return [e["payload"]["order"], e["payload"]["outcome"]])
	assert_eq(orders, [["cook", "DONE"], ["eat", "DONE"], ["sleep", "DONE"]], "in the order given")
	assert_eq(_used(house, A), ["stove", "table", "bed"] as Array[String])
	for i: int in 12:
		var intent: BustleIntent = house.step()[A]
		assert_true(intent.idle and intent.order_id == &"", "then it idles")


func test_3_an_order_interrupts_and_the_agent_resumes_its_goal() -> void:
	var house := House.build(1)
	var intent := _until(house, A, func(i: BustleIntent) -> bool:
		return i.goal_id == &"use_object" and i.option_id == &"bench" and house.now % DAY < 400)
	assert_not_null(intent, "the agent sits on the bench of its own accord")
	assert_eq(house.brain_of(A).order(House.use_order(&"lay_table", &"table")), &"")
	var during: BustleIntent = house.step()[A]
	assert_eq([during.order_id, during.option_id], [&"lay_table", &"table"], "the order takes over at once")
	while house.timeline.of(&"order", A).is_empty():
		house.step()
	assert_eq(house.timeline.of(&"order", A)[0]["payload"]["outcome"], "DONE")
	var after: BustleIntent = house.step()[A]
	assert_eq([after.goal_id, after.option_id, after.order_id], [&"use_object", &"bench", &""], "then it goes back to the bench")
	assert_true(after.reasons.any(func(r: Dictionary) -> bool: return r.get("kind") == &"resumed"), "resuming, not choosing afresh")


func test_4_swapping_the_loner_and_outgoing_traits_changes_what_is_chosen() -> void:
	var as_loner := House.build(1)
	var as_outgoing := House.build(1, true)
	as_loner.run(DAY)
	as_outgoing.run(DAY)
	var quiet := func(house: RefCounted) -> int: return _used(house, A).count("bench")
	var social := func(house: RefCounted) -> int: return _used(house, A).filter(func(o: String) -> bool: return SOCIAL.has(o)).size()
	assert_ne(_choices(as_loner, A), _choices(as_outgoing, A), "the same day, other choices")
	assert_gt(quiet.call(as_loner), social.call(as_loner), "as a loner, more time alone on the bench: %s" % [_used(as_loner, A)])
	assert_gt(social.call(as_outgoing), quiet.call(as_outgoing), "outgoing, more company: %s" % [_used(as_outgoing, A)])


func test_5_a_player_controlled_agent_never_chooses_for_itself() -> void:
	var house := House.build(1)
	var brain := house.brain_of(A)
	brain.set_player_controlled(true)
	assert_eq(brain.order(House.use_order(&"cook", &"stove")), &"player_controlled", "orders are refused too")
	for i: int in DAY / house.step_minutes:
		var intent: BustleIntent = house.step()[A]
		assert_true(intent.player_controlled and intent.goal_id == &"" and intent.order_id == &"" and intent.option_id == &"",
			"never a goal of its own (minute %d)" % (house.now - house.step_minutes))
	assert_eq(_used(house, A), [] as Array[String], "so it uses nothing")
	assert_eq(house.timeline.of(&"attend", A), [] as Array[Dictionary], "and goes to no work")
	assert_eq(house.timeline.of(&"choice", A).size(), 1, "one entry: under the player's control")
	assert_false(_used(house, B).is_empty(), "the other resident carries on")


func test_the_same_seed_and_setup_give_the_same_timeline_hash() -> void:
	var first := House.build(7)
	var second := House.build(7)
	first.run(DAY)
	second.run(DAY)
	assert_gt(first.timeline.size(), 10)
	assert_eq(second.timeline.lines(), first.timeline.lines())
	assert_eq(second.timeline.hash(), first.timeline.hash())
	assert_eq(first.timeline.hash().length(), 64, "SHA-256, as hex")


func test_the_house_scene_runs_and_the_splash_opens_it() -> void:
	var main := (load("res://demo/main.tscn") as PackedScene).instantiate() as Control
	add_child_autofree(main)
	assert_eq((main.get_node("House") as Button).text, "House")
	var view := (load("res://demo/house/house.tscn") as PackedScene).instantiate() as Control
	view.set("minutes_per_second", 6000.0)
	add_child_autofree(view)
	await wait_process_frames(3)
	var house: RefCounted = view.get("house")
	assert_gt(house.now, 0, "time passes")
	var text := (view.get_node("Status") as Label).text
	assert_string_contains(text, String(A))
	assert_string_contains(text, String(B))


# The objects [param id] used, oldest first; on game day [param day] only, when given.
func _used(house: RefCounted, id: StringName, day: int = -1) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in house.timeline.of(&"used", id):
		if day < 0 or int(entry["t"]) / DAY == day:
			out.append(String(entry["payload"]["object"]))
	return out


func _choices(house: RefCounted, id: StringName) -> Array:
	return house.timeline.of(&"choice", id).map(func(e: Dictionary) -> String: return "%s/%s" % [e["payload"]["goal"], e["payload"]["option"]])


# Steps until [param id]'s intent passes [param test] (returning it), or null after three days.
func _until(house: RefCounted, id: StringName, test: Callable) -> BustleIntent:
	while house.now < 3 * DAY:
		var intent: BustleIntent = house.step()[id]
		if test.call(intent):
			return intent
	return null
