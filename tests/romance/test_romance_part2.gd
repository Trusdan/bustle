# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Romance, part 2: jealousy from a partner's opinion or interaction, family links through the
## social port, and the host's ratings policy over every step up the ladder.

const DAY := 1440

var _store: BustleSocialStore
var _romance: BustleRomance
var _moods: Dictionary[StringName, BustleMood] = {}
var _felt: Array = []


func _mood_of(id: StringName) -> Object:
	if not _moods.has(id):
		_moods[id] = BustleMood.new()
	return _moods[id]


func before_each() -> void:
	_store = BustleSocialStore.new()
	_moods.clear()
	_felt = []
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
	_romance.jealous.connect(func(agent: StringName, partner: StringName, rival: StringName, cause: StringName) -> void:
		_felt.append([agent, partner, rival, cause]))


func _like(a: StringName, b: StringName, opinion: int) -> void:
	_store.add_opinion(a, b, float(opinion - _store.opinion(a, b)), {"why": "test"}, 3650.0)


func _court(a: StringName, b: StringName) -> void:
	_like(a, b, 85)
	_like(b, a, 85)
	_romance.update(a, b, 0)


func _all(now: int) -> void:
	_romance.update_all([&"baker", &"cook", &"smith"] as Array[StringName], now, _mood_of)


# Acceptance (1): jealousy from a real cause, for the right agent, once per cause, timed.
func test_a_partners_fondness_for_someone_else_makes_jealousy_once() -> void:
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 74)
	_all(DAY)
	assert_true(_felt.is_empty(), "below the line")
	_like(&"smith", &"cook", 80)
	for step: int in 5:
		_all(DAY + step)
	assert_eq(_felt, [[&"baker", &"smith", &"cook", &"opinion"]], "once, for the partner of the one who took to someone")
	var mood: BustleMood = _moods[&"baker"]
	assert_eq(mood.count(&"jealous"), 1)
	assert_eq(mood.reasons()[0]["reason"]["rival"], "cook")
	assert_false(_moods.has(&"smith") and _moods[&"smith"].count(&"jealous") > 0, "not the one who took to them")
	mood.advance_to(DAY + 13 * 60)
	assert_eq(mood.count(&"jealous"), 0, "timed")
	_like(&"smith", &"cook", 65)
	_all(2 * DAY)
	_like(&"smith", &"cook", 80)
	_all(3 * DAY)
	assert_eq(_felt.size(), 1, "65 isn't below the release line (60)")
	_like(&"smith", &"cook", 50)
	_all(4 * DAY)
	_like(&"smith", &"cook", 80)
	_all(5 * DAY)
	assert_eq(_felt.size(), 2, "after a dip below it, a new cause")


func test_no_jealousy_without_a_romantic_bond() -> void:
	_store.set_kind(&"baker", &"smith", &"friend")
	_store.set_kind(&"smith", &"baker", &"friend")
	_like(&"smith", &"cook", 95)
	_all(DAY)
	assert_true(_romance.notice(&"smith", &"gift", &"cook", _mood_of) == false)
	assert_true(_felt.is_empty())
	_court(&"baker", &"smith")
	_romance.end(&"baker", &"smith", DAY)
	_all(2 * DAY)
	assert_true(_felt.is_empty(), "not after a breakup either")


func test_a_romantic_interaction_makes_jealousy_per_interaction() -> void:
	_court(&"baker", &"smith")
	assert_false(_romance.notice(&"smith", &"chat", &"cook", _mood_of), "not one of the verbs")
	assert_false(_romance.notice(&"smith", &"gift", &"baker", _mood_of), "to the partner")
	assert_false(_romance.notice(&"cook", &"gift", &"smith", _mood_of), "the giver has no partner")
	assert_true(_romance.notice(&"smith", &"gift", &"cook", _mood_of))
	assert_true(_romance.notice(&"smith", &"gift", &"cook", _mood_of))
	assert_eq(_felt, [[&"baker", &"smith", &"cook", &"gift"], [&"baker", &"smith", &"cook", &"gift"]], "each one a cause")
	assert_eq(_moods[&"baker"].count(&"jealous"), 2)


func test_same_causes_give_the_same_jealousy() -> void:
	var runs: Array = []
	for run: int in 2:
		before_each()
		_court(&"baker", &"smith")
		for day: int in 20:
			_like(&"smith", &"cook", 50 + (day * 13) % 45)
			_all(day * DAY)
		runs.append(_felt.duplicate())
	assert_eq(runs[0], runs[1])
	assert_false(runs[0].is_empty())


func test_felt_jealousy_survives_save_and_load() -> void:
	_court(&"baker", &"smith")
	_like(&"smith", &"cook", 80)
	_all(DAY)
	var saved: Variant = JSON.parse_string(JSON.stringify({"romance": _romance.export_state(), "social": _store.export_state()}))
	assert_eq(saved["romance"]["jealousy"], ["baker>smith>cook"])
	before_each()
	_store.import_state(saved["social"])
	assert_true(_romance.import_state(saved["romance"]))
	_all(2 * DAY)
	assert_true(_felt.is_empty(), "already felt for this cause")
	assert_false(_romance.import_state({"jealousy": ["baker>smith"]}))
	assert_false(_romance.import_state({"jealousy": "baker>smith>cook"}))


