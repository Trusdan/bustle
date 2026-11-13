# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The courtship ladder through the social port: courting and partner from mutual opinion and
## compatibility, engaged and married only with the host's approval, breakups with thoughts for
## both, no affairs, and saving.

const DAY := 1440

var _store: BustleSocialStore
var _romance: BustleRomance
var _thought: BustleThoughtDef


## A port that only records the kind writes it gets.
class _Recorder:
	extends BustleSocialPort
	var writes: Array = []
	var _kinds: Dictionary = {}
	var opinions: Dictionary = {}
	func supports_kinds() -> bool:
		return true
	func opinion(a: StringName, b: StringName) -> int:
		return opinions.get("%s>%s" % [a, b], 50)
	func kinds_between(a: StringName, b: StringName) -> PackedStringArray:
		return PackedStringArray(_kinds.get("%s>%s" % [a, b], []))
	func set_kind(a: StringName, b: StringName, kind: StringName) -> void:
		writes.append(["set", a, b, kind])
		var row: Array = _kinds.get("%s>%s" % [a, b], [])
		if not row.has(String(kind)):
			row.append(String(kind))
		_kinds["%s>%s" % [a, b]] = row
	func clear_kind(a: StringName, b: StringName, kind: StringName) -> void:
		var row: Array = _kinds.get("%s>%s" % [a, b], [])
		if row.has(String(kind)):
			writes.append(["clear", a, b, kind])
			row.erase(String(kind))


func before_each() -> void:
	_store = BustleSocialStore.new()
	_thought = BustleThoughtDef.new()
	_thought.id = &"heartbroken"
	_thought.value = -8.0
	_thought.duration_hours = 48.0
	var rules := BustleRomanceRules.new()
	rules.breakup_thought = _thought
	_romance = BustleRomance.new(_store, rules)
	_romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.5


func _like(a: StringName, b: StringName, opinion: int) -> void:
	_store.add_opinion(a, b, float(opinion - _store.opinion(a, b)), {"why": "test"}, 3650.0)


func _mutual(a: StringName, b: StringName, opinion: int) -> void:
	_like(a, b, opinion)
	_like(b, a, opinion)


# Acceptance (1): courtship only with mutual opinion and compatibility.
func test_courting_needs_mutual_opinion_and_compatibility() -> void:
	_like(&"baker", &"smith", 85)
	_like(&"smith", &"baker", 65)
	assert_eq(_romance.update(&"baker", &"smith", 0), &"", "one-sided")
	_like(&"smith", &"baker", 85)
	_romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.1
	assert_eq(_romance.update(&"baker", &"smith", 0), &"", "not compatible enough")
	_romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.5
	assert_eq(_romance.update(&"baker", &"smith", 0), BustleRomance.COURTING)
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["courting"]))
	assert_eq(_store.kinds_between(&"smith", &"baker"), PackedStringArray(["courting"]), "both ways")


func test_partner_follows_courting_days_and_the_partner_line() -> void:
	_mutual(&"baker", &"smith", 75)
	_romance.update(&"baker", &"smith", 0)
	assert_eq(_romance.update(&"baker", &"smith", 8 * DAY), BustleRomance.COURTING, "75 is below the partner line")
	_mutual(&"baker", &"smith", 85)
	_romance.update(&"baker", &"smith", 0)
	assert_eq(_romance.update(&"baker", &"smith", 7 * DAY - 1), BustleRomance.COURTING, "not yet seven days")
	assert_eq(_romance.update(&"baker", &"smith", 7 * DAY), BustleRomance.PARTNER)
	assert_eq(_store.kinds_between(&"smith", &"baker"), PackedStringArray(["partner"]), "courting replaced")
	for day: int in range(8, 60):
		_romance.update(&"baker", &"smith", day * DAY)
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.PARTNER, "never further on its own")


# Acceptance (2): engaged and married only after host confirmation.
func test_engaged_and_married_need_the_host() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.update(&"baker", &"smith", 7 * DAY)
	assert_false(_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 8 * DAY), "no hook: refused")
	var asked: Array = []
	var approve: Array[bool] = [false]
	_romance.confirm_hook = func(a: StringName, b: StringName, status: StringName) -> bool:
		asked.append([a, b, status])
		return approve[0]
	assert_false(_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 8 * DAY), "declined")
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.PARTNER)
	assert_false(_romance.request(&"baker", &"smith", BustleRomance.MARRIED, 8 * DAY), "a step at a time")
	approve[0] = true
	assert_true(_romance.request(&"smith", &"baker", BustleRomance.ENGAGED, 9 * DAY))
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["engaged"]))
	assert_true(_romance.request(&"baker", &"smith", BustleRomance.MARRIED, 20 * DAY))
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.MARRIED)
	assert_eq(asked.size(), 3, "only steps that may happen ask the host")
	assert_false(_romance.request(&"baker", &"cook", BustleRomance.ENGAGED, 0), "no partnership")


