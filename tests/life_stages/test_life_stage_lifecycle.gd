# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Birth and death: the host's hooks. A birth starts in a valid stage; a death fires once, stops
## aging and gating, and releases the career, job claim and roles it held. All of it is saved.

const Rules := preload("res://tests/life_stages/test_life_stage_rules.gd")
const DAY := 1440

var _events: Array = []


func _module(rules: BustleLifeStageRules = Rules.three()) -> BustleLifeStages:
	_events = []
	var module := BustleLifeStages.new(rules)
	module.born.connect(func(id: StringName, days: float) -> void: _events.append(["born", id, days]))
	module.stage_changed.connect(func(id: StringName, old: StringName, new: StringName) -> void: _events.append(["stage", id, old, new]))
	module.died.connect(func(id: StringName, cause: String) -> void: _events.append(["died", id, cause]))
	module.vacated.connect(func(id: StringName, kind: StringName, what: StringName) -> void: _events.append(["vacated", id, kind, what]))
	return module


func test_a_birth_starts_in_a_stage() -> void:
	var module := _module()
	assert_eq(module.birth(&"baby"), "")
	assert_eq(_events, [["born", &"baby", 0.0], ["stage", &"baby", &"", &"young"]])
	assert_eq(module.age_days(&"baby"), 0.0)
	assert_eq(module.birth(&"newcomer", 2000.0), "")
	assert_eq(module.stage_of(&"newcomer"), &"grown")
	module.advance_to(10 * DAY)
	assert_eq(module.age_days(&"baby"), 10.0, "a newborn ages like anyone")


func test_a_bad_birth_is_refused_with_a_reason() -> void:
	var module := _module(Rules.rules([Rules.stage(&"grown", 100.0)]))
	module.birth(&"known", 150.0)
	_events = []
	assert_eq(module.birth(&""), "an agent needs an id")
	assert_eq(module.birth(&"known"), "'known' is already known")
	assert_eq(module.birth(&"x", -1.0), "'x': age must be finite and not negative")
	assert_eq(module.birth(&"x", NAN), "'x': age must be finite and not negative")
	assert_eq(module.birth(&"x", 50.0), "'x': age 50.0 days is below the first stage ('grown')")
	assert_eq(_events, [], "a refused birth fires nothing")
	assert_false(module.has_age(&"x"))
	assert_eq(_module(Rules.rules([])).birth(&"x"), "there are no stages")


func test_a_death_fires_once_and_stops_the_agent() -> void:
	var module := _module()
	module.set_age(&"a", 3000.0)
	module.set_age(&"b", 10.0)
	_events = []
	module.advance_to(DAY)
	assert_eq(module.note_death(&"a", "illness"), "")
	assert_eq(_events, [["died", &"a", "illness"]])
	assert_true(module.is_dead(&"a"))
	assert_eq(module.cause_of(&"a"), "illness")
	assert_eq(module.living_ids(), [&"b"] as Array[StringName], "no longer scheduled")
	assert_false(module.allows_goal(&"a", [&"anything"]))
	assert_false(module.allows_affordance(&"a", []))
	assert_eq(module.note_death(&"a", "again"), "'a' has already died")
	assert_eq(module.note_death(&"nobody", "illness"), "'nobody' has no age")
	assert_eq(module.note_death(&"b", ""), "'b': a death needs a cause")
	assert_false(module.set_age(&"a", 5.0))
	assert_eq(module.birth(&"a"), "'a' is already known")
	module.advance_to(9000 * DAY)
	assert_eq(module.age_days(&"a"), 3001.0, "the dead don't age")
	assert_eq(module.stage_of(&"a"), &"grown", "and keep their last stage")
	assert_eq(_events.filter(func(e: Array) -> bool: return e[0] == "died").size(), 1)


func test_a_death_releases_career_job_and_roles() -> void:
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
	module.set_age(&"a", 3000.0)
	_events = []
	assert_eq(module.note_death(&"a", "accident"), "")
	assert_eq(_events, [["died", &"a", "accident"], ["vacated", &"a", &"career", &"office"],
		["vacated", &"a", &"job", job], ["vacated", &"a", &"role", &"clerk"], ["vacated", &"a", &"role", &"warden"]])
	assert_eq(careers.career_of(&"a"), &"")
	assert_eq(board.claimed_of(&"a"), &"")
	assert_true(board.posting(job).is_open(), "the posting is open again")
	assert_eq(roles.roles_of(&"a"), PackedStringArray())
	assert_eq(roles.holder_of(&"clerk"), &"", "nobody is put in: refilling is the host's call")
	assert_eq(roles.holder_of(&"cook"), &"b", "others keep theirs")


func test_a_death_with_nothing_attached_only_fires_died() -> void:
	var module := _module()
	module.set_age(&"a", 3000.0)
	_events = []
	module.note_death(&"a", "illness")
	assert_eq(_events, [["died", &"a", "illness"]])


func test_everything_survives_a_save_and_carries_on_exactly() -> void:
	var module := _module()
	module.set_age(&"a", 1590.0)
	module.advance_to(DAY + 30)
	module.birth(&"b")
	module.set_age(&"c", 3000.0)
	module.advance_to(2 * DAY)
	module.note_death(&"c", "illness")
	var saved := module.export_state()
	var loaded := _module()
	assert_true(loaded.import_state(saved))
	assert_eq(_events, [], "loading fires nothing")
	assert_eq(loaded.export_state(), saved)
	assert_true(loaded.is_dead(&"c"))
	assert_eq(loaded.cause_of(&"c"), "illness")
	module.advance_to(40 * DAY + 7)
	loaded.advance_to(40 * DAY + 7)
	assert_eq(loaded.export_state(), module.export_state(), "aging after a load is exact")
	assert_eq(loaded.stage_of(&"a"), &"grown")


func test_a_version_1_save_loads_and_bad_saves_are_refused() -> void:
	var module := _module()
	assert_true(module.import_state({"version": 1, "ages": {"a": 10.0}, "stages": {"a": "young"}}))
	assert_eq(module.now(), 0)
	module.advance_to(DAY)
	assert_eq(module.age_days(&"a"), 11.0)
	module.note_death(&"a", "illness")
	var good := module.export_state()
	var bad: Array[Dictionary] = []
	for i: int in 6:
		bad.append(good.duplicate(true))
	bad[0]["dead"]["a"]["cause"] = ""
	bad[1]["dead"]["z"] = {"cause": "illness", "at": 0}
	bad[2]["anchors"]["a"] = [10.0, DAY + 5]
	bad[3]["anchors"]["a"] = [-1.0, 0]
	bad[4].erase("anchors")
	bad[5]["now"] = -1
	var target := _module()
	target.set_age(&"q", 2000.0)
	var before := target.export_state()
	for saved: Dictionary in bad:
		assert_false(target.import_state(saved))
		assert_eq(target.export_state(), before)


func test_the_same_calls_give_the_same_state() -> void:
	var states: Array[Dictionary] = []
	for i: int in 2:
		var module := _module()
		module.birth(&"a")
		module.set_age(&"b", 5900.0)
		module.advance_to(300 * DAY)
		module.note_death(&"b", "illness")
		module.advance_to(301 * DAY)
		states.append(module.export_state())
	assert_eq(states[0], states[1])
