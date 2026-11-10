# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Ten days of a dozen agents, every half hour: moods rise and fall with the day's thoughts, and
## states come and go. Every insult is at someone disliked (or a rival) in the same area and within
## a short walk, once per person an episode; nobody ever means to kill; locked agents start nothing
## and carry no state modifiers; a friend in a low state is always offered comfort by a friend
## beside it; and the same village runs the same way twice.

const DAYS := 10
const STEP := 30


class Village:
	extends RefCounted
	var society := BustleSociety.new(21)
	var store := BustleSocialStore.new()
	var behaviour: BustleMentalBehaviour
	var conflict: BustleConflict
	var comfort := BustleComfort.new()
	var people: Dictionary[StringName, BustlePersonality] = {}
	var moods: Dictionary[StringName, BustleMood] = {}
	var offsets: Dictionary[StringName, Vector3] = {}
	var events: Array = []
	var problems: Array[String] = []
	var comforted: int = 0
	var _gloom := BustleThoughtDef.new()
	var _glee := BustleThoughtDef.new()
	var _episode: Dictionary[StringName, int] = {}
	var _now: int = 0

	func _init() -> void:
		society.register_archetype(&"villager", BustleGoalLibrary.new())
		society.set_port(&"social", store)
		society.ports.world.set_place(&"market", Vector3.ZERO)
		society.ports.world.set_place(&"field", Vector3(500, 0, 0))
		behaviour = BustleMentalBehaviour.new(society)
		behaviour.position_of = _position
		behaviour.is_locked = _locked
		behaviour.indulgence_of = func(_id: StringName) -> StringName: return &"bench"
		behaviour.insulted.connect(_on_insulted)
		conflict = BustleConflict.new(BustleDispositionPort.new(), BustleCombatPort.new(), BustleConflictConfig.new())
		conflict.social = store
		conflict.personality_of = _personality
		comfort.low_state_of = behaviour.in_low_state
		_gloom.id = &"gloom"
		_gloom.value = -45.0
		_gloom.duration_hours = 14.0
		_glee.id = &"glee"
		_glee.value = 46.0
		_glee.duration_hours = 10.0
		var sliders := [{&"temper": 90.0, &"boldness": 70.0}, {&"sociability": 10.0}, {&"curiosity": 90.0},
			{&"greed": 90.0}, {&"diligence": 80.0}, {&"sociability": 80.0}]
		for i in 12:
			var id := StringName("villager_%02d" % i)
			society.add_agent(id, &"villager")
			people[id] = BustlePersonality.new()
			for slider: StringName in sliders[i % sliders.size()]:
				people[id].set_slider(slider, sliders[i % sliders.size()][slider])
			moods[id] = BustleMood.new(null, BustleModifierSet.new())
			moods[id].start(0)
			offsets[id] = Vector3(float(i % 4) * 12.0, 0, floorf(i / 4.0) * 12.0)
			behaviour.state_of(id).state_entered.connect(_on_entered)
			behaviour.state_of(id).state_exited.connect(_on_exited)
		for i in 12:
			var a := StringName("villager_%02d" % i)
			var b := StringName("villager_%02d" % ((i + 1) % 12))
			var c := StringName("villager_%02d" % ((i + 5) % 12))
			store.set_kind(a, b, &"friend")
			store.set_kind(b, a, &"friend")
			store.add_opinion(a, c, -30.0 - float(i), {}, 1000.0)
		store.set_kind(&"villager_00", &"villager_06", &"rival")

	func run() -> void:
		for minute in range(0, DAYS * 1440, STEP):
			_now = minute
			var day := floori(minute / 1440.0)
			var hour := floori((minute % 1440) / 60.0)
			for id: StringName in society.agent_ids():
				var i := int(String(id).right(2))
				society.get_agent(id).area = &"market" if (hour + i) % 6 < 4 else &"field"
				if hour == 6 and minute % 60 == 0 and (day + i) % 3 == 0:
					moods[id].add_thought(_gloom)
				if hour == 6 and minute % 60 == 0 and (day + i) % 3 == 1:
					moods[id].add_thought(_glee)
				moods[id].advance_to(minute)
				var locked := _locked(id)
				var was := behaviour.state_of(id).is_active()
				behaviour.update(id, minute, moods[id], people[id])
				if locked and not was and behaviour.state_of(id).is_active():
					problems.append("%s started a state while locked at %d" % [id, minute])
				if locked and moods[id].modifiers.has(&"tag.social.mult"):
					problems.append("%s kept its state modifiers while locked at %d" % [id, minute])
				_check_modifiers(id, locked)
				var inputs: Dictionary[StringName, float] = {}
				behaviour.fill_inputs(id, inputs)
				if inputs.has(&"fact.mental.lash_out"):
					behaviour.insult(id, behaviour.lash_target(id), minute)
			for id: StringName in society.agent_ids():
				if conflict.intent_of(id) == BustleConflict.KILL:
					problems.append("%s meant to kill at %d" % [id, minute])
				_check_comfort(id)

	# The state rows on an agent's modifier set always match its active state (none while locked).
	func _check_modifiers(id: StringName, locked: bool) -> void:
		var active := StringName(behaviour.state_of(id).active().get("id", ""))
		var want := &"" if locked else active
		var mods := moods[id].modifiers
		if behaviour.applied_state(id) != want:
			problems.append("%s has %s's modifiers in %s at %d" % [id, behaviour.applied_state(id), want, _now])
		for state: StringName in behaviour.config.state_modifiers:
			for key: StringName in behaviour.config.state_modifiers[state]:
				var row: Array = behaviour.config.state_modifiers.get(want, {}).get(key, [])
				if row.is_empty() and mods.has(key) or not row.is_empty() and not is_equal_approx(mods.value(key, 1.0), _expected(key, row)):
					problems.append("%s's %s doesn't match %s at %d" % [id, key, want, _now])

	func _expected(key: StringName, row: Array) -> float:
		var probe := BustleModifierSet.new()
		probe.set_source(&"probe", key, float(row[0]), float(row[1]))
		return probe.value(key, 1.0)

	func _check_comfort(id: StringName) -> void:
		if not behaviour.in_low_state(id):
			return
		for friend: StringName in society.agent_ids():
			if friend != id and society.get_agent(friend).area == society.get_agent(id).area and store.kinds_between(friend, id).has("friend"):
				var senses := BustleSenses.new()
				if comfort.advertise(friend, [id] as Array[StringName], store, _mood_of, senses) != 1:
					problems.append("%s wasn't offered comfort for %s at %d" % [friend, id, _now])
				comforted += 1

	func _on_entered(agent: StringName, id: StringName, info: Dictionary) -> void:
		_episode[agent] = int(info["since"])
		events.append(["entered", agent, id, info["tier"], info["since"]])

	func _on_exited(agent: StringName, id: StringName, reason: StringName) -> void:
		events.append(["exited", agent, id, reason, _now])

	func _on_insulted(agent: StringName, target: StringName, provocation: float) -> void:
		var a := society.get_agent(agent)
		var t := society.get_agent(target)
		if a.area != t.area or _position(agent).distance_to(_position(target)) > behaviour.config.lash_radius:
			problems.append("%s insulted %s out of reach at %d" % [agent, target, _now])
		if store.opinion(agent, target) >= 50 and not store.kinds_between(agent, target).has("rival"):
			problems.append("%s insulted %s, whom it doesn't dislike" % [agent, target])
		var key := ["insult", agent, target, _episode[agent]]
		if events.has(key):
			problems.append("%s insulted %s twice in one episode" % [agent, target])
		events.append(key)
		conflict.quarrel(target, agent, _now, provocation)

	func _position(id: StringName) -> Vector3:
		return society.ports.world.place_position(society.get_agent(id).area) + offsets[id]

	func _locked(id: StringName) -> bool:
		var hour := floori((_now % 1440) / 60.0)
		return int(String(id).right(2)) % 4 == 0 and hour >= 9 and hour < 12

	func _mood_of(id: StringName) -> BustleMood:
		return moods.get(id)

	func _personality(id: StringName) -> BustlePersonality:
		return people.get(id)


