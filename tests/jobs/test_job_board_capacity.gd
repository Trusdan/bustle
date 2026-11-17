# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Work types that name minimum capacities: an agent below one isn't offered the work, can't claim
## it (with a reason), and lets go of a claim it holds at the next update. Without minimums, with the
## default port, or with health left out, nothing changes. Nothing is random, and saves round-trip.

const Health := preload("res://tests/health/fake_health_port.gd")

var _ports: BustlePorts
var _health: Health
var _board: BustleJobBoard
var _changes: Array = []


func _seeker(id: StringName) -> BustleJobSeeker:
	return BustleJobSeeker.new(id)


func before_each() -> void:
	_ports = BustlePorts.new()
	_health = Health.new()
	_ports.health = _health
	var haul := BustleWorkType.new()
	haul.id = &"haul"
	haul.minutes = 60
	haul.min_capacities = {&"moving": 0.5, &"manipulation": 0.3}
	var tally := BustleWorkType.new()
	tally.id = &"tally"
	tally.minutes = 60
	_board = BustleJobBoard.new([haul, tally] as Array[BustleWorkType], _ports)
	_changes = []
	_board.changed.connect(func(job: StringName, what: StringName, agent: StringName) -> void: _changes.append([job, what, agent]))


func test_the_minimums_are_optional_data_checked_for_range() -> void:
	var fresh := BustleWorkType.new()
	assert_eq(fresh.min_capacities, {} as Dictionary[StringName, float], "empty by default")
	fresh.id = &"x"
	assert_true(fresh.is_valid())
	for bad: Dictionary in [{&"": 0.5}, {&"moving": -0.1}, {&"moving": 1.5}, {&"moving": NAN}]:
		fresh.min_capacities.assign(bad)
		assert_false(fresh.is_valid(), str(bad))
	fresh.min_capacities = {&"moving": 1.0, &"sight": 0.0}
	assert_true(fresh.is_valid(), "0 and 1 are both allowed")


func test_an_agent_below_a_minimum_is_not_offered_the_work() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	_board.post(&"tally", &"mill", 0)
	_health.capacities = {&"baker": {&"moving": 0.4}}
	var senses := BustleSenses.new()
	assert_eq(_board.advertise(_seeker(&"baker"), senses), 1, "only the work with no minimum")
	assert_eq(senses.advertisements[0].option_id, &"job_2")
	assert_false(_board.can_do(_seeker(&"baker"), job))
	assert_eq(_board.best_for(_seeker(&"baker")), &"job_2")
	_health.capacities = {&"baker": {&"moving": 0.5}}
	assert_true(_board.can_do(_seeker(&"baker"), job), "at the minimum is enough")


func test_a_claim_below_a_minimum_is_refused_with_a_reason() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	_changes = []
	_health.capacities = {&"baker": {&"moving": 0.2, &"manipulation": 0.1}}
	assert_false(_board.claim(_seeker(&"baker"), job, 0))
	assert_eq(_board.refusal(_seeker(&"baker"), job), &"capacity:manipulation", "the first short one, by name")
	_health.capacities = {&"baker": {&"moving": 0.2}}
	assert_eq(_board.refusal(_seeker(&"baker"), job), &"capacity:moving")
	assert_eq(_changes, [], "nothing changed")
	_health.capacities = {}
	assert_eq(_board.refusal(_seeker(&"baker"), job), &"")
	assert_true(_board.claim(_seeker(&"baker"), job, 0))
	assert_eq(_board.refusal(_seeker(&"smith"), job), &"taken")
	assert_eq(_board.refusal(_seeker(&"baker"), &"job_9"), &"unknown_job")
	assert_eq(_board.refusal(null, job), &"no_seeker")
	var other := _board.post(&"tally", &"mill", 0)
	assert_eq(_board.refusal(_seeker(&"baker"), other), &"holds_claim")


func test_the_other_refusals_name_their_gate() -> void:
	var gated := BustleWorkType.new()
	gated.id = &"guard"
	gated.required_role = &"warden"
	var skilled := BustleWorkType.new()
	skilled.id = &"mend"
	skilled.skill = &"smithing"
	skilled.min_skill = 2.0
	var tagged := BustleWorkType.new()
	tagged.id = &"climb"
	tagged.required_tags = [&"ladder"]
	var board := BustleJobBoard.new([gated, skilled, tagged] as Array[BustleWorkType], _ports)
	assert_eq(board.refusal(_seeker(&"baker"), board.post(&"guard", &"town", 0)), &"role")
	assert_eq(board.refusal(_seeker(&"baker"), board.post(&"mend", &"town", 0)), &"skill")
	assert_eq(board.refusal(_seeker(&"baker"), board.post(&"climb", &"town", 0)), &"tags")


func test_assign_and_settle_pass_over_an_agent_below_a_minimum() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	_health.capacities = {&"baker": {&"moving": 0.1}}
	assert_eq(_board.assign([_seeker(&"baker"), _seeker(&"smith")] as Array[BustleJobSeeker], 0), {&"smith": job})
	_board.release(job)
	_board.request(_seeker(&"baker"), job)
	assert_eq(_board.settle(5), {} as Dictionary[StringName, StringName], "its request isn't granted")


