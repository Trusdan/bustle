# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## An OFF_SCREEN agent's backlog in tick() is bounded by the catch-up cap: a long clock jump is
## summarised beyond the cap, split exactly as catch_up() splits it, and the kept week is thought
## one interval a tick; a backlog within the cap is untouched; a clock that runs fast never piles
## up more than the cap. Deterministic.

const DAY := 1440
const JUMP := 365 * DAY + 100


## Everyone is far away.
class Far:
	extends BustleWorldPort

	func area_of(_id: StringName) -> StringName:
		return &"far"

	func player_area() -> StringName:
		return &"square"


var _thinks: Array = []
var _summaries: Array = []
var _caught: Array = []


func _library() -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	for id: StringName in [&"a", &"b", &"c"]:
		var goal := BustleGoalDef.new()
		goal.id = id
		goal.band = BustleBands.PERSONAL
		library.goals.append(goal)
	return library


# A society with one far-away agent, already sorted OFF_SCREEN, last updated at minute [param last].
func _setup(last: int) -> Array:
	var society := BustleSociety.new(9)
	society.register_archetype(&"villager", _library())
	society.set_port(&"world", Far.new())
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	var rings := BustleSimRings.new(society, config)
	rings.senses_provider = func(id: StringName, _ring: int, minute: int) -> BustleSenses:
		_thinks.append([id, minute])
		return BustleSenses.new()
	rings.summary_hook = func(id: StringName, report: Dictionary) -> void: _summaries.append([id, report.duplicate()])
	rings.caught_up.connect(func(id: StringName, report: Dictionary) -> void: _caught.append([id, report.duplicate()]))
	var agent := society.add_agent(&"a", &"villager")
	rings.tick(0.0)
	agent.last_update_minute = last
	_thinks = []
	_summaries = []
	_caught = []
	return [society, rings, agent]


func _minutes() -> Array:
	return _thinks.map(func(t: Array) -> int: return t[1])


func test_a_year_long_jump_thinks_only_the_capped_week_and_summarises_the_rest() -> void:
	var run := _setup(100)
	var society: BustleSociety = run[0]
	var rings: BustleSimRings = run[1]
	var agent: BustleNpcState = run[2]
	society.ports.clock.advance(JUMP)
	for frame in 400:
		rings.tick(0.0)
	assert_eq(_thinks.size(), 168, "7 days × 24 thinks, however many frames")
	assert_eq(_summaries.size(), 1, "summarised once")
	assert_eq(_summaries[0][1]["skipped_minutes"], (365 - 7) * DAY)
	assert_eq(_caught.size(), 1, "caught_up fires")
	assert_eq(_caught[0][1], {"agent": &"a", "from": 100, "to": JUMP, "ticks": 168,
		"simulated_minutes": 168 * 60, "skipped_minutes": (365 - 7) * DAY})
	assert_eq(agent.last_update_minute, society.ports.clock.now_minutes(), "no part interval left over")


func test_draining_in_tick_matches_one_catch_up_exactly() -> void:
	var by_tick := _setup(100)
	(by_tick[0] as BustleSociety).ports.clock.advance(JUMP)
	for frame in 400:
		(by_tick[1] as BustleSimRings).tick(0.0)
	var tick_minutes := _minutes()
	var tick_hash: String = (by_tick[0] as BustleSociety).state_hash()
	var by_catch_up := _setup(100)
	(by_catch_up[0] as BustleSociety).ports.clock.advance(JUMP)
	(by_catch_up[1] as BustleSimRings).catch_up(&"a")
	assert_eq(tick_minutes, _minutes(), "the same thinks at the same game minutes")
	assert_eq((by_tick[2] as BustleNpcState).last_update_minute, (by_catch_up[2] as BustleNpcState).last_update_minute)
	assert_eq(tick_hash, (by_catch_up[0] as BustleSociety).state_hash(), "the same state")


func test_a_backlog_within_the_cap_is_thought_as_before() -> void:
	for backlog: int in [5 * 60, 3 * DAY + 30]:
		var run := _setup(0)
		(run[0] as BustleSociety).ports.clock.advance(backlog)
		for frame in 200:
			(run[1] as BustleSimRings).tick(0.0)
		var ticks := backlog / 60
		var expected: Array = []
		for i in ticks:
			expected.append((i + 1) * 60)
		assert_eq(_minutes(), expected, "one think an interval, one a tick, at the same minutes")
		assert_eq(_summaries, [], "nothing summarised")
		assert_eq(_caught, [], "no extra caught_up")
		assert_eq((run[2] as BustleNpcState).last_update_minute, ticks * 60, "a part interval carries over")
		var hash: String = (run[0] as BustleSociety).state_hash()
		var reference := _setup(0)
		(reference[0] as BustleSociety).ports.clock.advance(backlog)
		(reference[1] as BustleSimRings).catch_up(&"a")
		assert_eq(hash, (reference[0] as BustleSociety).state_hash(), "the same state as catching up at once")


func _fast_clock() -> Array:
	var run := _setup(0)
	var society: BustleSociety = run[0]
	var agent: BustleNpcState = run[2]
	var worst := 0
	for frame in 300:
		society.ports.clock.advance(6 * 60)
		(run[1] as BustleSimRings).tick(0.0)
		worst = maxi(worst, society.ports.clock.now_minutes() - agent.last_update_minute)
	return [society, agent, worst]


func test_a_fast_clock_never_piles_up_more_than_the_cap() -> void:
	var result := _fast_clock()
	var society: BustleSociety = result[0]
	var agent: BustleNpcState = result[1]
	assert_lte(int(result[2]), 7 * DAY, "the backlog stays within the cap")
	assert_eq(_thinks.size(), 300, "one think a tick, as before")
	assert_gt(_summaries.size(), 0, "the older time was summarised")
	var skipped := 0
	for summary: Array in _summaries:
		skipped += int(summary[1]["skipped_minutes"])
	var behind := society.ports.clock.now_minutes() - agent.last_update_minute
	assert_eq(skipped + _thinks.size() * 60 + behind, 300 * 6 * 60, "every minute is thought, summarised or still to come")


func test_both_bounds_are_deterministic() -> void:
	var hashes: Array = []
	for run in 2:
		var jump := _setup(100)
		(jump[0] as BustleSociety).ports.clock.advance(JUMP)
		for frame in 400:
			(jump[1] as BustleSimRings).tick(0.0)
		var fast := _fast_clock()
		hashes.append([(jump[0] as BustleSociety).state_hash(), (fast[0] as BustleSociety).state_hash()])
	assert_eq(hashes[0], hashes[1])
