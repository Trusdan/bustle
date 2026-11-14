# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## A death for an agent the module has no age for: recorded and released exactly like an aged
## agent's, closed off afterwards, refused a second time, and saved.

const Rules := preload("res://tests/life_stages/test_life_stage_rules.gd")
const DAY := 1440

var _events: Array = []


func _module(rules: BustleLifeStageRules = Rules.three()) -> BustleLifeStages:
	_events = []
	var module := BustleLifeStages.new(rules)
	module.stage_changed.connect(func(id: StringName, old: StringName, new: StringName) -> void: _events.append(["stage", id, old, new]))
	module.died.connect(func(id: StringName, cause: String) -> void: _events.append(["died", id, cause]))
	module.vacated.connect(func(id: StringName, kind: StringName, what: StringName) -> void: _events.append(["vacated", id, kind, what]))
	return module


func test_an_ageless_death_releases_everything_in_order_and_closes_the_agent() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"a", &"warden": &"a", &"cook": &"b"}
	var roles := BustleRolesPort.new(table)
	var block := BustleScheduleBlock.new()
	block.activity = &"work"
	block.start_minute = 480
	block.end_minute = 960
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.day = day
	var schedules := BustleRoleSchedules.new()
	schedules.schedules = {&"clerk": routine}
	var roster := BustleScheduleRoster.new(roles, schedules)
	roster.add_agent(&"a")
	var rank := BustleCareerRank.new()
	rank.id = &"junior"
	var track := BustleCareerDef.new()
	track.id = &"office"
	track.role = &"clerk"
	track.activity = &"work"
	track.ranks = [rank]
	var careers := BustleCareers.new([track] as Array[BustleCareerDef], roster, BustlePorts.new())
	assert_true(careers.assign(&"a", &"office", &"junior", 0))
	var errand := BustleWorkType.new()
	errand.id = &"errand"
	var board := BustleJobBoard.new([errand] as Array[BustleWorkType], BustlePorts.new())
	var job := board.post(&"errand", &"shop", 0)
	assert_true(board.claim(BustleJobSeeker.new(&"a", BustlePersonality.new(), {} as Dictionary[StringName, float], []), job, 0))
	var module := _module()
	module.roles = roles
	module.jobs = board
	module.careers = careers
	module.set_age(&"b", 3000.0)
	_events = []
	assert_false(module.has_age(&"a"), "never set or born")
	assert_eq(module.note_death(&"a", "illness"), "")
	assert_eq(_events, [["died", &"a", "illness"], ["vacated", &"a", &"career", &"office"],
		["vacated", &"a", &"job", job], ["vacated", &"a", &"role", &"clerk"], ["vacated", &"a", &"role", &"warden"]])
	assert_eq(careers.career_of(&"a"), &"")
	assert_eq(board.claimed_of(&"a"), &"")
	assert_true(board.posting(job).is_open())
	assert_eq(roles.roles_of(&"a"), PackedStringArray())
	assert_eq(roles.holder_of(&"cook"), &"b")
	assert_true(module.is_dead(&"a"))
	assert_eq(module.cause_of(&"a"), "illness")
	assert_false(module.has_age(&"a"), "a death gives no age")
	assert_eq(module.stage_of(&"a"), &"")
	assert_false(module.allows_goal(&"a", [&"anything"]))
	assert_false(module.allows_affordance(&"a", [] as Array[StringName]))
	assert_false(module.set_age(&"a", 10.0))
	assert_eq(module.birth(&"a"), "'a' is already known")
	assert_eq(module.living_ids(), [&"b"] as Array[StringName])
	module.advance_to(10 * DAY)
	assert_eq(module.living_ids(), [&"b"] as Array[StringName], "never scheduled again")


func test_a_repeat_death_is_refused_and_fires_nothing() -> void:
	var module := _module()
	assert_eq(module.note_death(&"a", "illness"), "")
	_events = []
	assert_eq(module.note_death(&"a", "illness"), "'a' has already died")
	assert_eq(module.note_death(&"a", "accident"), "'a' has already died")
	assert_eq(_events, [])
	assert_eq(module.cause_of(&"a"), "illness", "the first cause stands")


func test_still_refused_empty_id_and_bad_rules() -> void:
	var module := _module()
	assert_eq(module.note_death(&"", "illness"), "an agent needs an id")
	assert_eq(module.note_death(&"a", ""), "'a': a death needs a cause")
	var broken := _module(Rules.rules([]))
	assert_eq(broken.note_death(&"a", "illness"), "there are no stages")
	assert_eq(_events, [])
	assert_false(broken.is_dead(&"a"))


func test_an_ageless_death_survives_a_save() -> void:
	var module := _module()
	module.set_age(&"b", 10.0)
	module.advance_to(DAY)
	module.note_death(&"a", "illness")
	var saved := module.export_state()
	assert_eq(saved["dead"], {"a": {"cause": "illness", "at": DAY}})
	assert_false(saved["ages"].has("a"))
	var loaded := _module()
	assert_true(loaded.import_state(saved))
	assert_eq(_events, [], "loading fires nothing")
	assert_eq(loaded.export_state(), saved)
	assert_true(loaded.is_dead(&"a"))
	assert_false(loaded.has_age(&"a"))
	assert_eq(loaded.note_death(&"a", "illness"), "'a' has already died")
	assert_false(loaded.allows_goal(&"a", [] as Array[StringName]))
	assert_eq(loaded.living_ids(), [&"b"] as Array[StringName])
	assert_true(loaded.import_state({"version": 1, "ages": {"b": 5.0}, "stages": {"b": "young"}}), "old saves still load")
	assert_false(loaded.is_dead(&"a"))