func test_dropping_below_a_minimum_releases_the_claim_at_the_next_update() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	assert_true(_board.claim(_seeker(&"baker"), job, 0))
	_health.capacities = {&"baker": {&"moving": 0.3}}
	assert_eq(_board.claimed_of(&"baker"), job, "nothing happens until the next update")
	assert_eq(_board.settle(10), {} as Dictionary[StringName, StringName])
	assert_eq(_board.claimed_of(&"baker"), &"", "let go at the next settle")
	assert_true(_board.posting(job).is_open(), "open again for others")
	assert_eq(_changes.back(), [job, &"released", &"baker"], "the usual release")
	assert_true(_board.claim(_seeker(&"smith"), job, 11))
	_health.capacities = {&"smith": {&"manipulation": 0.0}}
	assert_false(_board.work(_seeker(&"smith"), 30), "working lets go too, and adds nothing")
	assert_eq(_board.posting(job).progress, 0)
	assert_eq(_changes.back(), [job, &"released", &"smith"])


func test_release_unfit_lets_go_of_every_unfit_claim_in_order() -> void:
	var first := _board.post(&"haul", &"mill", 0)
	var second := _board.post(&"haul", &"mill", 0)
	var easy := _board.post(&"tally", &"mill", 0)
	_board.claim(_seeker(&"smith"), first, 0)
	_board.claim(_seeker(&"baker"), second, 0)
	_board.claim(_seeker(&"miller"), easy, 0)
	_health.capacities = {&"smith": {&"moving": 0.0}, &"baker": {&"moving": 0.0}, &"miller": {&"moving": 0.0}}
	assert_eq(_board.release_unfit(), [first, second] as Array[StringName], "not the work with no minimum")
	assert_eq(_board.claimed_of(&"miller"), easy)
	assert_eq(_board.release_unfit(), [] as Array[StringName])


func test_an_unusable_reading_counts_as_full() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	_health.capacities = {&"baker": {&"moving": NAN, &"manipulation": INF}}
	assert_true(_board.can_do(_seeker(&"baker"), job), "as the health behaviour reads it")


func test_without_minimums_a_port_or_health_nothing_changes() -> void:
	_health.capacities = {&"baker": {&"moving": 0.0, &"manipulation": 0.0}}
	var plain := _board.post(&"tally", &"mill", 0)
	assert_true(_board.claim(_seeker(&"baker"), plain, 0), "no minimums: no health gate")
	var quiet := BustleJobBoard.new([_board.type_of(&"haul")] as Array[BustleWorkType], BustlePorts.new())
	var job := quiet.post(&"haul", &"mill", 0)
	assert_true(quiet.claim(_seeker(&"baker"), job, 0), "the default port: everyone is fully able")
	assert_eq(quiet.release_unfit(), [] as Array[StringName])
	var bare := BustleJobBoard.new([_board.type_of(&"haul")] as Array[BustleWorkType])
	assert_true(bare.claim(_seeker(&"baker"), bare.post(&"haul", &"mill", 0), 0), "no ports at all")
	var none := BustlePorts.new()
	none.health = null
	var nulled := BustleJobBoard.new([_board.type_of(&"haul")] as Array[BustleWorkType], none)
	assert_true(nulled.claim(_seeker(&"baker"), nulled.post(&"haul", &"mill", 0), 0), "a null health port")
	assert_eq(nulled.release_unfit(), [] as Array[StringName])


func test_saves_round_trip_and_a_released_claim_stays_released() -> void:
	var job := _board.post(&"haul", &"mill", 0)
	_board.claim(_seeker(&"baker"), job, 0)
	_board.work(_seeker(&"baker"), 20)
	var held := _board.export_state()
	_health.capacities = {&"baker": {&"moving": 0.1}}
	_board.settle(30)
	var released := _board.export_state()
	assert_ne(released, held)
	var copy := BustleJobBoard.new([_board.type_of(&"haul"), _board.type_of(&"tally")] as Array[BustleWorkType], _ports)
	assert_true(copy.import_state(JSON.parse_string(JSON.stringify(held))), "also through JSON")
	assert_eq(copy.claimed_of(&"baker"), job, "a claim saved before the drop loads as held")
	assert_eq(copy.release_unfit(), [job] as Array[StringName], "and is let go at the next update")
	assert_eq(copy.export_state(), released, "the same as the board that let go of it")


func test_short_capacity_is_by_name_order_and_makes_no_rolls() -> void:
	var def: BustleWorkType = _board.type_of(&"haul")
	_health.capacities = {&"baker": {&"moving": 0.0, &"manipulation": 0.0}}
	assert_eq(def.short_capacity(&"baker", _health), &"manipulation")
	assert_eq(def.short_capacity(&"baker", null), &"")
	for path: String in ["res://addons/bustle/core/jobs/job_board.gd", "res://addons/bustle/core/jobs/work_type.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])
