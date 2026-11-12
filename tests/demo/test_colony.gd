# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The colony demo, headless: a week on their own with mood following thoughts, a forced low mood
## starting a mental state at once and catharsis when it ends, a friend's comfort, the same
## timeline hash from the same seed, and the demo still running with each optional module left out.

const Colony := preload("res://demo/colony/colony.gd")
const DAY := 1440
const WEEK := 7 * DAY
const A := Colony.SETTLER_A
const B := Colony.SETTLER_B
const C := Colony.SETTLER_C
const D := Colony.SETTLER_D
## The timeline hash of seed 1 over a week with every module on and a grief forced on settler B on
## the second afternoon (so a friend comforts them, and the seed picks what else is said). A change to
## the colony data, the harness or the framework's choices changes it: check the change is meant,
## then update it.
const GOLDEN_HASH := "6b622a0ac5f32f586880ab3d4cf00b50da09b54d3d0f785d3943128b2ffe93af"


func test_6_a_week_on_their_own_schedules_hold_and_mood_follows_thoughts() -> void:
	var colony := Colony.build(1)
	var calm := Colony.build(1, Colony.MODULES, false)
	var during := {}
	while colony.now < WEEK:
		colony.step()
		calm.step()
		if colony.now > Colony.COLD_START and colony.now <= Colony.COLD_START + Colony.COLD_MINUTES:
			for id: StringName in Colony.SETTLERS:
				var sums: Array = during.get(id, [0.0, 0.0])
				during[id] = [sums[0] + colony.mood_of(id).mood, sums[1] + calm.mood_of(id).mood]
	var steps := float(Colony.COLD_MINUTES / colony.step_minutes)
	for id: StringName in Colony.SETTLERS:
		assert_eq(_arrivals(colony, id, Colony.FARM), _on_time(7), "%s works the field on time every day" % id)
		assert_eq(_arrivals(colony, id, Colony.REST), _on_time(7), "%s goes to bed on time every night" % id)
		for need: StringName in [&"food", &"sleep"]:
			assert_lte(colony.dire_minutes(id, need), 60, "%s: %s never dire for more than an hour" % [id, need])
		var cold: float = during[id][0] / steps
		var mild: float = during[id][1] / steps
		assert_lt(cold, mild - 3.0, "%s: the cold snap's thoughts pull mood down (%.1f against %.1f on average)" % [id, cold, mild])
		assert_almost_eq(colony.mood_of(id).mood, calm.mood_of(id).mood, 1.0, "%s: and once they pass, mood comes back" % id)
	assert_eq(colony.timeline.of(&"event").map(func(e: Dictionary) -> Array: return [e["t"], e["payload"]["phase"]]),
		[[Colony.COLD_START, "start"], [Colony.COLD_START + Colony.COLD_MINUTES, "end"]], "the host injects the cold snap")
	assert_true(calm.timeline.of(&"event").is_empty())


func test_6_mood_heads_for_its_thoughts() -> void:
	var colony := Colony.build(1)
	colony.run(DAY + 3 * 60)
	var mood := colony.mood_of(A)
	assert_almost_eq(mood.mood, mood.target(), 0.5, "settled by morning")
	var before := mood.mood
	assert_true(mood.add_thought(Colony.thought(&"good_news", 20.0, 24.0, &"glad", 1)))
	assert_almost_eq(mood.target(), before + 20.0, 0.5, "a thought moves the target by its value")
	colony.run(60)
	assert_almost_eq(mood.mood, before + mood.config.rise_per_hour, 0.5, "and mood heads for it at the rise rate")
	assert_true(mood.reasons().any(func(r: Dictionary) -> bool: return r["thought"] == &"good_news"), "with its reason")
	var settled := false
	for i: int in 24:
		colony.step()
		settled = settled or absf(mood.mood - mood.target()) < 0.5
	assert_true(settled, "until it gets there")


