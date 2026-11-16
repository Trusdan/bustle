# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The out-of-order config pairs: validate() names each one, the code that reads the config warns
## once per class and pair, and every value is used as it is. In-order (and equal) pairs warn
## nothing. Then the live tick's OFF_SCREEN interval: 0 or less counts as 1 game minute.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")


## Everyone is far away.
class Far:
	extends BustleWorldPort

	func area_of(_id: StringName) -> StringName:
		return &"far"

	func player_area() -> StringName:
		return &"square"


var _thinks: Array[int] = []


func before_each() -> void:
	_Warn.reset()


# Each case: [class name, a fresh resource, {field: value} that puts one pair out of order, the
# problem validate() names, a Callable(resource) that runs the code reading it].
func _cases() -> Array:
	var target := BustleSenseTarget.new(Vector3(0, 0, -2), 1.0, 0.0, true, false)
	var perceive := func(profile: Resource) -> void:
		BustleDetectionMeter.new(profile).tick(0.1, Vector3.ZERO, Vector3.FORWARD, target)
	var mental := func(config: Resource) -> void:
		BustleMentalState.new(&"baker", config).choose(BustleMood.new())
	var stealth := func(rules: Resource) -> void:
		BustleVisibilityModel.new(rules).compute(1.0, BustleStealthRules.Posture.STANDING, BustleStealthRules.Movement.WALKING)
	var social := func(rules: Resource) -> void:
		var store := BustleSocialStore.new()
		store.rules = rules
		store.update_kinds(&"baker", &"smith")
	var wants := func(config: Resource) -> void:
		BustleAspirations.new(&"baker", config).update(0)
	return [
		["BustlePerceptionProfile", BustlePerceptionProfile.new(), {"suspicious_at": 0.95, "alert_at": 0.5},
			"suspicious_at is above alert_at", perceive],
		["BustleMentalConfig", BustleMentalConfig.new(), {"extreme_fraction": 0.8, "major_fraction": 0.4},
			"extreme_fraction is above major_fraction", mental],
		["BustleMentalConfig", BustleMentalConfig.new(), {"high_spirits_exit": 85.0},
			"high_spirits_exit is above high_spirits_above", mental],
		["BustleMentalConfig", BustleMentalConfig.new(), {"inspired_exit": 95.0},
			"inspired_exit is above inspired_above", mental],
		["BustleMentalConfig", BustleMentalConfig.new(), {"recover_margin": -5.0},
			"recover_margin is negative", mental],
		["BustleStealthRules", BustleStealthRules.new(), {"min_visibility": 2.0, "max_visibility": 0.5},
			"min_visibility is above max_visibility", stealth],
		["BustleRelationshipRules", BustleRelationshipRules.new(), {"friend_release": 80.0},
			"friend_release is above friend_at", social],
		["BustleRelationshipRules", BustleRelationshipRules.new(), {"rival_release": 20.0},
			"rival_release is below rival_at", social],
		["BustleAspirationConfig", BustleAspirationConfig.new(), {"auto_wants": 4, "want_cap": 2},
			"auto_wants is above want_cap", wants],
	]


func test_in_order_pairs_warn_nothing() -> void:
	for row: Array in _cases():
		var resource: Resource = row[1]
		assert_eq(resource.call(&"validate"), "", "%s's defaults are in order" % row[0])
		var read: Callable = row[4]
		read.call(resource)
		read.call(resource)
		assert_false(_Warn.has_warned("%s.%s" % [row[0], row[3]]), "%s: no warning" % row[3])
	assert_push_warning_count(0)


func test_equal_lines_are_in_order() -> void:
	var profile := BustlePerceptionProfile.new()
	profile.suspicious_at = 0.5
	profile.alert_at = 0.5
	var rules := BustleRelationshipRules.new()
	rules.friend_release = rules.friend_at
	rules.rival_release = rules.rival_at
	var config := BustleAspirationConfig.new()
	config.auto_wants = config.want_cap
	for resource: Resource in [profile, rules, config]:
		assert_eq(resource.call(&"validate"), "")