# Acceptance (2): family links both ways through the port, saved, and never courted.
func test_family_links_are_written_both_ways_and_block_courting() -> void:
	assert_true(_romance.link_family(&"baker", &"smith", &"parent"))
	assert_eq(_store.kinds_between(&"baker", &"smith"), PackedStringArray(["parent"]))
	assert_eq(_store.kinds_between(&"smith", &"baker"), PackedStringArray(["child"]))
	assert_true(_romance.link_family(&"cook", &"miller", &"sibling"))
	assert_true(_romance.link_family(&"cook", &"weaver", &"in_law"))
	assert_eq(_store.kinds_between(&"miller", &"cook"), PackedStringArray(["sibling"]))
	assert_eq(_store.kinds_between(&"weaver", &"cook"), PackedStringArray(["in_law"]))
	assert_false(_romance.link_family(&"baker", &"smith", &"cousin"))
	assert_false(_romance.link_family(&"baker", &"baker", &"sibling"))
	for pair: Array in [[&"baker", &"smith"], [&"cook", &"miller"], [&"cook", &"weaver"]]:
		_like(pair[0], pair[1], 95)
		_like(pair[1], pair[0], 95)
		assert_eq(_romance.update(pair[0], pair[1], 0), &"", str(pair))
	var saved: Variant = JSON.parse_string(JSON.stringify(_store.export_state()))
	before_each()
	assert_true(_store.import_state(saved))
	assert_eq(_store.kinds_between(&"smith", &"baker"), PackedStringArray(["child"]), "saved by the port")
	assert_eq(_romance.update(&"baker", &"smith", 0), &"")
	assert_true(_romance.unlink_family(&"baker", &"smith", &"parent"))
	assert_true(_store.kinds_between(&"smith", &"baker").is_empty())


func test_family_needs_a_port_that_keeps_kinds() -> void:
	var none := BustleRomance.new(BustleSocialPort.new())
	assert_false(none.link_family(&"a", &"b", &"sibling"))
	assert_push_error_count(0)


# Acceptance (3): the ratings policy can veto every step; a veto changes nothing.
func test_the_ratings_policy_vetoes_every_step() -> void:
	var asked: Array = []
	var allow: Array[StringName] = []
	_romance.ratings_policy = func(a: StringName, b: StringName, status: StringName) -> bool:
		asked.append([a, b, status])
		return allow.has(status)
	var changes: Array = []
	_romance.status_changed.connect(func(_a: StringName, _b: StringName, _o: StringName, n: StringName, _r: StringName) -> void:
		changes.append(n))
	var confirmed: Array = []
	_romance.confirm_hook = func(_a: StringName, _b: StringName, s: StringName) -> bool:
		confirmed.append(s)
		return true
	_like(&"baker", &"smith", 90)
	_like(&"smith", &"baker", 90)
	assert_eq(_romance.update(&"baker", &"smith", 0), &"", "courting vetoed")
	assert_eq(asked, [[&"baker", &"smith", BustleRomance.COURTING]])
	assert_true(_store.kinds_between(&"baker", &"smith").is_empty())
	assert_true(_romance.export_state().is_empty(), "no state")
	allow.append(BustleRomance.COURTING)
	_romance.update(&"baker", &"smith", 0)
	assert_eq(_romance.update(&"baker", &"smith", 8 * DAY), BustleRomance.COURTING, "partner vetoed")
	allow.append(BustleRomance.PARTNER)
	assert_eq(_romance.update(&"baker", &"smith", 8 * DAY), BustleRomance.PARTNER)
	assert_false(_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 9 * DAY), "engaged vetoed")
	assert_true(confirmed.is_empty(), "the host's confirm isn't even asked")
	assert_eq(_romance.status_of(&"baker", &"smith"), BustleRomance.PARTNER)
	allow.append(BustleRomance.ENGAGED)
	assert_true(_romance.request(&"baker", &"smith", BustleRomance.ENGAGED, 9 * DAY))
	assert_false(_romance.request(&"baker", &"smith", BustleRomance.MARRIED, 10 * DAY), "married vetoed")
	assert_eq(changes, [BustleRomance.COURTING, BustleRomance.PARTNER, BustleRomance.ENGAGED], "no signal for a veto")


func test_ratings_policy_can_be_cleared() -> void:
	_romance.ratings_policy = func(_a: StringName, _b: StringName, _s: StringName) -> bool: return false
	_like(&"baker", &"smith", 90)
	_like(&"smith", &"baker", 90)
	_romance.update(&"baker", &"smith", 0)
	_romance.ratings_policy = Callable()
	assert_eq(_romance.update(&"baker", &"smith", DAY), BustleRomance.COURTING, "unset allows what the ladder allows")
