# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The storyteller: events fire only when eligible, a quest lock holds back lock-sensitive ones,
## tension steers raise against relief, cooldowns and tension survive a save, and the same inputs
## replay the same. Event ids are neutral test names.

const HOUR := 60
const DAY := 1440


class Veto extends BustleDirectorPort:
	var refused: Array[StringName] = []

	func allows(event_kind: StringName) -> bool:
		return not refused.has(event_kind)


var _fired: Array = []


static func event(id: StringName, tension: float = 0.0, cooldown: int = 0, requires: Array[Dictionary] = [],
		lock_sensitive: bool = false, weight: float = 1.0) -> BustleEventDef:
	var def := BustleEventDef.new()
	def.id = id
	def.tension = tension
	def.cooldown_minutes = cooldown
	def.requires = requires
	def.lock_sensitive = lock_sensitive
	def.weight = weight
	return def


func _director(defs: Array[BustleEventDef], rules: BustleDirectorRules = null, ports: BustlePorts = null) -> BustleDirector:
	_fired = []
	var director := BustleDirector.new(rules, ports)
	for def: BustleEventDef in defs:
		assert_true(director.add_event(def), String(def.id))
	director.event_fired.connect(func(id: StringName, now: int) -> void: _fired.append([id, now]))
	return director


func test_an_event_fires_only_when_its_preconditions_hold() -> void:
	var director := _director([event(&"storm", 0.0, 0, [{"input": &"fact.season_cold"}, {"input": &"fact.stock", "at_most": 3.0}])])
	assert_eq(director.update(0, {}), &"", "a missing input fails")
	assert_eq(director.update(10, {&"fact.season_cold": 0.0, &"fact.stock": 1.0}), &"", "an input at 0 fails")
	assert_eq(director.update(20, {&"fact.season_cold": 1.0, &"fact.stock": 5.0}), &"", "above at_most fails")
	assert_eq(director.update(30, {&"fact.season_cold": 1.0, &"fact.stock": 3.0}), &"storm")
	var counted := _director([event(&"crowd", 0.0, 0, [{"input": &"fact.population", "at_least": 10}])])
	assert_eq(counted.update(0, {&"fact.population": 9.0}), &"")
	assert_eq(counted.update(10, {&"fact.population": 10.0}), &"crowd", "a count the host supplies")


func test_a_cooldown_holds_until_it_has_passed() -> void:
	var director := _director([event(&"visit", 0.0, DAY)])
	assert_eq(director.update(0), &"visit")
	for minute: int in range(HOUR, DAY, HOUR):
		assert_eq(director.update(minute), &"", "cooling down at %d" % minute)
	assert_eq(director.update(DAY), &"visit", "exactly when it has passed")
	assert_eq(_fired, [[&"visit", 0], [&"visit", DAY]])
	assert_eq(director.last_fired(&"visit"), DAY)


func test_the_port_vetoes_by_kind() -> void:
	var ports := BustlePorts.new()
	var veto := Veto.new()
	ports.director = veto
	var named := event(&"visit_a")
	named.kind = &"visit"
	var director := _director([named, event(&"rain")], null, ports)
	veto.refused = [&"visit", &"rain"]
	assert_eq(director.update(0), &"", "both refused")
	veto.refused = [&"rain"]
	assert_eq(director.update(10), &"visit_a", "asked by its kind")
	assert_true(BustleDirectorPort.new().allows(&"anything"), "the default port still allows everything")


func test_a_lock_sensitive_event_waits_for_the_lock_to_drop() -> void:
	var director := _director([event(&"raid", 0.5, 0, [], true), event(&"market", 0.0, DAY)])
	assert_eq(director.update(0, {}, true), &"market", "only the other event, while locked")
	for minute: int in range(HOUR, 10 * HOUR, HOUR):
		assert_eq(director.update(minute, {}, true), &"", "never while locked")
	assert_eq(director.update(10 * HOUR, {}, false), &"raid", "it fires once the lock drops")


func test_high_tension_prefers_relief_and_low_tension_prefers_raising() -> void:
	var rules := BustleDirectorRules.new()
	rules.tension_inputs = {&"fact.danger": 1.0}
	var defs: Array[BustleEventDef] = [event(&"raise", 0.3, 0, [], false, 5.0), event(&"relief", -0.3, 0, [], false, 1.0),
		event(&"neutral", 0.0, 0, [], false, 3.0)]
	var calm := _director(defs, rules)
	assert_eq(calm.need(0, {&"fact.danger": 0.1}), BustleDirector.NEED_RAISE)
	assert_eq(calm.update(0, {&"fact.danger": 0.1}), &"raise")
	var tense := _director(defs, rules)
	assert_eq(tense.need(0, {&"fact.danger": 0.9}), BustleDirector.NEED_RELIEVE)
	assert_eq(tense.update(0, {&"fact.danger": 0.9}), &"relief", "relief beats a higher score")
	var middle := _director(defs, rules)
	assert_eq(middle.need(0, {&"fact.danger": 0.5}), BustleDirector.NEED_NONE)
	assert_eq(middle.update(0, {&"fact.danger": 0.5}), &"raise", "in between, the score decides")
	var only := _director([event(&"raise", 0.3)], rules)
	assert_eq(only.update(0, {&"fact.danger": 0.9}), &"raise", "the wrong way still fires when nothing else can")


