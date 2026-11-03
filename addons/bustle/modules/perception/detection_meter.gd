# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDetectionMeter
extends RefCounted

## One observer's awareness of one target: a meter from 0 to 1 that sight and hearing fill and
## that decays when neither reaches the target, and four states driven by it.
##
## Each tick the project calls [method tick] with the observer's position and facing and a
## [BustleSenseTarget]. One-off sounds arrive through [method hear_event]. The numbers come from the
## [BustlePerceptionProfile].
## [codeblock]
## UNAWARE ──level ≥ suspicious_at──▶ SUSPICIOUS ──level ≥ alert_at──▶ ALERT
##    ▲                                   │                              │
##    │                          level < suspicious_at       lost for lose_track_time
##    │                                   ▼                              │
##    └──────── search_time, nothing new ── SEARCHING ◀─────────────────┘
##                                          │ level ≥ alert_at ──▶ ALERT
## [/codeblock]
## @experimental

## The state changed from [param old] to [param new].
signal state_changed(old: State, new: State)
## It became suspicious of something at [param position].
signal noticed(position: Vector3)

## Awareness states.
enum State { UNAWARE, SUSPICIOUS, SEARCHING, ALERT }

## Below this distance the target counts as straight ahead.
const _NEAR := 0.001

## The numbers.
var profile: BustlePerceptionProfile
## The meter, 0..1.
var level: float = 0.0
## The current state.
var state: State = State.UNAWARE
## Where it last sensed the target (or heard an event). Only meaningful while
## [member has_last_known].
var last_known_position := Vector3.ZERO
## True once it has a last known position, until it is unaware again.
var has_last_known := false
## True when the last [method tick] sensed the target by sight.
var seen_now := false
## True when the last [method tick] sensed the target by hearing.
var heard_now := false
## Seconds since it last sensed the target (or heard an event); [constant INF] if never.
var since_sensed: float = INF

## ALERT: time without sensing the target.
var _lost_time: float = 0.0
## SEARCHING: time left before it gives up.
var _search_left: float = 0.0


func _init(p_profile: BustlePerceptionProfile = null) -> void:
	profile = p_profile if p_profile != null else BustlePerceptionProfile.new()


## Advances the meter by [param delta] seconds. [param observer_forward] is the way the observer
## faces (any length). Returns true when it sensed the target this tick.
func tick(delta: float, observer_position: Vector3, observer_forward: Vector3, target: BustleSenseTarget) -> bool:
	var sight := sight_rate(observer_position, observer_forward, target)
	var hearing := hearing_rate(observer_position, target)
	seen_now = sight > 0.0
	heard_now = hearing > 0.0
	var rate := sight + hearing
	var sensed := rate > 0.0
	since_sensed = 0.0 if sensed else since_sensed + delta
	if sensed:
		level = minf(1.0, level + rate * delta)
		last_known_position = target.position
		has_last_known = true
	else:
		level = maxf(0.0, level - profile.decay_rate * delta)
	_update_state(delta, sensed)
	return sensed


## A one-off sound. When it reaches the observer (and the observer hears), the meter jumps to at
## least [member BustlePerceptionProfile.suspicious_at], the event becomes the last known position, and an
## unaware or searching observer becomes suspicious. Returns true when it was heard.
func hear_event(event: BustleNoiseEvent, observer_position: Vector3) -> bool:
	if not profile.hears or not event.reaches(observer_position, profile.hearing_scale):
		return false
	level = maxf(level, profile.suspicious_at)
	last_known_position = event.position
	has_last_known = true
	since_sensed = 0.0
	if state == State.UNAWARE or state == State.SEARCHING:
		_enter(State.SUSPICIOUS)
	return true


## Sight's fill rate per second for [param target], or 0 when it can't see it: out of range,
## outside both cones, no line of sight, an observer that doesn't see, or a profile that needs a
## carried light on a target without one.
func sight_rate(observer_position: Vector3, observer_forward: Vector3, target: BustleSenseTarget) -> float:
	if not target.line_of_sight or not light_allows(target):
		return 0.0
	var cone := sight_cone(observer_position, observer_forward, target.position)
	if cone <= 0.0:
		return 0.0
	var falloff := 1.0 - observer_position.distance_to(target.position) / profile.sight_range
	return profile.fill_rate_sight * maxf(target.visibility, 0.0) * falloff * cone


