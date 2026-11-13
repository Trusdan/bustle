# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## The opinion entry jealousy adds toward the rival: one per cause, as configured, never toward the
## partner, saved like any opinion entry, off at 0, and never a status change by itself.

const DAY := 1440
const IDS: Array[StringName] = [&"baker", &"cook", &"smith"]

var _store: BustleSocialStore
var _romance: BustleRomance
var _moods: Dictionary[StringName, BustleMood] = {}


func _mood_of(id: StringName) -> Object:
	if not _moods.has(id):
		_moods[id] = BustleMood.new()
	return _moods[id]


func before_each() -> void:
	_store = BustleSocialStore.new()
	_moods.clear()
	var rules := BustleRomanceRules.new()
	var jealous := BustleThoughtDef.new()
	jealous.id = &"jealous"
	jealous.value = -5.0
	jealous.duration_hours = 12.0
	jealous.stack_limit = 5
	rules.jealousy_thought = jealous
	rules.jealousy_verbs = [&"gift"] as Array[StringName]
	_romance = BustleRomance.new(_store, rules)
	_romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.5


func _like(a: StringName, b: StringName, opinion: int) -> void:
	_store.add_opinion(a, b, float(opinion - _store.opinion(a, b)), {"why": "test"}, 3650.0)


func _court(a: StringName, b: StringName) -> void:
	_like(a, b, 85)
	_like(b, a, 85)
	_romance.update(a, b, 0)


func _jealous_entries(a: StringName, b: StringName) -> Array:
	return _store.reasons(a, b, 20).filter(func(entry: Dictionary) -> bool: return entry["reason"].has("jealous"))


# Acceptance (1): one entry per cause, as configured, toward the rival only.
func test_each_cause_adds_one_entry_toward_the_rival() -> void:
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 80)
	for step: int in 5:
		_romance.update_all(IDS, DAY + step, _mood_of)
	var entries := _jealous_entries(&"baker", &"cook")
	assert_eq(entries.size(), 1, "once for the opinion cause, however many updates")
	assert_eq(entries[0]["value"], -5.0)
	assert_eq(entries[0]["reason"], {"jealous": "opinion", "partner": "smith", "rival": "cook"})
	assert_eq(int(entries[0]["until"]) - int(entries[0]["at"]), 3 * DAY, "lasts jealousy_opinion_days")
	assert_eq(_store.opinion(&"baker", &"cook"), 45)
	assert_eq(_store.opinion(&"baker", &"smith"), 85, "never toward the partner")
	assert_eq(_moods[&"baker"].count(&"jealous"), 1, "alongside the thought")
	_romance.notice(&"smith", &"gift", &"cook", _mood_of)
	_romance.notice(&"smith", &"gift", &"cook", _mood_of)
	assert_eq(_jealous_entries(&"baker", &"cook").size(), 3, "one per interaction")
	assert_eq(_store.opinion(&"baker", &"cook"), 35)
	_romance.notice(&"smith", &"gift", &"baker", _mood_of)
	assert_eq(_store.opinion(&"baker", &"smith"), 85)


func test_a_rearmed_cause_adds_one_more() -> void:
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 80)
	_romance.update_all(IDS, DAY, _mood_of)
	_like(&"smith", &"cook", 65)
	_romance.update_all(IDS, 2 * DAY, _mood_of)
	_like(&"smith", &"cook", 80)
	_romance.update_all(IDS, 2 * DAY + 1, _mood_of)
	assert_eq(_jealous_entries(&"baker", &"cook").size(), 1, "65 isn't below the release line")
	_like(&"smith", &"cook", 50)
	_romance.update_all(IDS, 2 * DAY + 2, _mood_of)
	_like(&"smith", &"cook", 80)
	_romance.update_all(IDS, 2 * DAY + 3, _mood_of)
	assert_eq(_jealous_entries(&"baker", &"cook").size(), 2)


func test_no_entry_without_a_romantic_bond() -> void:
	_store.set_kind(&"baker", &"smith", &"friend")
	_store.set_kind(&"smith", &"baker", &"friend")
	_like(&"smith", &"cook", 95)
	_romance.update_all(IDS, DAY, _mood_of)
	_romance.notice(&"smith", &"gift", &"cook", _mood_of)
	assert_true(_jealous_entries(&"baker", &"cook").is_empty())
	assert_eq(_store.opinion(&"baker", &"cook"), 50)


# Acceptance (2): a value of 0 writes nothing, and the thought still works.
func test_a_zero_value_writes_no_entry() -> void:
	_romance.rules.jealousy_opinion_value = 0.0
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 80)
	_romance.update_all(IDS, DAY, _mood_of)
	_romance.notice(&"smith", &"gift", &"cook", _mood_of)
	assert_true(_store.reasons(&"baker", &"cook", 20).is_empty())
	assert_eq(_moods[&"baker"].count(&"jealous"), 2, "the thought still comes")


# Acceptance (3): saved like any opinion entry; the felt bookkeeping is unchanged.
func test_the_entry_survives_save_and_load() -> void:
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 80)
	_romance.update_all(IDS, DAY, _mood_of)
	var saved: Variant = JSON.parse_string(JSON.stringify({"romance": _romance.export_state(), "social": _store.export_state()}))
	assert_eq(saved["romance"]["jealousy"], ["baker>smith>cook"])
	before_each()
	assert_true(_store.import_state(saved["social"]))
	assert_true(_romance.import_state(saved["romance"]))
	assert_eq(_store.opinion(&"baker", &"cook"), 45)
	assert_eq(_jealous_entries(&"baker", &"cook")[0]["reason"]["rival"], "cook")
	_romance.update_all(IDS, 2 * DAY, _mood_of)
	assert_eq(_jealous_entries(&"baker", &"cook").size(), 1, "no second entry after the load")
	_store.set_time(DAY + 3 * DAY)
	assert_eq(_store.opinion(&"baker", &"cook"), 50, "and it expires on time")


# Acceptance (4): the entry never changes a status.
func test_the_entry_never_ends_a_relationship() -> void:
	_romance.rules.jealousy_opinion_value = -40.0
	_court(&"baker", &"smith")
	_romance.update(&"baker", &"smith", 7 * DAY)
	_romance.confirm_hook = func(_a: StringName, _b: StringName, _s: StringName) -> bool: return true
	_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 8 * DAY)
	for i: int in 4:
		_romance.notice(&"smith", &"gift", &"cook", _mood_of)
		_romance.update_all(IDS, 8 * DAY + i, _mood_of)
	assert_eq(_store.opinion(&"baker", &"cook"), 0, "the rival's standing fell")
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.ENGAGED, "the engagement holds")
	assert_eq(_store.opinion(&"baker", &"smith"), 85)
	_court(&"miller", &"weaver")
	_romance.update(&"miller", &"weaver", 7 * DAY)
	_romance.notice(&"weaver", &"gift", &"cook", _mood_of)
	assert_eq(_romance.update(&"miller", &"weaver", 9 * DAY), BustleRomance.PARTNER, "a partnership holds too")
