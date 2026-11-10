# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## What a witness does about a theft: exactly one outcome, decided by who it is (personality,
## opinions, fear of the thief, the authority's standing, loyalty), never by chance. Whatever it
## decides, it remembers and can be questioned. A host can replace the decision.

const NEW_FILES: Array[String] = ["res://addons/bustle/core/crime/witness_judge.gd",
	"res://addons/bustle/core/crime/witness_config.gd"]


class Social:
	extends BustleSocialPort
	var kinds: Dictionary = {}

	func kinds_between(a: StringName, b: StringName) -> PackedStringArray:
		return kinds.get([a, b], PackedStringArray())


var _society: BustleSociety
var _crime: BustleCrime
var _watch: BustleCrimeWatch
var _social: Social
var _people: Dictionary[StringName, BustlePersonality] = {}
var _events: Array = []


func before_each() -> void:
	_society = BustleSociety.new(9)
	_society.register_archetype(&"villager", BustleGoalLibrary.new())
	_social = Social.new()
	_society.set_port(&"social", _social)
	_crime = BustleCrime.new(_society)
	var hunger := BustleNeedSet.new()
	var food := BustleNeedDef.new()
	food.id = &"food"
	food.start = 1.0
	hunger.add_need(food)
	_crime.needs_of = func(id: StringName) -> BustleNeedSet: return hunger if id == &"drifter" else null
	_crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	_watch = BustleCrimeWatch.new(_crime)
	_watch.instant = true
	_people = {}
	_watch.judge.personality_of = func(id: StringName) -> BustlePersonality: return _people.get(id)
	_events = []
	for name: String in ["decided", "crime_reported", "confronted", "victim_told", "gossiped"]:
		_watch.connect(name, _on_event.bind(name))
	_society.add_agent(&"drifter", &"villager").area = &"market"
	_society.add_agent(&"witness", &"villager").area = &"market"
	_society.ports.roles.set_holder(BustleCrimeWatch.AUTHORITY, &"warden")


func test_each_outcome_follows_from_who_the_witness_is() -> void:
	assert_eq(_outcome({&"honesty": 100.0}), &"report", "honest: 1.0")
	assert_eq(_events.map(func(e: Array) -> String: return e[-1]), ["decided", "crime_reported"])
	_watch.judge.standing_of = func(_w: StringName) -> float: return 0.0
	assert_eq(_outcome({&"honesty": 100.0}), &"tell_victim", "honest but distrusts the authority: report 0.5, tell the victim 1.0")
	assert_eq(_events.map(func(e: Array) -> String: return e[-1]), ["decided", "victim_told", "decided"], "the victim hears of it and decides in turn")
	assert_eq(_outcome({&"honesty": 100.0, &"temper": 100.0}), &"confront", "and hot-tempered, with the thief right there: 1.5")
	assert_eq(_events[-1].slice(0, 2), [&"witness", &"drifter"])
	_watch.can_reach = func(_a: StringName, _b: StringName) -> bool: return false
	assert_eq(_outcome({&"honesty": 100.0, &"temper": 100.0}), &"tell_victim", "a thief out of reach can't be confronted")
	_watch.gossip_to = func(_a: StringName, _r: Dictionary) -> StringName: return &"friend"
	assert_eq(_outcome({&"honesty": 100.0, &"sociability": 100.0}), &"gossip", "a sociable one with someone to tell: 1.5")
	assert_eq(_events[-2].slice(0, 2), [&"witness", &"friend"])
	_watch.judge.standing_of = Callable()
	assert_eq(_outcome({&"honesty": 100.0}), &"report", "report and telling the victim tie at 1.0: report comes first")
	assert_eq(_outcome({}), &"silent", "an ordinary witness: nothing reaches 1.0")
	assert_eq(_events.map(func(e: Array) -> String: return e[-1]), ["decided"], "silence emits only the decision")
	_watch.judge.fear_of = func(_w: StringName, _t: StringName) -> float: return 100.0
	assert_eq(_outcome({&"honesty": 100.0, &"boldness": 100.0}), &"silent", "fear of the thief: 1.0 + 0.5 − 1.0")
	_watch.judge.fear_of = Callable()
	_social.kinds[[&"witness", &"drifter"]] = PackedStringArray(["kin"])
	_watch.judge.config.kind_weights = {&"kin": -2.0}
	assert_eq(_outcome({&"honesty": 100.0}), &"silent", "loyalty to kin keeps an honest witness quiet")
	var scores: Dictionary = _watch.judge.decide(&"witness", {"thief": "drifter", "owner_id": "witness"})["scores"]
	assert_eq(scores.keys(), ["report"], "its own loss: no victim to tell, no thief in reach, nobody to gossip to")