func test_each_out_of_order_pair_warns_once_and_keeps_its_values() -> void:
	for row: Array in _cases():
		_Warn.reset()
		var resource: Resource = row[1]
		var changes: Dictionary = row[2]
		for field: String in changes:
			resource.set(field, changes[field])
		assert_eq(resource.call(&"validate"), row[3], "%s names the pair" % row[0])
		var read: Callable = row[4]
		for i in 3:
			read.call(resource)
		assert_true(_Warn.has_warned("%s.%s" % [row[0], row[3]]), "%s: warned" % row[3])
		for field: String in changes:
			assert_eq(resource.get(field), changes[field], "%s.%s is used as it is" % [row[0], field])
	assert_push_warning_count(_cases().size(), "exactly one warning a pair, however often it's read")


func test_two_bad_pairs_in_one_resource_warn_once_each() -> void:
	var config := BustleMentalConfig.new()
	config.extreme_fraction = 0.9
	config.recover_margin = -1.0
	assert_eq(config.validate(), "extreme_fraction is above major_fraction; recover_margin is negative")
	var state := BustleMentalState.new(&"baker", config)
	for i in 3:
		state.choose(BustleMood.new())
	assert_push_warning_count(2)


func test_an_out_of_order_visibility_pair_is_used_as_it_is() -> void:
	var rules := BustleStealthRules.new()
	rules.min_visibility = 2.0
	rules.max_visibility = 0.5
	var model := BustleVisibilityModel.new(rules)
	var got := model.compute(1.0, BustleStealthRules.Posture.STANDING, BustleStealthRules.Movement.WALKING)
	assert_eq(got, clampf(1.0, 2.0, 0.5), "the same clamp as before the check")
	assert_push_warning_count(1)


# A society with one far-away agent, sorted OFF_SCREEN and last updated at minute 0, ringed with
# [param interval] game minutes between OFF_SCREEN thoughts.
func _rings(interval: int) -> Array:
	var society := BustleSociety.new(9)
	var library := BustleGoalLibrary.new()
	var goal := BustleGoalDef.new()
	goal.id = &"rest"
	library.goals.append(goal)
	society.register_archetype(&"villager", library)
	society.set_port(&"world", Far.new())
	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	config.offscreen_interval_game_minutes = interval
	var rings := BustleSimRings.new(society, config)
	rings.senses_provider = func(_id: StringName, _ring: int, minute: int) -> BustleSenses:
		_thinks.append(minute)
		return BustleSenses.new()
	var agent := society.add_agent(&"baker", &"villager")
	rings.tick(0.0)
	agent.last_update_minute = 0
	_thinks = []
	return [society, rings, agent]


func test_a_live_interval_of_zero_or_less_counts_as_one_minute() -> void:
	for interval: int in [0, -5]:
		var run := _rings(interval)
		(run[0] as BustleSociety).ports.clock.advance(5)
		for frame in 20:
			(run[1] as BustleSimRings).tick(0.0)
		assert_eq(_thinks, [1, 2, 3, 4, 5] as Array[int], "interval %d: one think a minute, one a tick" % interval)
		assert_eq((run[2] as BustleNpcState).last_update_minute, 5)
		assert_eq((run[1] as BustleSimRings).config.offscreen_interval_game_minutes, interval, "the value is kept")


func test_a_valid_live_interval_is_unchanged() -> void:
	for interval: int in [1, 60]:
		var run := _rings(interval)
		(run[0] as BustleSociety).ports.clock.advance(120)
		for frame in 200:
			(run[1] as BustleSimRings).tick(0.0)
		var expected: Array[int] = []
		for i in 120 / interval:
			expected.append((i + 1) * interval)
		assert_eq(_thinks, expected, "interval %d thinks every %d minutes" % [interval, interval])
