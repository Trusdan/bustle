# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The detection meter: sight and hearing fill, decay, states, events and saved state.

const S := BustleDetectionMeter.State
const FORWARD := Vector3(0, 0, -1)

var _profile: BustlePerceptionProfile
var _meter: BustleDetectionMeter


func before_each() -> void:
	_profile = BustlePerceptionProfile.new()
	_meter = BustleDetectionMeter.new(_profile)


## A silent target [param distance] metres away at [param angle_deg] from straight ahead.
func _target(distance: float, angle_deg: float = 0.0, visibility: float = 1.0, noise: float = 0.0, sight: bool = true) -> BustleSenseTarget:
	var dir := FORWARD.rotated(Vector3.UP, deg_to_rad(angle_deg))
	return BustleSenseTarget.new(dir * distance, visibility, noise, sight)


## Ticks until the meter reaches [param state] or [param max_seconds] pass. Returns the time taken
## (or INF).
func _time_to(state: S, target: BustleSenseTarget, max_seconds: float = 30.0) -> float:
	var step := 0.05
	var time := 0.0
	while time < max_seconds:
		if _meter.state == state:
			return time
		_meter.tick(step, Vector3.ZERO, FORWARD, target)
		time += step
	return INF if _meter.state != state else time


func test_a_visible_target_in_the_cone_makes_it_suspicious_then_alert() -> void:
	watch_signals(_meter)
	var target := _target(3.0)
	assert_lt(_time_to(S.SUSPICIOUS, target), INF)
	assert_signal_emitted_with_parameters(_meter, "noticed", [target.position])
	assert_lt(_time_to(S.ALERT, target), INF)
	assert_signal_emitted_with_parameters(_meter, "state_changed", [S.SUSPICIOUS, S.ALERT])
	assert_eq(_meter.last_known_position, target.position)
	assert_true(_meter.has_last_known)


func test_sight_does_not_fill_behind_beyond_range_or_without_line_of_sight() -> void:
	for target: BustleSenseTarget in [_target(3.0, 180.0), _target(_profile.sight_range + 1.0), _target(3.0, 0.0, 1.0, 0.0, false)]:
		_meter.tick(1.0, Vector3.ZERO, FORWARD, target)
		assert_eq(_meter.level, 0.0)
		assert_eq(_meter.sight_rate(Vector3.ZERO, FORWARD, target), 0.0)
	assert_true(_meter.is_unaware())


func test_a_darker_target_takes_longer() -> void:
	var lit := _time_to(S.SUSPICIOUS, _target(5.0, 0.0, 1.0))
	_meter = BustleDetectionMeter.new(_profile)
	var dark := _time_to(S.SUSPICIOUS, _target(5.0, 0.0, 0.3))
	assert_gt(dark, lit * 2.0)


func test_sight_falls_off_with_range_and_halves_in_the_peripheral_band() -> void:
	var near := _meter.sight_rate(Vector3.ZERO, FORWARD, _target(3.0))
	var far := _meter.sight_rate(Vector3.ZERO, FORWARD, _target(12.0))
	assert_almost_eq(near, 0.8, 0.001, "1 - 3/15")
	assert_almost_eq(far, 0.2, 0.001)
	var side := _meter.sight_rate(Vector3.ZERO, FORWARD, _target(3.0, 60.0))
	assert_almost_eq(side, near * 0.5, 0.001, "60° is past the inner 45° but inside the outer 75°")
	assert_eq(_meter.sight_rate(Vector3.ZERO, FORWARD, _target(3.0, 80.0)), 0.0, "past the outer cone")


func test_hearing_fills_inside_the_scaled_noise_radius_only() -> void:
	var loud := _target(4.0, 180.0, 1.0, 8.0, false)
	assert_almost_eq(_meter.hearing_rate(Vector3.ZERO, loud), 0.8 * 0.5, 0.001)
	assert_true(_meter.tick(0.5, Vector3.ZERO, FORWARD, loud))
	assert_gt(_meter.level, 0.0)
	var quiet := _target(4.0, 180.0, 1.0, 3.0, false)
	assert_eq(_meter.hearing_rate(Vector3.ZERO, quiet), 0.0)
	_profile.hearing_scale = 2.0
	assert_gt(_meter.hearing_rate(Vector3.ZERO, quiet), 0.0, "a sharper ear hears it")