func test_7_a_forced_low_mood_starts_a_state_at_once_and_ends_in_catharsis() -> void:
	var colony := Colony.build(1, [Colony.NEEDS_MOOD, Colony.PERCEPTION] as Array[StringName])
	colony.run(DAY + 2 * 60)
	var grief := Colony.thought(&"grief", -45.0, 24.0, &"sad", 1)
	var entered := {}
	for id: StringName in [C, D]:
		assert_true(colony.mood_of(id).add_thought(grief))
	while entered.size() < 2 and colony.now < 3 * DAY:
		colony.step()
		for id: StringName in [C, D]:
			if entered.has(id):
				continue
			var mood := colony.mood_of(id)
			var state := colony.mental_of(id)
			if mood.mood >= state.break_threshold(mood):
				assert_false(state.is_active(), "%s: nothing starts above the line" % id)
				continue
			assert_true(state.is_active(), "%s: crossing the line starts a state in the same step" % id)
			assert_eq(state.active()["tier"], "minor", "%s: just under the line, a minor one" % id)
			entered[id] = colony.now - colony.step_minutes
	for id: StringName in [C, D]:
		assert_true(entered.has(id), "%s entered a state" % id)
		var logged := colony.timeline.of(&"state", id)
		assert_eq(logged.size(), 1)
		assert_eq(logged[0]["t"], entered[id], "%s: logged at that minute" % id)
		assert_eq(colony.mood_of(id).count(&"catharsis"), 0, "no catharsis yet")
	assert_lt(absi(int(entered[C]) - int(entered[D])), 6 * 60, "no spacing or cap: both are in a state at once")
	for id: StringName in [C, D]:
		colony.mood_of(id).remove_thought(&"grief")
	var until := colony.now + 2 * DAY
	while colony.now < until and not [C, D].all(func(id: StringName) -> bool: return not colony.mental_of(id).is_active()):
		colony.step()
	for id: StringName in [C, D]:
		assert_false(colony.mental_of(id).is_active(), "%s: the state ends" % id)
		assert_eq(colony.timeline.of(&"state_end", id).size(), 1)
		assert_eq(colony.mood_of(id).count(&"catharsis"), 1, "%s: with the catharsis thought" % id)
	assert_eq(colony.timeline.of(&"state", A), [] as Array[Dictionary], "nobody else breaks")


func test_8_a_friend_comforts_a_settler_in_a_low_mood() -> void:
	for modules: Array[StringName] in [Colony.MODULES, [Colony.NEEDS_MOOD, Colony.SOCIAL] as Array[StringName]]:
		var colony := Colony.build(1, modules)
		colony.run(DAY + 10 * 60)
		assert_true(colony.mood_of(B).add_thought(Colony.thought(&"grief", -45.0, 12.0, &"sad", 1)))
		var until := colony.now + 4 * 60
		while colony.now < until and colony.timeline.of(&"talk", A).is_empty():
			colony.step()
		var comforts := colony.timeline.of(&"choice", A).filter(func(e: Dictionary) -> bool: return e["payload"]["goal"] == "comfort")
		assert_false(comforts.is_empty(), "%s: the friend chooses to comfort" % [modules])
		if comforts.is_empty():
			continue
		assert_eq(comforts[0]["payload"]["option"], String(B), "the settler in the low mood")
		var talk := colony.timeline.of(&"talk", A)
		assert_false(talk.is_empty())
		assert_eq(talk[0]["payload"], {"with": String(B), "interaction": "comfort"}, "opening with comfort")
		assert_eq(colony.mood_of(B).count(&"comforted"), 1, "which leaves its thought")
		assert_gt(colony.store.opinion(B, A), 50, "and its friend thinks better of them")
		for id: StringName in [C, D]:
			assert_true(colony.timeline.of(&"choice", id).all(func(e: Dictionary) -> bool: return e["payload"]["goal"] != "comfort"),
				"%s isn't a friend, so doesn't come" % id)


