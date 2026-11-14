# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## Sixty game days with a small neutral deck, checked every hour: the director only fires what was
## eligible and best, keeps every cooldown and the beat gap, never fires a lock-sensitive event under
## a quest lock, spends tension both ways, and replays the same timeline and effects.

const HOUR := 60
const DAY := 1440


class Mood extends RefCounted:
	var got: Array = []

	func add_thought(def: BustleThoughtDef, details: Dictionary) -> bool:
		got.append([def.id, details["event"]])
		return true


static func _event(id: StringName, tension: float, cooldown_hours: int, requires: Array[Dictionary], lock_sensitive: bool,
		weight: float, thought_value: float) -> BustleEventDef:
	var def := BustleEventDef.new()
	def.id = id
	def.tension = tension
	def.cooldown_minutes = cooldown_hours * HOUR
	def.requires = requires
	def.lock_sensitive = lock_sensitive
	def.weight = weight
	var thought := BustleThoughtDef.new()
	thought.id = StringName(String(id) + "_felt")
	thought.value = thought_value
	thought.duration_hours = 12.0
	var effect := BustleEventEffect.new()
	effect.thought = thought
	effect.target_ids = [&"a", &"b"]
	def.effects = [effect]
	return def


static func _deck() -> Array[BustleEventDef]:
	return [
		_event(&"quarrel", 0.25, 18, [], false, 2.0, -4.0),
		_event(&"raid", 0.45, 72, [{"input": BustleDirector.INPUT_WEALTH, "at_least": 40}], true, 3.0, -8.0),
		_event(&"feast", -0.35, 30, [{"input": BustleDirector.INPUT_POPULATION, "at_least": 12}], false, 1.0, 6.0),
		_event(&"calm_day", -0.2, 24, [], false, 0.5, 2.0),
		_event(&"rumour", 0.0, 12, [], false, 1.5, -1.0),
	]


# The host's world on each hour: a head count and wealth that drift, and quest locks on some days.
static func _inputs(hour: int) -> Dictionary:
	var day := hour / 24
	return BustleDirector.hooks(10 + day % 5, float((day * 37) % 100))


static func _locked(hour: int) -> bool:
	var day := hour / 24
	return (day >= 10 and day < 14) or (day % 9 == 0 and hour % 24 < 12)


func _soak() -> Dictionary:
	var rules := BustleDirectorRules.new()
	rules.beat_gap_minutes = 4 * HOUR
	var director := BustleDirector.new(rules)
	for def: BustleEventDef in _deck():
		director.add_event(def)
	var moods := {&"a": Mood.new(), &"b": Mood.new()}
	var effects := BustleDirectorEffects.new()
	effects.mood_of = func(id: StringName) -> Object: return moods.get(id)
	director.effects = effects
	var fired: Array = []
	var problems: Array[String] = []
	var last: Dictionary = {}
	var last_beat := -1
	var high_hours := 0
	for hour: int in 60 * 24:
		var now := hour * HOUR
		var inputs := _inputs(hour)
		var locked := _locked(hour)
		if director.tension(now, inputs) >= rules.high:
			high_hours += 1
		var best := director.eligible(now, inputs, locked)
		var id := director.update(now, inputs, locked)
		if id == &"":
			if not best.is_empty():
				problems.append("%d: nothing fired though %s was eligible" % [now, best[0].id])
			continue
		var def := director.find(id)
		if best.is_empty() or best[0].id != id:
			problems.append("%d: %s fired but was not the best eligible" % [now, id])
		if not def.preconditions_hold(inputs):
			problems.append("%d: %s fired with its preconditions false" % [now, id])
		if def.lock_sensitive and locked:
			problems.append("%d: %s fired under a quest lock" % [now, id])
		if last.has(id) and now - int(last[id]) < def.cooldown_minutes:
			problems.append("%d: %s broke its cooldown" % [now, id])
		if last_beat >= 0 and now - last_beat < rules.beat_gap_minutes:
			problems.append("%d: %s broke the beat gap" % [now, id])
		last[id] = now
		last_beat = now
		fired.append([id, now])
	return {"fired": fired, "problems": problems, "high_hours": high_hours,
		"thoughts": [moods[&"a"].got, moods[&"b"].got], "state": director.export_state()}


func test_sixty_days_keep_every_rule() -> void:
	var run := _soak()
	assert_eq(run["problems"], [] as Array[String])
	var fired: Array = run["fired"]
	var counts := {}
	for entry: Array in fired:
		counts[entry[0]] = int(counts.get(entry[0], 0)) + 1
	assert_eq(counts.keys().size(), 5, "every event in the deck fired: %s" % counts)
	assert_gt(int(counts[&"raid"]), 0, "the lock-sensitive event fires outside the locks")
	assert_lt(int(run["high_hours"]), 60 * 24 / 5, "tension is spent: under a fifth of the time at the high line")
	assert_eq((run["thoughts"][0] as Array).size(), fired.size(), "each fire applied its thought, and nothing else did")


func test_sixty_days_replay_the_same_timeline_and_effects() -> void:
	var first := _soak()
	var second := _soak()
	assert_eq(first["fired"], second["fired"])
	assert_eq(first["thoughts"], second["thoughts"])
	assert_eq(first["state"], second["state"])
	for path: String in ["director.gd", "director_effects.gd", "event_effect.gd", "event_def.gd"]:
		var text := FileAccess.get_file_as_string("res://addons/bustle/modules/director/" + path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "rand_range", "rand_from_seed"]:
			assert_false(text.contains(word), "%s has no %s" % [path, word])