func test_an_observer_that_does_not_see_ignores_a_silent_visible_target() -> void:
	_profile.sees = false
	assert_eq(_time_to(S.SUSPICIOUS, _target(2.0), 5.0), INF)
	assert_eq(_meter.level, 0.0)


func test_an_observer_that_does_not_hear_ignores_noise_and_events() -> void:
	_profile.hears = false
	assert_eq(_meter.hearing_rate(Vector3.ZERO, _target(1.0, 180.0, 1.0, 10.0, false)), 0.0)
	assert_false(_meter.hear_event(BustleNoiseEvent.new(Vector3(1, 0, 0), 10.0), Vector3.ZERO))
	assert_true(_meter.is_unaware())


func test_the_meter_decays_when_nothing_is_sensed() -> void:
	_meter.tick(0.2, Vector3.ZERO, FORWARD, _target(3.0))
	var filled := _meter.level
	_meter.tick(1.0, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	assert_almost_eq(_meter.level, maxf(0.0, filled - _profile.decay_rate), 0.001)


func test_a_heard_event_makes_an_unaware_observer_suspicious_of_the_event() -> void:
	watch_signals(_meter)
	var event := BustleNoiseModel.event_noise(10.0, Vector3(6, 0, 0), &"thrown")
	assert_false(_meter.hear_event(BustleNoiseModel.event_noise(3.0, Vector3(6, 0, 0)), Vector3.ZERO), "too far")
	assert_true(_meter.hear_event(event, Vector3.ZERO))
	assert_eq(_meter.state, S.SUSPICIOUS)
	assert_eq(_meter.level, _profile.suspicious_at)
	assert_eq(_meter.last_known_position, Vector3(6, 0, 0))
	assert_signal_emitted_with_parameters(_meter, "noticed", [Vector3(6, 0, 0)])


func test_suspicion_that_fades_becomes_a_search_then_unaware() -> void:
	_meter.hear_event(BustleNoiseEvent.new(Vector3(6, 0, 0), 10.0), Vector3.ZERO)
	_meter.tick(0.1, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	assert_eq(_meter.state, S.SEARCHING, "the meter fell below suspicious_at")
	_meter.tick(_profile.search_time - 0.5, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	assert_eq(_meter.state, S.SEARCHING)
	_meter.tick(0.6, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	assert_eq(_meter.state, S.UNAWARE)
	assert_eq(_meter.level, 0.0)
	assert_false(_meter.has_last_known)


func test_alert_drops_to_searching_after_losing_track_then_unaware() -> void:
	_time_to(S.ALERT, _target(2.0))
	assert_eq(_meter.state, S.ALERT)
	var gone := _target(2.0, 180.0)
	_meter.tick(_profile.lose_track_time - 0.5, Vector3.ZERO, FORWARD, gone)
	assert_eq(_meter.state, S.ALERT, "still on the hunt")
	_meter.tick(0.6, Vector3.ZERO, FORWARD, gone)
	assert_eq(_meter.state, S.SEARCHING)
	assert_false(_meter.is_unaware())
	_meter.tick(_profile.search_time + 0.1, Vector3.ZERO, FORWARD, gone)
	assert_eq(_meter.state, S.UNAWARE)
	assert_true(_meter.is_unaware())


func test_a_searching_observer_that_finds_the_target_again_is_alert() -> void:
	_time_to(S.ALERT, _target(2.0))
	_meter.tick(_profile.lose_track_time + 0.1, Vector3.ZERO, FORWARD, _target(2.0, 180.0))
	assert_eq(_meter.state, S.SEARCHING)
	assert_lt(_time_to(S.ALERT, _target(2.0)), INF)


func test_is_unaware_only_in_unaware() -> void:
	assert_true(_meter.is_unaware())
	_meter.hear_event(BustleNoiseEvent.new(Vector3.ZERO, 5.0), Vector3.ZERO)
	assert_false(_meter.is_unaware())


func test_state_round_trips_through_export_and_import() -> void:
	_time_to(S.ALERT, _target(2.0))
	_meter.tick(_profile.lose_track_time + 1.0, Vector3.ZERO, FORWARD, _target(2.0, 180.0))
	var data := _meter.export_state()
	assert_eq(data["state"], "searching")
	var copy := BustleDetectionMeter.new(_profile)
	copy.import_state(JSON.parse_string(JSON.stringify(data)))
	assert_eq(copy.state, S.SEARCHING)
	assert_almost_eq(copy.level, _meter.level, 0.0001)
	assert_eq(copy.last_known_position, _meter.last_known_position)
	assert_true(copy.has_last_known)
	_meter.tick(_profile.search_time - 0.5, Vector3.ZERO, FORWARD, _target(2.0, 180.0))
	copy.tick(_profile.search_time - 0.5, Vector3.ZERO, FORWARD, _target(2.0, 180.0))
	assert_eq(copy.state, _meter.state, "the search timer came along")
	copy.import_state({"state": "nonsense", "level": 7})
	assert_eq(copy.state, S.UNAWARE)
	assert_eq(copy.level, 1.0)


func test_seen_and_heard_are_reported_separately_with_freshness() -> void:
	assert_eq(_meter.since_sensed, INF, "never sensed")
	_meter.tick(0.1, Vector3.ZERO, FORWARD, _target(3.0))
	assert_true(_meter.seen_now)
	assert_false(_meter.heard_now, "silent")
	assert_eq(_meter.since_sensed, 0.0)
	_meter.tick(0.1, Vector3.ZERO, FORWARD, _target(3.0, 180.0, 1.0, 8.0, false))
	assert_false(_meter.seen_now, "behind and out of sight")
	assert_true(_meter.heard_now)
	_meter.tick(0.5, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	assert_false(_meter.seen_now or _meter.heard_now)
	assert_almost_eq(_meter.since_sensed, 0.5, 0.0001, "seconds since last sensed")


func test_a_carried_light_profile_sees_only_lit_targets_but_still_hears() -> void:
	_profile.sight_light = BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY
	var dark := _target(3.0)
	assert_eq(_meter.sight_rate(Vector3.ZERO, FORWARD, dark), 0.0, "no carried light")
	var lit := _target(3.0)
	lit.carries_light = true
	assert_gt(_meter.sight_rate(Vector3.ZERO, FORWARD, lit), 0.0)
	var loud := _target(3.0, 0.0, 1.0, 8.0)
	assert_gt(_meter.hearing_rate(Vector3.ZERO, loud), 0.0, "hearing is unaffected")
	_meter.tick(0.5, Vector3.ZERO, FORWARD, loud)
	assert_false(_meter.seen_now)
	assert_true(_meter.heard_now)


func test_sight_cone_is_the_geometry_alone() -> void:
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, FORWARD * 3.0), 1.0)
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, FORWARD.rotated(Vector3.UP, deg_to_rad(60.0)) * 3.0), 0.5)
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, -FORWARD * 3.0), 0.0)
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, FORWARD * 30.0), 0.0, "beyond range")
	var blocked := _target(3.0, 0.0, 1.0, 0.0, false)
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, blocked.position), 1.0, "line of sight is not its business")
	_profile.sees = false
	assert_eq(_meter.sight_cone(Vector3.ZERO, FORWARD, FORWARD * 3.0), 0.0)


func test_freshness_round_trips_through_export_and_import() -> void:
	_meter.tick(0.1, Vector3.ZERO, FORWARD, _target(3.0))
	_meter.tick(2.0, Vector3.ZERO, FORWARD, _target(3.0, 180.0))
	var copy := BustleDetectionMeter.new(_profile)
	copy.import_state(JSON.parse_string(JSON.stringify(_meter.export_state())))
	assert_almost_eq(copy.since_sensed, 2.0, 0.0001)
	copy.import_state(BustleDetectionMeter.new(_profile).export_state())
	assert_eq(copy.since_sensed, INF, "never sensed stays never")
