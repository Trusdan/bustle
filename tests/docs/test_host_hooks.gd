# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The 1.1 hooks page (docs/host-hooks.md) stays true: every snippet compiles as written, names only
## real classes and pages, and does what the page says when called against real objects.

const PAGE := "res://docs/host-hooks.md"
const Health := preload("res://tests/health/fake_health_port.gd")
const DAY := 1440


static func _blocks() -> Array[String]:
	var out: Array[String] = []
	for found: RegExMatch in RegEx.create_from_string("(?s)```gdscript\\n(.*?)```").search_all(FileAccess.get_file_as_string(PAGE)):
		out.append(found.get_string(1))
	return out


static func _compile(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source if source.begins_with("extends ") else "extends RefCounted\n\n" + source
	return script if script.reload() == OK else null


# An instance of the snippet that defines [param function].
func _snippet(function: String) -> RefCounted:
	for block: String in _blocks():
		if block.contains("func %s(" % function):
			var script := _compile(block)
			assert_not_null(script, function)
			return script.new() if script != null else null
	fail_test("no snippet defines %s" % function)
	return null


func test_every_snippet_compiles() -> void:
	var blocks := _blocks()
	assert_eq(blocks.size(), 6, "one per section")
	for block: String in blocks:
		assert_not_null(_compile(block), "compiles:\n%s" % block.left(120))


func test_the_page_names_only_real_classes_and_pages() -> void:
	var classes: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes.append(String(entry["class"]))
	var text := FileAccess.get_file_as_string(PAGE)
	for found: RegExMatch in RegEx.create_from_string("\\b(Bustle[A-Z][A-Za-z]*)\\b").search_all(text):
		assert_true(classes.has(found.get_string(1)), "class %s exists" % found.get_string(1))
	for found: RegExMatch in RegEx.create_from_string("`((?:addons|demo|docs|tests|tools)/[A-Za-z0-9_./]+?)`").search_all(text):
		assert_true(FileAccess.file_exists("res://" + found.get_string(1)), "%s exists" % found.get_string(1))
	for found: RegExMatch in RegEx.create_from_string("\\]\\(([a-z][\\w./-]*\\.md)(#[\\w-]+)?\\)").search_all(text):
		var page := "res://docs".path_join(found.get_string(1))
		assert_true(FileAccess.file_exists(page), "link %s exists" % found.get_string(1))
		var anchor := found.get_string(2).trim_prefix("#")
		if anchor != "" and FileAccess.file_exists(page):
			var slugs: Array[String] = []
			for heading: RegExMatch in RegEx.create_from_string("(?m)^#+ (.+)$").search_all(FileAccess.get_file_as_string(page)):
				slugs.append(RegEx.create_from_string("[^a-z0-9 -]").sub(heading.get_string(1).to_lower(), "", true).replace(" ", "-"))
			assert_true(slugs.has(anchor), "%s has a heading for #%s" % [found.get_string(1), anchor])


func test_career_periods_and_the_window_reset() -> void:
	var snippet := _snippet("add_busy_season")
	var rank := BustleCareerRank.new()
	rank.id = &"junior"
	rank.review_days = 3
	snippet.call(&"add_busy_season", rank)
	assert_eq(rank.periods[&"busy_season"].review_days, 2)
	var block := BustleScheduleBlock.new()
	block.activity = &"work"
	block.start_minute = 480
	block.end_minute = 960
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.day = day
	var table := BustleRoleTable.new()
	table.holders = {&"clerk": &"clerk_1"}
	var jobs := BustleRoleSchedules.new()
	jobs.schedules = {&"clerk": routine}
	var roster := BustleScheduleRoster.new(BustleRolesPort.new(table), jobs)
	roster.add_agent(&"clerk_1")
	var def := BustleCareerDef.new()
	def.id = &"office"
	def.role = &"clerk"
	def.activity = &"work"
	def.ranks = [rank]
	var careers := BustleCareers.new([def] as Array[BustleCareerDef], roster)
	assert_true(careers.assign(&"clerk_1", &"office", &"junior", 0))
	for d: int in 2:
		roster.schedule_of(&"clerk_1").attend(d * DAY + 480, &"work")
	assert_eq(snippet.call(&"end_of_day", careers, &"clerk_1", DAY, &"busy_season"), [] as Array[Dictionary])
	assert_eq(careers.window_period(&"clerk_1"), &"busy_season")
	var reviews: Array[Dictionary] = snippet.call(&"end_of_day", careers, &"clerk_1", 2 * DAY, &"busy_season")
	assert_eq(reviews.size(), 1, "reviewed after the season's 2 days, not the rank's 3")
	roster.schedule_of(&"clerk_1").attend(2 * DAY + 480, &"work")
	assert_true(snippet.call(&"back_from_leave", careers, &"clerk_1", 3 * DAY))
	assert_true(is_nan(careers.performance(&"clerk_1")), "day 2 was closed, then dropped")
	assert_eq(careers.window_period(&"clerk_1"), &"")


func test_stolen_goods_after_they_change_hands() -> void:
	var snippet := _snippet("is_from_an_open_deed")
	var society := BustleSociety.new(1)
	society.register_archetype(&"villager", BustleGoalLibrary.new())
	for id: StringName in [&"baker", &"smith"]:
		society.add_agent(id, &"villager").area = &"market"
	society.ports.property.register(&"loaf", &"baker", &"market")
	var crime := BustleCrime.new(society)
	var watch := BustleCrimeWatch.new(crime)
	assert_false(snippet.call(&"is_from_an_open_deed", watch, &"loaf"))
	assert_true(crime.record_theft(&"stranger", &"baker", &"loaf", {"place": &"lane", "at": 10}))
	society.ports.property.transfer(&"loaf", &"baker", &"stranger")
	society.ports.property.transfer(&"loaf", &"stranger", &"smith")
	assert_true(snippet.call(&"is_from_an_open_deed", watch, &"loaf"), "sold on, still traced")
	assert_eq(snippet.call(&"stolen_items_on", watch, &"smith"), [&"loaf"] as Array[StringName])
	assert_eq(snippet.call(&"stolen_items_on", watch, &"baker"), [] as Array[StringName])


func test_a_cap_on_aspiration_points() -> void:
	var config := BustleAspirationConfig.new()
	var capped: BustleAspirationConfig = _snippet("with_point_cap").call(&"with_point_cap", config, 10)
	assert_eq(capped.max_points, 10)
	assert_eq(config.max_points, -1, "the original is left uncapped")
	var aspirations := BustleAspirations.new(&"baker", capped)
	assert_true(aspirations.add_points(8, &"want_met"))
	assert_true(aspirations.add_points(8, &"want_met"))
	assert_eq(aspirations.points(), 10, "stops at the cap")
	assert_false(aspirations.add_points(1, &"want_met"))


func test_work_that_needs_a_minimum_capacity() -> void:
	var snippet := _snippet("make_haul_work")
	var ports := BustlePorts.new()
	var health := Health.new()
	ports.health = health
	var board := BustleJobBoard.new([snippet.call(&"make_haul_work")] as Array[BustleWorkType], ports)
	var job := board.post(&"haul", &"mill", 0)
	health.capacities = {&"baker": {&"moving": 0.4}}
	assert_eq(snippet.call(&"why_not", board, &"baker", job), &"capacity:moving")
	assert_eq(snippet.call(&"why_not", board, &"smith", job), &"")
	assert_true(board.claim(BustleJobSeeker.new(&"smith"), job, 0))
	health.capacities = {&"smith": {&"manipulation": 0.1}}
	assert_eq(snippet.call(&"release_the_unfit", board), [job] as Array[StringName])
	assert_eq(board.claimed_of(&"smith"), &"")


func _brain(id: StringName, library: BustleGoalLibrary, health: BustleHealthBehaviour) -> BustleBrain:
	var config := BustleScoringConfig.new()
	config.pick_window = 0.0
	var brain := BustleBrain.new(id, library, config, 5)
	brain.gate = health.allows
	return brain


func test_fetching_a_healer() -> void:
	var snippet := _snippet("add_fetch_healer")
	var ports := BustlePorts.new()
	var port := Health.new()
	ports.health = port
	ports.roles.set_holder(&"healer", &"doctor")
	var health := BustleHealthBehaviour.new(null, ports)
	var at := {&"patient": Vector3.ZERO, &"bystander": Vector3(1, 0, 0), &"doctor": Vector3(50, 0, 0)}
	var library := BustleGoalLibrary.new()
	var brain := _brain(&"bystander", library, health)
	var fetch: BustleFetchHealer = snippet.call(&"add_fetch_healer", health, library, brain,
		func(id: StringName) -> Variant: return at.get(id))
	assert_eq(library.goals.back().id, &"fetch_healer")
	port.downed = [&"patient"]
	var intent: BustleIntent = snippet.call(&"tick_bystander", fetch, brain, &"patient", 0)
	assert_eq(fetch.errand_of(&"bystander")["healer"], &"doctor")
	assert_eq(intent.goal_id, &"fetch_healer")
	assert_true(intent.has_move_to, "the host is asked to move the bystander")
	assert_eq(intent.move_to, Vector3(50, 0, 0))
	at[&"bystander"] = Vector3(49, 0, 0)
	snippet.call(&"tick_bystander", fetch, brain, &"patient", 10)
	assert_eq(fetch.summoned_to(&"doctor"), &"patient", "arrived: the healer is summoned")


func test_seeking_care_and_resting_when_sick() -> void:
	var snippet := _snippet("add_care_goals")
	var ports := BustlePorts.new()
	var port := Health.new()
	ports.health = port
	var health := BustleHealthBehaviour.new(null, ports)
	var library := BustleGoalLibrary.new()
	var brain := _brain(&"baker", library, health)
	var rest: BustleRestSick = snippet.call(&"add_care_goals", health, library, brain)
	assert_eq(library.goals.map(func(g: BustleGoalDef) -> StringName: return g.id), [&"seek_care", &"rest_sick"])
	assert_not_null(rest.seek_care, "seeking care comes first")
	port.tags = {&"baker": [&"sick"]}
	var senses := BustleSenses.new()
	snippet.call(&"fill_care_inputs", rest, &"baker", senses)
	assert_eq(senses.inputs.get(BustleRestSick.INPUT, 0.0), 1.0, "ill, with no need for care: rests")
	assert_false(senses.inputs.has(BustleSeekCare.INPUT))
	port.care_needed = {&"baker": 0.7}
	ports.roles.set_holder(&"healer", &"doctor")
	senses = BustleSenses.new()
	snippet.call(&"fill_care_inputs", rest, &"baker", senses)
	assert_almost_eq(senses.inputs.get(BustleSeekCare.INPUT, 0.0), 0.7, 1e-6, "needs care: seeks it")
	assert_false(senses.inputs.has(BustleRestSick.INPUT), "and doesn't rest first")
