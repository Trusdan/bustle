# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The open_business ambition template: off by default; once turned on, assigned to a greedy agent
## (greed at least 50) whose host says it can open a business; done when the host says it opened
## one; moot when the host says it can't. All three are host facts: Bustle opens nothing, takes no
## money and assigns no property. Untargeted work and trade boosts, the 7-day cooldown, and nothing
## random.

const DAY := 1440
const CAN := {"can_open_business": true}

var _config: BustleAmbitionConfig
var _ambitions: BustleAmbitions
var _greedy: BustlePersonality


func before_each() -> void:
	_config = _only_open_business()
	_ambitions = BustleAmbitions.new(&"baker", _config)
	_greedy = _person(70.0)


# A library of only open_business, turned on.
func _only_open_business() -> BustleAmbitionConfig:
	var config := BustleAmbitionConfig.new()
	var business := config.find(&"open_business")
	business.enabled = true
	config.templates = [business] as Array[BustleAmbitionDef]
	return config


func _person(greed: float) -> BustlePersonality:
	var person := BustlePersonality.new()
	person.set_slider(&"greed", greed)
	return person


func _update(now: int, inputs: Dictionary = CAN) -> Dictionary:
	return _ambitions.update(now, _greedy, inputs.duplicate())


func test_the_template_is_in_the_default_library_switched_off() -> void:
	var library := BustleAmbitionConfig.new()
	var business := library.find(&"open_business")
	assert_not_null(business)
	assert_eq(library.templates.back(), business, "appended after learn_trade")
	assert_false(business.enabled, "off until a host turns it on")
	assert_eq(business.weights, {&"greed": 1.0, &"boldness": 0.4} as Dictionary[StringName, float])
	assert_eq(business.min_sliders, {&"greed": 50.0} as Dictionary[StringName, float])
	assert_eq(business.requires, [&"can_open_business"] as Array[StringName])
	assert_eq(business.done_fact, &"business_opened")
	assert_eq(business.done_facts, [] as Array[StringName])
	assert_eq(business.moot_facts, [&"cannot_open_business"] as Array[StringName])
	assert_eq(business.progress_input, &"", "no wallet line or other progress")
	assert_eq(business.boosts, {&"work": 1.5, &"trade": 1.3} as Dictionary[StringName, float])
	assert_eq(business.target_input, &"", "boosts aren't narrowed")
	assert_eq(business.subject_input, &"")
	assert_eq(business.next, &"")
	assert_true(business.is_valid())


func test_switched_off_it_is_never_assigned() -> void:
	var library := BustleAmbitionConfig.new()
	for def: BustleAmbitionDef in library.templates:
		def.enabled = false
	_ambitions = BustleAmbitions.new(&"baker", library)
	assert_true(_update(0).is_empty(), "everything off, open_business included")
	var keen := BustleAmbitions.new(&"baker", BustleAmbitionConfig.new())
	keen.pin = &"open_business"
	assert_ne(keen.update(0, _greedy, CAN.duplicate()).get("id", ""), "open_business", "not even pinned, with can_open_business")


func test_assigned_only_when_the_host_says_it_can_and_greed_is_at_least_50() -> void:
	assert_true(_update(0, {}).is_empty(), "without can_open_business")
	assert_true(_update(0, {"can_open_business": false}).is_empty())
	var started := _update(10)
	assert_eq(started.get("id"), "open_business")
	assert_eq(started["target"], "", "no subject")
	assert_eq(started["progress"], 0.0)
	var other := BustleAmbitions.new(&"smith", _config)
	assert_true(other.update(0, _person(49.0), CAN.duplicate()).is_empty(), "greed under 50")
	assert_eq(other.update(0, _person(50.0), CAN.duplicate()).get("id"), "open_business", "greed 50")


