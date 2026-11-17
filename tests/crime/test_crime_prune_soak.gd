# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Pruning over long runs. The thirty-day village of test_crime_soak.gd, pruned after every theft
## of what closed more than three game days ago, decides exactly as it does unpruned (its fear
## hook counts sightings itself instead of reading the records, as a host that prunes must), and
## keeps nothing closed and old. A year of steady thefts, pruned daily, keeps the number of records
## bounded while the unpruned count grows with every theft.

const Soak := preload("res://tests/crime/test_crime_soak.gd")
const KEEP := 3 * 1440


## The village, with a fear of each thief that counts its own sightings, and an optional prune.
class Pruned:
	extends Soak.Village
	var prune := false
	var sizes: Array[int] = []
	var pruned := 0
	var stale: Array[String] = []
	var _seen: Dictionary[String, int] = {}

	func _init() -> void:
		super()
		# Methods, not lambdas: a lambda reading this village's members would hold it from its own
		# watch, and neither would be freed.
		watch.witnessed.connect(_on_seen)
		crime.theft.connect(_after_theft)

	func _on_seen(witness: StringName, thief: StringName, _item: StringName, _record: Dictionary) -> void:
		var key := "%s|%s" % [witness, thief]
		_seen[key] = _seen.get(key, 0) + 1

	# The same as reading the records: the times the witness has seen this thief steal, before now.
	func _fear_of(witness: StringName, thief: StringName) -> float:
		return 50.0 + 20.0 * (_seen.get("%s|%s" % [witness, thief], 0) - 1)

	func _after_theft(_thief: StringName, _owner: StringName, _item: StringName, circumstances: Dictionary) -> void:
		var cutoff := int(circumstances.get("at", 0)) - KEEP
		if prune:
			pruned += watch.prune(cutoff).size()
		var errand_records := {}
		for id: StringName in society.agent_ids():
			for errand: Dictionary in watch.errands_of(id):
				errand_records[int(errand["record"])] = true
		for row: Dictionary in watch.records():
			var open := bool(row["deed"]) and int(row["found_at"]) < 0 and not row.has("recovered_at")
			var last := maxi(maxi(int(row["at"]), int(row["found_at"])), int(row.get("recovered_at", -1)))
			if prune and not open and not errand_records.has(int(row["id"])) and last < cutoff:
				stale.append("record %d closed at %d, kept past %d" % [row["id"], last, cutoff])
		sizes.append(watch.records().size())


func test_pruning_keeps_the_records_bounded_and_changes_no_decision() -> void:
	var kept := Pruned.new()
	kept.run()
	var pruned := Pruned.new()
	pruned.prune = true
	pruned.run()
	assert_eq(kept.problems, [] as Array[String])
	assert_eq(pruned.problems, [] as Array[String])
	assert_eq(pruned.events, kept.events, "the village decides exactly as it does unpruned")
	assert_eq(pruned.stale, [] as Array[String], "nothing closed and old is kept")
	var thefts := kept.sizes.size()
	gut.p("village: %d thefts; unpruned ends with %d records; pruned peaks at %d, %d pruned, ends with %d" % [
		thefts, kept.sizes[-1], pruned.sizes.max(), pruned.pruned, pruned.sizes[-1]])
	assert_eq(kept.sizes[-1], thefts, "unpruned, every theft's record is kept")
	assert_lt(pruned.sizes[-1] * 2, kept.sizes[-1], "pruned, it ends well under the unpruned count")
	assert_eq(pruned.pruned + pruned.sizes[-1], thefts, "every record is either kept or handed back")
	var copy := BustleCrimeWatch.new(BustleCrime.new(pruned.society))
	assert_true(copy.import_state(pruned.watch.export_state()), "the pruned records save and load")
	assert_eq(copy.export_state(), pruned.watch.export_state())


func test_a_year_of_thefts_pruned_daily_stays_bounded() -> void:
	var pruned := _year(true)
	var kept := _year(false)
	var early: int = pruned.slice(0, 60).max()
	var late: int = pruned.slice(60).max()
	gut.p("a year: unpruned ends with %d records; pruned peaks at %d in the first 60 days and %d after" % [kept[-1], early, late])
	assert_eq(kept[-1], 365 * 3, "unpruned, the count grows with every theft")
	assert_lte(late, early, "pruned, it never grows past where it was in the first two months")
	assert_lte(late, 3 * 5 + 10, "bounded by about the last few days' thefts plus what's still open or on an errand")


# A year, three thefts a day by the drifter of the baker's goods: every third one seen by the cook,
# the rest deeds the baker finds on even days. Reports are errands, delivered at the end of each
# day, except days 3 and 4 of every ten, when nobody holds the role and they wait. With
# [param prune], the host prunes daily what closed more than three days ago. Returns the number
# of records at the end of each day.
func _year(prune: bool) -> Array[int]:
	var society := BustleSociety.new(7)
	society.register_archetype(&"villager", BustleGoalLibrary.new())
	var crime := BustleCrime.new(society)
	var needs: Dictionary[StringName, BustleNeedSet] = {}
	crime.needs_of = func(id: StringName) -> BustleNeedSet: return needs.get(id)
	crime.is_observed = func(_thief: StringName, _place: StringName) -> bool: return false
	var watch := BustleCrimeWatch.new(crime)
	var honest := BustlePersonality.new()
	honest.set_slider(&"honesty", 100.0)
	watch.judge.personality_of = func(id: StringName) -> BustlePersonality: return honest if id in [&"baker", &"cook"] else null
	for id: StringName in [&"drifter", &"baker", &"cook", &"warden"]:
		society.add_agent(id, &"villager").area = &"bakery"
		var food := BustleNeedDef.new()
		food.id = &"food"
		food.start = 1.0 if id == &"drifter" else 0.0
		needs[id] = BustleNeedSet.new()
		needs[id].add_need(food)
	society.get_agent(&"drifter").area = &"market"
	var sizes: Array[int] = []
	for day in 365:
		var away := day % 10 in [3, 4]
		society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"" if away else &"warden")
		for i in 3:
			var minute := day * 1440 + 100 + i * 500
			var item := StringName("loaf_%d_%d" % [day, i])
			society.ports.property.register(item, &"baker", &"market", {&"food": 0.5})
			society.get_agent(&"cook").area = &"market" if i == 0 else &"bakery"
			needs[&"drifter"].raise(&"food", 1.0)
			crime.consider(&"drifter", minute)
			assert_true(crime.steal(&"drifter", minute)["ok"], "day %d theft %d" % [day, i])
			society.ports.property.remove(item)
		var evening := day * 1440 + 1400
		if day % 2 == 0:
			watch.notice_losses(&"baker", &"market", evening)
		society.get_agent(&"cook").area = &"bakery"
		for agent: StringName in [&"cook", &"baker"]:
			while watch.deliver(agent, evening)["state"] == &"delivered":
				pass
		if prune:
			watch.prune(evening - KEEP)
		sizes.append(watch.records().size())
	return sizes