func test_a_silent_witness_still_remembers_and_can_be_questioned() -> void:
	var memories: Dictionary[StringName, BustleMemory] = {&"witness": BustleMemory.new(), &"baker": BustleMemory.new()}
	_watch.memory_of = func(id: StringName) -> BustleMemory: return memories.get(id)
	assert_eq(_outcome({}), &"silent")
	var told := _watch.question(&"witness", 70)
	assert_eq(told, [{"id": 1, "item": "loaf", "owner_id": "baker", "place": "market", "at": 60, "thief": "drifter", "outcome": "silent"}] as Array[Dictionary],
		"questioned soon after, it names the thief")
	assert_eq(memories[&"witness"].recall(BustleMemory.ITEM, &"loaf", 70)["area"], &"market")
	assert_eq(_watch.question(&"witness", 60 + 7 * 1440)[0]["thief"], "", "a week on, it has forgotten who it was")
	assert_eq(_watch.question(&"stranger", 70), [] as Array[Dictionary], "nobody else knows anything")
	_society.get_agent(&"witness").area = &"well"
	_society.ports.property.register(&"bun", &"baker", &"market", {&"food": 0.3})
	_society.ports.property.remove(&"loaf")
	_crime.consider(&"drifter", 100)
	_crime.steal(&"drifter", 100)
	assert_true(_watch.record(2)["deed"])
	_watch.notice_losses(&"baker", &"market", 200)
	assert_eq(_watch.question(&"baker", 210)[0]["thief"], "", "the owner never saw who")
	assert_eq(_watch.record(2)["decisions"], {"baker": "silent"}, "an owner who finds a deed decides too")
	assert_eq(memories[&"baker"].recall(BustleMemory.ITEM, &"bun", 210)["area"], &"market", "and remembers where it went")


func test_a_host_can_replace_the_decision() -> void:
	var cases := []
	_watch.should_report = func(agent: StringName, case: Dictionary) -> StringName:
		cases.append([agent, case])
		return &"confront"
	assert_eq(_outcome({}), &"confront")
	assert_eq([cases[0][0], cases[0][1]["thief"], cases[0][1]["owner_id"], cases[0][1]["can_confront"], cases[0][1]["gossip_to"]],
		[&"witness", "drifter", "baker", true, ""])
	_watch.should_report = func(_a: StringName, _c: Dictionary) -> StringName: return &"shrug"
	assert_eq(_outcome({}), &"silent", "anything but an outcome is silence")


func test_deciding_leaves_nothing_to_chance_and_harms_nobody() -> void:
	for path: String in NEW_FILES:
		var text := FileAccess.get_file_as_string(path)
		for word: String in ["RandomNumberGenerator", "randf", "randi", "combat", "conflict", "health"]:
			assert_false(text.contains(word), "%s mentions %s" % [path, word])
	_watch.judge.standing_of = func(_w: StringName) -> float: return 0.0
	assert_eq(_outcome({&"honesty": 100.0, &"temper": 100.0}), &"confront")
	var goods := _society.ports.property.export_state()
	var case := {"thief": "drifter", "owner_id": "baker", "can_confront": true}
	assert_eq(_watch.judge.decide(&"witness", case), _watch.judge.decide(&"witness", case), "the same every time")
	assert_eq(_society.ports.property.export_state(), goods, "deciding moves no goods")


# Steals a fresh loaf with the witness given [param sliders]; returns what it decided.
func _outcome(sliders: Dictionary) -> StringName:
	var p := BustlePersonality.new()
	for slider: StringName in sliders:
		p.set_slider(slider, sliders[slider])
	_people[&"witness"] = p
	for row: Dictionary in _society.ports.property.items_of(&"drifter"):
		_society.ports.property.remove(StringName(row["id"]))
	var id := StringName("loaf_%d" % _watch.records().size()) if not _watch.records().is_empty() else &"loaf"
	_society.ports.property.register(id, &"baker", &"market", {&"food": 0.5})
	_events = []
	_crime.consider(&"drifter", 60)
	assert_true(_crime.steal(&"drifter", 60)["ok"])
	return StringName(_watch.record(_watch.records().size())["decisions"].get("witness", ""))


func _on_event(a: Variant, b: Variant, c: Variant, name: String = "") -> void:
	_events.append([a, b, c, name])