func test_sustained_tension_from_fired_events_turns_to_relief() -> void:
	var rules := BustleDirectorRules.new()
	rules.memory_minutes = 2 * DAY
	var director := _director([event(&"raise", 0.3, 0, [], false, 5.0), event(&"relief", -0.4, 0, [], false, 1.0)], rules)
	var picks: Array[StringName] = []
	var before: Array[float] = []
	for hour: int in 8:
		before.append(director.tension(hour * HOUR, {}))
		picks.append(director.update(hour * HOUR))
	assert_eq(picks, [&"raise", &"raise", &"raise", &"relief", &"raise", &"relief", &"raise", &"raise"] as Array[StringName],
		"raised while low, relieved once it builds up, then held in the middle")
	assert_lt(before[0], 0.3)
	assert_gt(before[3], 0.7, "three raises built tension past the high line")
	assert_almost_eq(director.tension(10 * DAY, {}), 0.0, 1e-9, "old events fade from tension")


func test_the_best_score_wins_and_ties_go_by_id() -> void:
	var director := _director([event(&"b", 0.0, DAY), event(&"a", 0.0, DAY), event(&"c", 0.0, DAY, [], false, 2.0)])
	assert_eq(director.update(0), &"c")
	assert_eq(director.update(10), &"a", "a tie, by id")
	assert_eq(director.update(20), &"b")
	var scored := event(&"scored")
	scored.score_inputs = {&"fact.crowd": 2.0}
	var by_input := _director([scored, event(&"plain", 0.0, 0, [], false, 2.0)])
	assert_eq(by_input.update(0, {&"fact.crowd": 1.0}), &"scored", "1 + 2 beats 2")


func test_the_beat_gap_delays_but_does_not_drop_an_event() -> void:
	var rules := BustleDirectorRules.new()
	rules.beat_gap_minutes = 6 * HOUR
	var director := _director([event(&"a", 0.0, DAY), event(&"b", 0.0, DAY)], rules)
	assert_eq(director.update(0), &"a")
	assert_eq(director.update(HOUR), &"", "within the gap")
	assert_eq(director.update(6 * HOUR), &"b", "fires when the gap ends")


func test_the_same_inputs_replay_the_same_timeline() -> void:
	var timelines: Array = []
	for run: int in 2:
		var rules := BustleDirectorRules.new()
		rules.tension_inputs = {&"fact.danger": 0.5}
		var director := _director([event(&"raise", 0.2, 3 * HOUR), event(&"relief", -0.3, 5 * HOUR),
			event(&"guarded", 0.1, DAY, [{"input": &"fact.danger", "at_least": 0.5}], true)], rules)
		for hour: int in 72:
			director.update(hour * HOUR, {&"fact.danger": float(hour % 24) / 24.0}, hour % 10 < 3)
		timelines.append(_fired.duplicate())
	assert_eq(timelines[0], timelines[1])
	assert_gt(timelines[0].size(), 10)
	for path: String in ["director.gd", "director_rules.gd", "event_def.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/director/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range", "rand_from_seed"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])


func test_a_director_saved_mid_run_makes_the_same_choices_after_loading() -> void:
	var defs: Array[BustleEventDef] = [event(&"raise", 0.3, 2 * HOUR), event(&"relief", -0.4, 4 * HOUR), event(&"quiet", 0.0, DAY)]
	var first := _director(defs)
	for hour: int in 12:
		first.update(hour * HOUR)
	var saved := first.export_state()
	var second := _director(defs)
	assert_true(second.import_state(saved))
	assert_eq(second.export_state(), saved)
	assert_eq(second.tension(12 * HOUR, {}), first.tension(12 * HOUR, {}), "tension comes back")
	var a: Array[StringName] = []
	var b: Array[StringName] = []
	for hour: int in range(12, 60):
		a.append(first.update(hour * HOUR))
		b.append(second.update(hour * HOUR))
	assert_eq(a, b)


func test_a_bad_save_is_refused_and_changes_nothing() -> void:
	var director := _director([event(&"a", 0.1)])
	director.update(0)
	var good := director.export_state()
	var bad: Array[Dictionary] = []
	for i: int in 4:
		bad.append(good.duplicate(true))
	bad[0]["version"] = 9
	bad[1]["last"]["unknown"] = 0
	bad[2]["history"] = [["a", 50], ["a", 10]]
	bad[3]["history"] = [["a", "noon"]]
	var target := _director([event(&"a", 0.1)])
	target.update(100)
	var before := target.export_state()
	for saved: Dictionary in bad:
		assert_false(target.import_state(saved))
		assert_eq(target.export_state(), before)


func test_no_events_or_bad_data_fires_nothing() -> void:
	var empty := _director([])
	for hour: int in 48:
		assert_eq(empty.update(hour * HOUR, {&"fact.danger": 1.0}, hour % 2 == 0), &"")
	assert_eq(_fired, [])
	var rules := BustleDirectorRules.new()
	rules.low = 0.8
	assert_eq(rules.validate(), "low and high must satisfy 0 <= low < high <= 1")
	var broken := _director([event(&"a")], rules)
	assert_eq(broken.update(0), &"", "invalid rules fire nothing")
	var director := _director([event(&"a")])
	assert_false(director.add_event(event(&"a")), "an id is used once")
	assert_false(director.add_event(event(&"")))
	assert_false(director.add_event(event(&"b", NAN)))
	var odd := event(&"c", 0.0, 0, [{"input": &"fact.x", "above": 1.0}])
	assert_eq(odd.validate(), "event 'c': precondition 0 has an unknown key 'above'")
	assert_eq(director.update(10), &"a")
	assert_eq(director.update(5), &"", "the clock never runs back")