# Acceptance (3): a breakup adds a thought to both.
func test_a_lapse_breaks_up_with_thoughts_for_both() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.update(&"baker", &"smith", 7 * DAY)
	var baker := BustleMood.new()
	var smith := BustleMood.new()
	_like(&"smith", &"baker", 65)
	assert_eq(_romance.update(&"baker", &"smith", 8 * DAY, baker, smith), BustleRomance.PARTNER, "above the release line")
	watch_signals(_romance)
	_like(&"smith", &"baker", 55)
	assert_eq(_romance.update(&"baker", &"smith", 9 * DAY, baker, smith), &"")
	assert_signal_emitted_with_parameters(_romance, "status_changed",
			[&"baker", &"smith", BustleRomance.PARTNER, &"", &"lapsed"])
	assert_eq(baker.count(&"heartbroken"), 1)
	assert_eq(smith.count(&"heartbroken"), 1)
	assert_eq(baker.reasons()[0]["reason"]["with"], "smith")
	assert_true(_store.kinds_between(&"baker", &"smith").is_empty())
	assert_true(_store.kinds_between(&"smith", &"baker").is_empty())
	assert_eq(_romance.update(&"baker", &"smith", 10 * DAY, baker, smith), &"", "no thought twice")
	assert_eq(baker.count(&"heartbroken"), 1)


func test_either_can_end_it() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	var baker := BustleMood.new()
	var smith := BustleMood.new()
	assert_true(_romance.end(&"smith", &"baker", DAY, smith, baker))
	assert_eq(_romance.update(&"baker", &"smith", DAY + 1), &"", "the end sticks with opinions unchanged")
	assert_eq(baker.count(&"heartbroken") + smith.count(&"heartbroken"), 2)
	assert_eq(_romance.history_of(&"baker", &"smith").back()["reason"], &"ended")
	assert_false(_romance.end(&"smith", &"baker", DAY))


# Acceptance (4): affairs never occur while the flag is off (and have no path when it is on).
func test_no_affairs() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.update(&"baker", &"smith", 7 * DAY)
	_mutual(&"baker", &"cook", 95)
	for affairs: bool in [false, true]:
		_romance.rules.affairs_enabled = affairs
		for day: int in range(8, 30):
			_romance.update(&"baker", &"cook", day * DAY)
			_romance.update(&"cook", &"smith", day * DAY)
		assert_eq(_romance.status_of(&"baker", &"cook"), &"", "affairs %s" % affairs)
		assert_true(_store.kinds_between(&"baker", &"cook").is_empty())
	_mutual(&"cook", &"miller", 90)
	_romance.update(&"cook", &"miller", 0)
	_mutual(&"cook", &"weaver", 90)
	assert_eq(_romance.update(&"cook", &"weaver", 0), &"", "one courtship at a time")


func test_family_is_never_courted() -> void:
	_mutual(&"baker", &"smith", 90)
	_store.set_kind(&"baker", &"smith", &"sibling")
	assert_eq(_romance.update(&"baker", &"smith", 0), &"")
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["sibling"]), "left as the host set it")


# Acceptance (5): every kind goes through the social port.
func test_kinds_are_written_only_through_the_port() -> void:
	var port := _Recorder.new()
	port.opinions = {"a>b": 90, "b>a": 90}
	var romance := BustleRomance.new(port)
	romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.5
	romance.update(&"a", &"b", 0)
	romance.update(&"a", &"b", 7 * DAY)
	romance.end(&"a", &"b", 8 * DAY)
	assert_eq(port.writes, [["set", &"a", &"b", &"courting"], ["set", &"b", &"a", &"courting"],
		["clear", &"a", &"b", &"courting"], ["clear", &"b", &"a", &"courting"],
		["set", &"a", &"b", &"partner"], ["set", &"b", &"a", &"partner"],
		["clear", &"a", &"b", &"partner"], ["clear", &"b", &"a", &"partner"]])
	var none := BustleRomance.new(BustleSocialPort.new())
	assert_eq(none.update(&"a", &"b", 0), &"", "a port with no kinds: no romance")
	assert_push_error_count(0)