func test_ten_days_of_mental_states() -> void:
	var village := Village.new()
	village.run()
	var entered := village.events.filter(func(e: Array) -> bool: return e[0] == "entered")
	var exited := village.events.filter(func(e: Array) -> bool: return e[0] == "exited")
	var insults := village.events.filter(func(e: Array) -> bool: return e[0] == "insult")
	var kinds := {}
	for e: Array in entered:
		kinds[e[2]] = int(kinds.get(e[2], 0)) + 1
	var catharsis := 0
	for id: StringName in village.moods:
		catharsis += village.moods[id].count(&"catharsis")
	gut.p("%d states %s, %d ended, %d insults, %d comfort checks, %d catharsis still active" % [entered.size(), kinds, exited.size(), insults.size(), village.comforted, catharsis])
	assert_eq(village.problems, [] as Array[String])
	for state: String in ["withdraw", "wander", "binge", "lash_out", "high_spirits", "inspired"]:
		assert_true(kinds.has(StringName(state)), "%s happened" % state)
	assert_true(exited.any(func(e: Array) -> bool: return e[3] == &"ended") and exited.any(func(e: Array) -> bool: return e[3] == &"recovered"))
	assert_gt(catharsis, 0, "low states leave catharsis behind")
	assert_gt(insults.size(), 0, "some lashed out")
	assert_gt(village.comforted, 0, "friends were there to comfort")
	var again := Village.new()
	again.run()
	assert_eq(again.events, village.events, "the same village runs the same way twice")
	assert_eq(again.behaviour.export_state(), village.behaviour.export_state())