## The geometric part of sight, without light or line of sight: 1 inside the inner cone, 0.5 in
## the peripheral band, 0 outside both, beyond [member BustlePerceptionProfile.sight_range] or for
## an observer that doesn't see. A host can call it first and cast its sight ray only when it is
## above 0.
func sight_cone(observer_position: Vector3, observer_forward: Vector3, point: Vector3) -> float:
	if not profile.sees or profile.sight_range <= 0.0:
		return 0.0
	var to_point := point - observer_position
	var distance := to_point.length()
	if distance >= profile.sight_range:
		return 0.0
	if distance <= _NEAR or observer_forward.length_squared() <= 0.0:
		return 1.0
	var angle := rad_to_deg(observer_forward.angle_to(to_point))
	if angle <= profile.sight_angle_deg * 0.5:
		return 1.0
	if angle <= profile.peripheral_angle_deg * 0.5:
		return 0.5
	return 0.0


## True when the profile's [member BustlePerceptionProfile.sight_light] lets it see
## [param target]: always for [constant BustlePerceptionProfile.SightLight.AMBIENT], only a target
## carrying a light for [constant BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY].
func light_allows(target: BustleSenseTarget) -> bool:
	return profile.sight_light != BustlePerceptionProfile.SightLight.CARRIED_LIGHT_ONLY or target.carries_light


## Hearing's fill rate per second for [param target], or 0 when its noise doesn't reach the
## observer (or the observer doesn't hear).
func hearing_rate(observer_position: Vector3, target: BustleSenseTarget) -> float:
	if not profile.hears:
		return 0.0
	var reach := target.noise_radius * profile.hearing_scale
	if reach <= 0.0:
		return 0.0
	var distance := observer_position.distance_to(target.position)
	if distance >= reach:
		return 0.0
	return profile.fill_rate_hearing * (1.0 - distance / reach)


## True only while unaware: the check a surprise attack uses.
func is_unaware() -> bool:
	return state == State.UNAWARE


## The meter as plain data, for a save.
func export_state() -> Dictionary:
	return {
		"level": level,
		"state": state_name(state),
		"last_known": [last_known_position.x, last_known_position.y, last_known_position.z],
		"has_last_known": has_last_known,
		"lost_time": _lost_time,
		"search_left": _search_left,
		"since_sensed": since_sensed if is_finite(since_sensed) else -1.0,
	}


## Restores [method export_state]'s data. Unknown or missing values fall back to unaware. Emits
## no signals.
func import_state(data: Dictionary) -> void:
	level = clampf(float(data.get("level", 0.0)), 0.0, 1.0)
	var index := State.keys().find(str(data.get("state", "unaware")).to_upper())
	state = State.UNAWARE if index < 0 else index as State
	var at: Variant = data.get("last_known", [])
	if at is Array and (at as Array).size() == 3:
		last_known_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	else:
		last_known_position = Vector3.ZERO
	has_last_known = data.get("has_last_known", false) == true
	_lost_time = maxf(0.0, float(data.get("lost_time", 0.0)))
	_search_left = maxf(0.0, float(data.get("search_left", 0.0)))
	var since := float(data.get("since_sensed", -1.0))
	since_sensed = since if since >= 0.0 else INF
	seen_now = false
	heard_now = false


## The state's name in lower case, for saves and logs.
static func state_name(value: State) -> String:
	return String(State.keys()[value]).to_lower()


func _update_state(delta: float, sensed: bool) -> void:
	match state:
		State.UNAWARE:
			if level >= profile.suspicious_at:
				_enter(State.SUSPICIOUS)
		State.SUSPICIOUS:
			if level >= profile.alert_at:
				_enter(State.ALERT)
			elif level < profile.suspicious_at:
				_enter(State.SEARCHING)
		State.ALERT:
			_lost_time = 0.0 if sensed else _lost_time + delta
			if _lost_time >= profile.lose_track_time:
				_enter(State.SEARCHING)
		State.SEARCHING:
			if level >= profile.alert_at:
				_enter(State.ALERT)
			elif sensed:
				_search_left = profile.search_time
			else:
				_search_left -= delta
				if _search_left <= 0.0:
					_enter(State.UNAWARE)


func _enter(next: State) -> void:
	if next == state:
		return
	var old := state
	state = next
	match next:
		State.SUSPICIOUS:
			noticed.emit(last_known_position)
		State.ALERT:
			_lost_time = 0.0
		State.SEARCHING:
			_search_left = profile.search_time
		State.UNAWARE:
			level = 0.0
			has_last_known = false
	state_changed.emit(old, next)