# Acceptance (6): statuses and their history survive save and load.
func test_statuses_survive_save_and_load() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	var saved: Variant = JSON.parse_string(JSON.stringify({"romance": _romance.export_state(), "social": _store.export_state()}))
	var straight := _romance.update(&"baker", &"smith", 7 * DAY)
	before_each()
	assert_true(_store.import_state(saved["social"]))
	assert_true(_romance.import_state(saved["romance"]))
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.COURTING)
	assert_eq(_romance.since_of(&"baker", &"smith"), 0)
	assert_eq(_romance.update(&"baker", &"smith", 7 * DAY), straight, "carries on the same")
	assert_eq(_romance.history_of(&"baker", &"smith").map(func(e: Dictionary) -> StringName: return e["status"]),
			[BustleRomance.COURTING, BustleRomance.PARTNER])
	var before := _romance.export_state()
	for bad: Variant in [null, {"x": {"a": "baker"}}, {"baker|smith": {"a": "baker", "b": "smith", "status": 3,
			"since": 0, "history": []}}, {"baker|smith": {"a": "baker", "b": "smith", "status": "", "since": 0,
			"armed": "yes", "history": []}}, {"baker|smith": {"a": "baker", "b": "smith", "status": "betrothed",
			"since": 0, "history": []}}, {"smith|baker": {"a": "smith", "b": "baker", "status": "", "since": 0, "history": []}}]:
		assert_false(_romance.import_state(bad), str(bad))
		assert_eq(_romance.export_state(), before)


func test_same_opinions_give_the_same_ladder() -> void:
	var runs: Array = []
	for run: int in 2:
		before_each()
		for day: int in 40:
			_mutual(&"baker", &"smith", 60 + (day * 7) % 35)
			_romance.update(&"baker", &"smith", day * DAY)
		runs.append(_romance.export_state())
	assert_eq(runs[0], runs[1])
	assert_false(runs[0].is_empty())


# A breakup sticks until the pair's lower opinion has been below the courting release line.
func test_after_a_breakup_courting_needs_a_dip_and_a_climb() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.end(&"baker", &"smith", DAY)
	for day: int in range(2, 20):
		assert_eq(_romance.update(&"baker", &"smith", day * DAY), &"", "day %d" % day)
	_like(&"smith", &"baker", 56)
	_romance.update(&"baker", &"smith", 20 * DAY)
	_like(&"smith", &"baker", 90)
	assert_eq(_romance.update(&"baker", &"smith", 21 * DAY), &"", "56 isn't below the release line (55)")
	_like(&"smith", &"baker", 50)
	assert_eq(_romance.update(&"baker", &"smith", 22 * DAY), &"", "below it: armed, but not courting at 50")
	_like(&"smith", &"baker", 90)
	assert_eq(_romance.update(&"baker", &"smith", 23 * DAY), BustleRomance.COURTING, "climbed back")
	assert_eq(_romance.history_of(&"baker", &"smith").back(), {"status": BustleRomance.COURTING, "at": 23 * DAY,
		"reason": &"formed"})


func test_a_lapse_below_the_release_line_rearms_at_once() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_like(&"smith", &"baker", 50)
	_romance.update(&"baker", &"smith", DAY)
	_like(&"smith", &"baker", 90)
	assert_eq(_romance.update(&"baker", &"smith", 2 * DAY), BustleRomance.COURTING, "it has already dipped")


func test_a_breakup_sticks_across_a_save() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.end(&"baker", &"smith", DAY)
	var saved: Variant = JSON.parse_string(JSON.stringify({"romance": _romance.export_state(), "social": _store.export_state()}))
	assert_eq(saved["romance"]["baker|smith"]["armed"], false)
	before_each()
	_store.import_state(saved["social"])
	assert_true(_romance.import_state(saved["romance"]))
	assert_eq(_romance.update(&"baker", &"smith", 2 * DAY), &"", "still apart after the load")
	_like(&"baker", &"smith", 40)
	_romance.update(&"baker", &"smith", 3 * DAY)
	_like(&"baker", &"smith", 90)
	assert_eq(_romance.update(&"baker", &"smith", 4 * DAY), BustleRomance.COURTING)


# Only the host ends an engagement or a marriage.
func test_engaged_and_married_never_lapse_on_their_own() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.update(&"baker", &"smith", 7 * DAY)
	_romance.confirm_hook = func(_a: StringName, _b: StringName, _s: StringName) -> bool: return true
	_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 8 * DAY)
	_mutual(&"baker", &"smith", 10)
	var baker := BustleMood.new()
	var smith := BustleMood.new()
	assert_eq(_romance.update(&"baker", &"smith", 9 * DAY, baker, smith), BustleRomance.ENGAGED)
	_romance.request(&"baker", &"smith", BustleRomance.MARRIED, 10 * DAY)
	assert_eq(_romance.update(&"baker", &"smith", 11 * DAY, baker, smith), BustleRomance.MARRIED)
	assert_eq(baker.count(), 0)
	assert_true(_romance.end(&"baker", &"smith", 12 * DAY, baker, smith))
	assert_eq(baker.count(&"heartbroken") + smith.count(&"heartbroken"), 2)
	assert_true(_store.kinds_between(&"baker", &"smith").is_empty())


func test_invalid_rules_change_nothing() -> void:
	_mutual(&"baker", &"smith", 90)
	_romance.rules.courting_release = 80
	assert_false(_romance.rules.is_valid())
	assert_eq(_romance.update(&"baker", &"smith", 0), &"")
	assert_true(_store.kinds_between(&"baker", &"smith").is_empty())