func test_done_when_the_host_says_it_opened_with_the_deed_and_the_cooldown() -> void:
	var social := BustleSocialStore.new()
	_ambitions.social = social
	watch_signals(_ambitions)
	_update(0)
	assert_eq(_update(DAY).get("id"), "open_business", "still its aim while the host says nothing")
	assert_true(_update(2 * DAY, {"can_open_business": true, "business_opened": true}).is_empty(), "done")
	assert_signal_emitted_with_parameters(_ambitions, "ambition_completed",
		[&"baker", &"open_business", {"id": "open_business", "since": 0, "progress": 0.0, "target": "",
			"last_target": "", "completed_at": 2 * DAY}])
	var deed: Dictionary = social.deeds_of(&"baker", 1)[0]
	assert_eq([deed["verb"], deed["target"]], [BustleAmbitions.DEED, &"open_business"])
	assert_true(_update(2 * DAY + 7 * DAY - 10).is_empty(), "within 7 days, with the fact cleared")
	assert_eq(_update(2 * DAY + 7 * DAY).get("id"), "open_business", "after the cooldown")


func test_a_business_still_open_keeps_it_from_starting_again() -> void:
	var opened := {"can_open_business": true, "business_opened": true}
	_update(0)
	_update(DAY, opened)
	assert_true(_update(DAY + 7 * DAY, opened).is_empty(), "after the cooldown, the host still says it's open")
	assert_true(_update(DAY + 30 * DAY, opened).is_empty())
	assert_eq(_update(DAY + 31 * DAY).get("id"), "open_business", "once the host clears it, it can start again")


func test_an_agent_that_already_has_a_business_never_takes_it_on() -> void:
	assert_true(_update(0, {"can_open_business": true, "business_opened": true}).is_empty())
	assert_eq(_ambitions.export_state(), {"active": {}, "completed": {}}, "nothing started or completed")


func test_moot_when_the_host_says_it_cannot() -> void:
	_update(0)
	watch_signals(_ambitions)
	assert_true(_update(10, {"can_open_business": true, "cannot_open_business": true}).is_empty())
	assert_signal_emitted_with_parameters(_ambitions, "ended_moot", [&"baker", &"open_business", &"cannot_open_business"])
	assert_true(_update(20, {"can_open_business": true, "cannot_open_business": true}).is_empty(), "not while it holds")
	assert_eq(_update(30).get("id"), "open_business", "assigned again at once once it's lifted: no cooldown")


func test_boosts_work_and_trade_for_any_option_and_never_a_fight() -> void:
	_update(0)
	assert_eq(_ambitions.boost(&"work", &"mill"), 1.5, "not narrowed to anything")
	assert_eq(_ambitions.boost(&"work"), 1.5)
	assert_eq(_ambitions.boost(&"trade", &"anyone"), 1.3, "a host with no trade goal never asks")
	assert_eq(_ambitions.boost(&"train"), 1.0)
	assert_eq(_ambitions.boost(&"explore"), 1.0)
	_config.find(&"open_business").boosts[&"steal"] = 3.0
	assert_eq(_ambitions.boost(&"steal"), 1.0, "never_boost holds")
	_update(10, {"can_open_business": true, "locked": true})
	assert_eq(_ambitions.boost(&"work"), 1.0, "off while locked")
	assert_eq(_ambitions.active().get("id"), "open_business", "and still assigned")


func test_it_saves_and_loads() -> void:
	_update(0)
	_update(DAY)
	var saved := _ambitions.export_state()
	assert_eq(saved["active"]["id"], "open_business")
	var loaded := BustleAmbitions.new(&"baker", _config)
	assert_true(loaded.import_state(saved.duplicate(true)))
	assert_eq(loaded.active(), _ambitions.active())
	assert_eq(loaded.export_state(), saved)
	assert_eq(loaded.boost(&"trade"), 1.3)


func test_the_same_inputs_give_the_same_run() -> void:
	var runs: Array = []
	for attempt: int in 2:
		before_each()
		var log: Array = []
		for step: int in 20:
			var inputs := {"can_open_business": step % 5 != 4, "business_opened": step == 6, "cannot_open_business": step == 12}
			log.append(_update(step * DAY, inputs).duplicate())
		runs.append([log, _ambitions.export_state()])
	assert_eq(runs[1], runs[0])


func test_the_default_library_is_unchanged_with_it_off() -> void:
	var curious := BustlePersonality.new()
	curious.set_slider(&"curiosity", 70.0)
	var plain := BustleAmbitions.new(&"baker", BustleAmbitionConfig.new())
	assert_eq(plain.update(0, curious, CAN.duplicate()).get("id"), "leave_settlement",
		"the same choice as without open_business, even with can_open_business set")
