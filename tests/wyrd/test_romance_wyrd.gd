# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Romance with the Wyrd bridge installed: the courtship kinds are written to and cleared from
## Wyrd's social state through the bridge's social port, and opinions come from Wyrd. Anonymous
## agents only. CI deletes this folder, the bridge and the vendored Wyrd in its core-only job.

const _Wyrd := preload("res://addons/wyrd/runtime/wyrd.gd")
const DAY := 1440


## A world where every id exists and is alive.
class _World:
	extends WyrdWorldAdapter
	func exists(_id: StringName) -> bool:
		return true
	func is_alive(_id: StringName) -> bool:
		return true
	func kind(_id: StringName) -> StringName:
		return &"person"
	func tags(_id: StringName) -> PackedStringArray:
		return PackedStringArray()
	func display_name(id: StringName) -> String:
		return String(id)
	func members(_group: StringName) -> PackedStringArray:
		return PackedStringArray()


var _wyrd: Node
var _social: BustleSocialPort
var _romance: BustleRomance


func before_each() -> void:
	_wyrd = _Wyrd.new()
	add_child_autofree(_wyrd)
	_wyrd.register_adapter(WyrdWorldAdapter, _World.new())
	var config := WyrdConfig.new()
	config.axis_verbs = PackedStringArray(["helped", "slighted"])
	config.axis_names = PackedStringArray(["affinity", "affinity"])
	config.axis_deltas = PackedFloat64Array([20.0, -30.0])
	_wyrd.configure(config)
	_wyrd.start_new_game(7)
	var society := BustleSociety.new(7)
	society.register_archetype(&"plain", BustleGoalLibrary.new())
	for id: StringName in [&"a1", &"a2", &"a3"]:
		society.add_agent(id, &"plain")
	var bridge := BustleWyrdBridge.install(society, _wyrd)
	assert_not_null(bridge)
	_social = bridge.social
	var rules := BustleRomanceRules.new()
	rules.courting_opinion = 58
	rules.courting_release = 52
	rules.partner_opinion = 59
	rules.partner_release = 53
	_romance = BustleRomance.new(_social, rules)
	_romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 0.5


func _help(a: StringName, b: StringName) -> void:
	_social.record_deed(a, &"helped", b, &"", [] as Array[Dictionary])


# Acceptance (5), with the bridge: the ladder lives in Wyrd's social state.
func test_the_ladder_goes_through_wyrd() -> void:
	assert_true(_social.supports_kinds())
	_help(&"a1", &"a2")
	assert_eq(_romance.update(&"a1", &"a2", 0), &"", "one-sided")
	_help(&"a2", &"a1")
	assert_eq(_romance.update(&"a1", &"a2", 0), BustleRomance.COURTING)
	assert_true(_wyrd.social.has_kind(&"a1", &"a2", &"courting"))
	assert_true(_wyrd.social.has_kind(&"a2", &"a1", &"courting"))
	assert_eq(_social.kinds_between(&"a2", &"a1"), PackedStringArray(["courting"]))
	assert_eq(_romance.update(&"a1", &"a2", 7 * DAY), BustleRomance.PARTNER)
	assert_false(_wyrd.social.has_kind(&"a1", &"a2", &"courting"), "replaced in Wyrd")
	assert_true(_wyrd.social.has_kind(&"a1", &"a2", &"partner"))
	_romance.confirm_hook = func(_a: StringName, _b: StringName, _s: StringName) -> bool: return true
	assert_true(_romance.request(&"a1", &"a2", BustleRomance.ENGAGED, 8 * DAY))
	assert_true(_wyrd.social.has_kind(&"a2", &"a1", &"engaged"))


func test_a_breakup_clears_wyrds_kinds() -> void:
	_help(&"a1", &"a2")
	_help(&"a2", &"a1")
	_romance.update(&"a1", &"a2", 0)
	_social.record_deed(&"a2", &"slighted", &"a1", &"", [] as Array[Dictionary])
	assert_lt(_social.opinion(&"a1", &"a2"), 52)
	assert_eq(_romance.update(&"a1", &"a2", DAY), &"")
	assert_true(_wyrd.social.targets(&"a1", &"courting").is_empty())
	assert_true(_wyrd.social.targets(&"a2", &"courting").is_empty())
	assert_push_error_count(0)