func test_9_the_same_seed_gives_the_same_timeline_hash() -> void:
	var first := _grieving_week(1)
	var second := _grieving_week(1)
	assert_gt(first.timeline.size(), 100)
	assert_false(first.timeline.of(&"talk").is_empty(), "a friend comforts B, and they talk on")
	assert_eq(second.timeline.lines(), first.timeline.lines())
	assert_eq(second.timeline.hash(), first.timeline.hash())
	assert_eq(first.timeline.hash(), GOLDEN_HASH, "the pinned week")
	assert_ne(_grieving_week(2).timeline.hash(), first.timeline.hash(), "another seed, another conversation")


func test_10_the_demo_runs_with_each_optional_module_left_out() -> void:
	var sets: Array = []
	for left_out: StringName in Colony.MODULES:
		sets.append(Colony.MODULES.filter(func(m: StringName) -> bool: return m != left_out))
	sets.append([])
	for modules: Array in sets:
		var on: Array[StringName] = []
		on.assign(modules)
		var colony := Colony.build(1, on)
		colony.run(WEEK)
		for id: StringName in Colony.SETTLERS:
			assert_eq(_arrivals(colony, id, Colony.FARM), _on_time(7), "%s: %s works every day" % [on, id])
			assert_eq(_arrivals(colony, id, Colony.REST), _on_time(7), "%s: %s sleeps every night" % [on, id])
			assert_eq(colony.mood_of(id) == null, not on.has(Colony.NEEDS_MOOD), "%s: a mood only with needs_mood" % [on])
		assert_eq(colony.store == null, not on.has(Colony.SOCIAL), "%s: a social store only with social" % [on])
		assert_eq(colony.perception == null, not on.has(Colony.PERCEPTION), "%s: perception only with perception" % [on])
		if not on.has(Colony.NEEDS_MOOD):
			assert_true(colony.timeline.of(&"state").is_empty(), "no mental states without needs_mood")
		if not on.has(Colony.SOCIAL):
			assert_true(colony.timeline.of(&"talk").is_empty(), "no conversations without social")
			assert_false(colony.brain_of(A).library.goals.any(func(g: BustleGoalDef) -> bool: return g.id == &"comfort"))


func test_the_colony_scene_runs_and_the_splash_opens_it() -> void:
	var main := (load("res://demo/main.tscn") as PackedScene).instantiate() as Control
	add_child_autofree(main)
	assert_eq((main.get_node("Colony") as Button).text, "Colony")
	var view := (load("res://demo/colony/colony.tscn") as PackedScene).instantiate() as Control
	view.set("minutes_per_second", 6000.0)
	add_child_autofree(view)
	await wait_process_frames(3)
	var colony: RefCounted = view.get("colony")
	assert_gt(colony.now, Colony.START, "time passes")
	var text := (view.get_node("Status") as Label).text
	for id: StringName in Colony.SETTLERS:
		assert_string_contains(text, String(id))


# [param id]'s arrivals for [param activity] blocks, oldest first.
func _arrivals(colony: RefCounted, id: StringName, activity: StringName) -> Array:
	return colony.timeline.of(&"attend", id).filter(func(e: Dictionary) -> bool: return e["payload"]["activity"] == String(activity)) \
		.map(func(e: Dictionary) -> String: return e["payload"]["arrival"])


func _on_time(count: int) -> Array:
	var out: Array = []
	out.resize(count)
	out.fill("on_time")
	return out


# A week from seed [param world_seed] with every module on, and a grief forced on settler B at 16:00
# on the second day.
func _grieving_week(world_seed: int) -> RefCounted:
	var colony := Colony.build(world_seed)
	colony.run(DAY + 10 * 60)
	colony.mood_of(B).add_thought(Colony.thought(&"grief", -45.0, 12.0, &"sad", 1))
	colony.run(WEEK - colony.now)
	return colony
