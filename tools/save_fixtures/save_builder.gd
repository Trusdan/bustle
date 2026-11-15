# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## The neutral setup behind the golden save fixtures (docs/saves.md). The generator runs it on a
## tagged release to build each saved class with state; the fixture test runs it on the current code
## to build the empty target a fixture loads into. It names Bustle classes only through
## [method make], so it loads on a release where some of them don't exist yet. Fixed ids, seeds
## and minutes; no random numbers and no clock.

## Every saved class with a fixture, in a fixed order. The brain is saved inside the society.
const FORMATS: Array[StringName] = [&"BustleAffordance", &"BustleAffordanceSet", &"BustleAmbitions",
	&"BustleAspirations", &"BustleAwareness", &"BustleCareers", &"BustleConflict", &"BustleCrimeWatch",
	&"BustleDetectionMeter", &"BustleDirector", &"BustleEnvironmentPort", &"BustleJobBoard", &"BustleLeisure",
	&"BustleLifeStages", &"BustleMemory", &"BustleMentalBehaviour", &"BustleMentalState", &"BustleMood",
	&"BustleNeedSet", &"BustlePersonality", &"BustlePropertyPort", &"BustleRomance", &"BustleRoomThoughts",
	&"BustleSchedule", &"BustleScheduleRoster", &"BustleSequenceRunner", &"BustleSkills",
	&"BustleSocialInteractions", &"BustleSocialStore", &"BustleSociety", &"BustleTradePort"]
const BAKER := &"baker"
const SMITH := &"smith"
const MILLER := &"miller"
const SEED := 4242

var _classes: Dictionary = {}


func _init() -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_classes[StringName(entry["class"])] = String(entry["path"])


## True when this release has [param name] and it saves.
func has(name: StringName) -> bool:
	return _classes.has(name) and (load(_classes[name]) as Script).get_script_method_list().any(
		func(m: Dictionary) -> bool: return m["name"] == "export_state")


## A new [param name] made with [param args].
func make(name: StringName, args: Array = []) -> Object:
	return (load(_classes[name]) as Script).callv("new", args)


## [param items] as an Array typed with [param name], for typed parameters.
func typed(name: StringName, items: Array) -> Array:
	return Array(items, TYPE_OBJECT, &"RefCounted", load(_classes[name]))


## An empty [param name], set up to load a save, and how to load one into it:
## [code][target, func(target, saved) -> Variant][/code].
func target(name: StringName) -> Array:
	var plain := func(t: Object, s: Variant) -> Variant: return t.import_state(s)
	match name:
		&"BustleAwareness":
			return [make(name), func(t: Object, s: Variant) -> Variant: return t.import_state(s, profile())]
		&"BustleMood":
			return [_mood(), func(t: Object, s: Variant) -> Variant: return t.import_state(s, typed(&"BustleThoughtDef", thoughts()))]
		&"BustlePersonality":
			return [make(name), func(t: Object, s: Variant) -> Variant: return t.import_state(s, typed(&"BustleTraitDef", traits()))]
		&"BustleSequenceRunner":
			return [make(name), func(t: Object, s: Variant) -> Variant: return t.import_state(runner_sequence(), s)]
	return [call("_target_" + String(name).trim_prefix("Bustle").to_snake_case()) if has_method(
		"_target_" + String(name).trim_prefix("Bustle").to_snake_case()) else make(name), plain]


## A [param name] with state in every part of its save.
func populated(name: StringName) -> Object:
	var made: Object = target(name)[0]
	call("_fill_" + String(name).trim_prefix("Bustle").to_snake_case(), made)
	return made


# --- Shared definitions ---------------------------------------------------------------------

## Two thoughts: a warm one and a sour one.
func thoughts() -> Array:
	var out: Array = []
	for row: Array in [[&"warm_meal", 8.0], [&"cold_morning", -6.0]]:
		var def: Object = make(&"BustleThoughtDef")
		def.id = row[0]
		def.value = row[1]
		def.duration_hours = 24.0
		out.append(def)
	return out


## Two traits.
func traits() -> Array:
	var out: Array = []
	for id: StringName in [&"early_riser", &"patient"]:
		var def: Object = make(&"BustleTraitDef")
		def.id = id
		out.append(def)
	return out


## A two-step sequence: wait, then wait again.
func sequence() -> Object:
	var seq: Object = make(&"BustleActionSequence")
	for minutes: int in [30, 20]:
		var step: Object = make(&"BustleActionStep")
		step.action = &"wait"
		step.params = {"minutes": minutes}
		seq.steps.append(step)
	return seq


## The runner's sequence: a wait, then an action nothing handles, so it fails on purpose.
func runner_sequence() -> Object:
	var seq: Object = sequence()
	seq.steps[1].action = &"ring_bell"
	return seq


func profile() -> Object:
	return make(&"BustlePerceptionProfile")


func library(goal_id: StringName) -> Object:
	var goal: Object = make(&"BustleGoalDef")
	goal.id = goal_id
	goal.band = 2
	goal.sequence = sequence()
	var lib: Object = make(&"BustleGoalLibrary")
	lib.goals.append(goal)
	return lib


func _mood() -> Object:
	var mood: Object = make(&"BustleMood")
	mood.start(0)
	return mood


func _need(id: StringName) -> Object:
	var def: Object = make(&"BustleNeedDef")
	def.id = id
	def.rate_per_hour = 2.0
	return def


func _schedule_def() -> Object:
	var day: Object = make(&"BustleScheduleDay")
	var block: Object = make(&"BustleScheduleBlock")
	block.activity = &"bake"
	block.start_minute = 360
	block.end_minute = 720
	day.blocks.append(block)
	var def: Object = make(&"BustleScheduleDef")
	def.id = &"bakery_day"
	def.day = day
	return def


func _affordance_def(id: StringName) -> Object:
	var def: Object = make(&"BustleAffordanceDef")
	def.id = id
	def.capacity = 2
	def.hold_minutes = 60
	def.relief[&"thirst"] = 40.0
	return def


# --- Targets: what a save needs to load -------------------------------------------------------

func _target_affordance() -> Object:
	return make(&"BustleAffordance", [&"well", _affordance_def(&"draw_water")])


func _target_affordance_set() -> Object:
	var set_: Object = make(&"BustleAffordanceSet")
	set_.add(_target_affordance())
	return set_


func _target_need_set() -> Object:
	var needs: Object = make(&"BustleNeedSet")
	for id: StringName in [&"hunger", &"thirst"]:
		needs.add_need(_need(id))
	return needs


func _target_schedule() -> Object:
	var schedule: Object = make(&"BustleSchedule")
	schedule.set_def(_schedule_def())
	return schedule


func _target_schedule_roster() -> Object:
	var roster: Object = make(&"BustleScheduleRoster")
	for id: StringName in [BAKER, SMITH]:
		roster.add_agent(id, _schedule_def())
	return roster


func _target_society() -> Object:
	var society: Object = make(&"BustleSociety", [SEED])
	society.register_archetype(BAKER, library(&"bake"))
	society.register_archetype(SMITH, library(&"forge"))
	return society


func _target_mental_state() -> Object:
	return make(&"BustleMentalState", [BAKER])


func _target_life_stages() -> Object:
	var rules: Object = make(&"BustleLifeStageRules")
	for row: Array in [[&"child", 0.0], [&"adult", 18.0 * 60.0], [&"elder", 60.0 * 60.0]]:
		var stage: Object = make(&"BustleLifeStageDef")
		stage.id = row[0]
		stage.min_days = row[1]
		rules.stages.append(stage)
	rules.days_per_year = 60.0
	return make(&"BustleLifeStages", [rules])


func _target_director() -> Object:
	var director: Object = make(&"BustleDirector")
	for id: StringName in [&"harvest_fair", &"cold_snap"]:
		var def: Object = make(&"BustleEventDef")
		def.id = id
		def.weight = 1.0
		director.add_event(def)
	return director


func _target_careers() -> Object:
	var careers: Object = make(&"BustleCareers")
	var def: Object = make(&"BustleCareerDef")
	def.id = &"bakery"
	def.role = &"bakehouse"
	def.activity = &"bake"
	for rank_id: StringName in [&"apprentice", &"master"]:
		var rank: Object = make(&"BustleCareerRank")
		rank.id = rank_id
		def.ranks.append(rank)
	careers.add_def(def)
	careers.roster.jobs.schedules[&"bakehouse"] = _schedule_def()
	careers.roster.roles.set_holder(&"bakehouse", BAKER)
	careers.roster.add_agent(BAKER)
	return careers


func _target_skills() -> Object:
	var skills: Object = make(&"BustleSkills")
	var def: Object = make(&"BustleSkillDef")
	def.id = &"baking"
	skills.add_def(def)
	var passion: Object = make(&"BustlePassionDef")
	passion.skill = &"baking"
	skills.add_passion_def(passion)
	return skills


func _target_job_board() -> Object:
	var board: Object = make(&"BustleJobBoard")
	var def: Object = make(&"BustleWorkType")
	def.id = &"fetch_water"
	def.minutes = 30
	board.add_type(def)
	return board


func _target_room_thoughts() -> Object:
	var rooms: Object = make(&"BustleRoomThoughts")
	var rule: Object = make(&"BustleRoomThought")
	rule.score = &"beauty"
	rule.at_least = 0.4
	rule.thought = thoughts()[0]
	rooms.add_rule(rule)
	rooms.ports = make(&"BustlePorts")
	rooms.ports.environment = make(&"BustleEnvironmentPort")
	return rooms


func _target_aspirations() -> Object:
	var aspirations: Object = make(&"BustleAspirations", [BAKER])
	aspirations.config = make(&"BustleAspirationConfig")
	aspirations.config.auto_wants = 0
	for id: StringName in [&"bake_bread", &"visit_the_well"]:
		var want: Object = make(&"BustleWantDef")
		want.id = id
		want.points = 5
		aspirations.config.wants.append(want)
	var fear: Object = make(&"BustleFearDef")
	fear.id = &"dark_lanes"
	fear.trigger = &"robbed"
	fear.avoid_goals.append(&"stroll")
	aspirations.config.fears.append(fear)
	return aspirations


func _target_ambitions() -> Object:
	var ambitions: Object = make(&"BustleAmbitions", [BAKER])
	ambitions.config = make(&"BustleAmbitionConfig")
	ambitions.config.templates.clear()
	for row: Array in [[&"open_a_bakery", &"train_an_apprentice", &"bakery"], [&"train_an_apprentice", &"", &"apprentice"]]:
		var def: Object = make(&"BustleAmbitionDef")
		def.id = row[0]
		def.next = row[1]
		def.target = 1.0
		def.progress_input = row[2]
		ambitions.config.templates.append(def)
	return ambitions


func _target_crime_watch() -> Object:
	var society: Object = _target_society()
	society.register_archetype(&"villager", make(&"BustleGoalLibrary"))
	var crime: Object = make(&"BustleCrime", [society])
	return make(&"BustleCrimeWatch", [crime])


func _target_mental_behaviour() -> Object:
	var behaviour: Object = make(&"BustleMentalBehaviour")
	behaviour.society = _target_society()
	return behaviour


func _target_romance() -> Object:
	var romance: Object = make(&"BustleRomance")
	romance.social = make(&"BustleSocialStore")
	romance.rules.jealousy_verbs.append(&"flirt")
	romance.compatibility = func(_a: StringName, _b: StringName) -> float: return 1.0
	return romance


func _target_social_interactions() -> Object:
	var social: Object = make(&"BustleSocialInteractions")
	social.store = make(&"BustleSocialStore")
	var greeting: Object = make(&"BustleInteractionDef")
	greeting.id = &"greet"
	greeting.days = 1.0
	social.greeting = greeting
	return social


# --- Fills: state in every part of the save ---------------------------------------------------

func _fill_affordance(a: Object) -> void:
	a.reserve(BAKER, 600)
	a.reserve(SMITH, 610)
	a.owner = MILLER
	a.payee = SMITH


func _fill_affordance_set(s: Object) -> void:
	_fill_affordance(s.get_affordance(&"well"))






func _fill_awareness(a: Object) -> void:
	for id: StringName in [SMITH, MILLER]:
		var meter: Object = a.meter_for(id, profile())
		meter.level = 0.4
		meter.last_known_position = Vector3(2, 0, 3)
		meter.has_last_known = true




func _fill_conflict(c: Object) -> void:
	c.quarrel(BAKER, SMITH, 600, 1.0)




func _fill_detection_meter(m: Object) -> void:
	m.level = 0.6
	m.last_known_position = Vector3(1, 0, 2)
	m.has_last_known = true


func _fill_director(d: Object) -> void:
	d.update(600, {}, false)




func _fill_job_board(b: Object) -> void:
	b.post(&"fetch_water", MILLER, 600, 720, &"well")




func _fill_life_stages(s: Object) -> void:
	s.birth(BAKER, 20.0 * 60.0)
	s.birth(SMITH, 5.0 * 60.0)
	s.birth(MILLER, 70.0 * 60.0)
	s.advance_to(1440 * 3)
	s.note_death(MILLER, "old_age")








func _fill_mood(m: Object) -> void:
	var defs := thoughts()
	m.add_thought(defs[0], {"kind": "meal"})
	m.add_thought(defs[1])
	m.emotion = &"content"
	m.advance_to(120)


func _fill_need_set(n: Object) -> void:
	n.set_pressure(&"hunger", 0.35)
	n.set_pressure(&"thirst", 0.6)




func _fill_property_port(p: Object) -> void:
	p.register(&"bread_basket", BAKER, &"bakehouse", {&"hunger": 20.0})
	p.register(&"anvil", SMITH, &"forge", {}, true)






func _fill_schedule(s: Object) -> void:
	s.attend(400, &"bake")


func _fill_schedule_roster(_r: Object) -> void:
	pass




func _fill_skills(s: Object) -> void:
	s.add_xp(BAKER, &"baking", 150.0)
	s.assign_passion(BAKER, &"baking")








func _fill_trade_port(t: Object) -> void:
	t.set_balance(BAKER, 40)
	t.set_balance(SMITH, 15)


func _fill_ambitions(a: Object) -> void:
	a.pin = &"open_a_bakery"
	a.update(600, null, {&"bakery": 0.5})
	a.update(1500, null, {&"bakery": 1.0, &"apprentice": 0.25})


func _fill_aspirations(a: Object) -> void:
	a.post_want(&"bake_bread", 600)
	a.post_want(&"visit_the_well", 600)
	a.fulfill(&"visit_the_well", 700)
	a.add_points(12, &"good_day")
	a.update(800, null, {}, [&"robbed"] as Array[StringName])


func _fill_careers(c: Object) -> void:
	c.assign(BAKER, &"bakery", &"apprentice", 600)


func _fill_crime_watch(w: Object) -> void:
	var society: Object = w.crime.society
	var hunger: Object = make(&"BustleNeedSet")
	hunger.add_need(_need(&"food"))
	hunger.set_pressure(&"food", 1.0)
	w.crime.needs_of = func(id: StringName) -> Object: return hunger if id == MILLER else null
	w.crime.is_observed = func(_t: StringName, _p: StringName) -> bool: return false
	var honest: Object = make(&"BustlePersonality")
	honest.set_slider(&"honesty", 100.0)
	w.judge.personality_of = func(id: StringName) -> Object: return honest if id == SMITH else null
	var memories := {}
	w.memory_of = func(id: StringName) -> Object: return memories.get_or_add(id, make(&"BustleMemory"))
	for row: Array in [[MILLER, &"market"], [SMITH, &"market"], [&"warden", &"hall"], [BAKER, &"bakehouse"]]:
		society.add_agent(row[0], &"villager").area = row[1]
	society.ports.world.set_place(&"hall", Vector3(40, 0, 0))
	society.ports.roles.set_holder(w.AUTHORITY, &"warden")
	society.ports.property.register(&"loaf", BAKER, &"market", {&"food": 0.5})
	w.crime.consider(MILLER, 600)
	w.crime.steal(MILLER, 600)


func _fill_environment_port(e: Object) -> void:
	e.set_room(BAKER, &"bakehouse")
	e.set_scores(&"bakehouse", {&"beauty": 0.5, &"comfort": 0.25})


func _fill_leisure(l: Object) -> void:
	l.kinds.append_array([&"music", &"stroll"] as Array[StringName])
	l.use(&"music")
	l.use(&"stroll")
	l.use(&"music")


func _fill_memory(m: Object) -> void:
	m.note(&"person", SMITH, &"square", Vector3(1, 0, 2), &"saw", 600)
	m.note(&"person", MILLER, &"mill", null, &"heard", 610)


func _fill_mental_behaviour(b: Object) -> void:
	var society: Object = b.society
	society.set_port(&"social", make(&"BustleSocialStore"))
	for id: StringName in [BAKER, SMITH]:
		society.add_agent(id, id).area = &"square"
	society.ports.social.set_kind(BAKER, SMITH, &"rival")
	var mood: Object = _mood()
	mood.mood = -100.0
	b.update(BAKER, 600, mood)
	b.insult(BAKER, SMITH, 610)


func _fill_mental_state(s: Object) -> void:
	var mood: Object = _mood()
	mood.mood = -100.0
	s.update(600, mood)


func _fill_personality(p: Object) -> void:
	p.set_slider(&"sociability", 40.0)
	p.set_slider(&"diligence", 75.0)
	p.add_trait(traits()[0])


func _fill_romance(r: Object) -> void:
	for pair: Array in [[BAKER, SMITH], [SMITH, BAKER]]:
		r.social.add_opinion(pair[0], pair[1], 90.0, {"kind": "kindness"}, 30.0)
	r.update(BAKER, SMITH, 600)
	r.social.add_opinion(SMITH, MILLER, 90.0, {"kind": "kindness"}, 30.0)
	r.update_all([BAKER, SMITH, MILLER] as Array[StringName], 700)


func _fill_room_thoughts(r: Object) -> void:
	r.ports.environment.set_room(BAKER, &"bakehouse")
	r.ports.environment.set_scores(&"bakehouse", {&"beauty": 0.8})
	r.sync(BAKER)


func _fill_sequence_runner(r: Object) -> void:
	r.start(runner_sequence(), BAKER, 600, &"bake")
	r.tick(0.1, 640)
	r.tick(0.1, 641)
	r.context.data["loaves"] = 3


func _fill_social_interactions(s: Object) -> void:
	s.store.set_time(600)
	s.greet(BAKER, SMITH, 600, &"square")


func _fill_social_store(s: Object) -> void:
	s.set_time(600)
	for i: int in 3:
		var deed: StringName = s.record_deed(BAKER, &"helped", SMITH, &"square", [{"id": MILLER}] as Array[Dictionary])
		s.add_opinion(SMITH, BAKER, 30.0, {"deed": String(deed)}, 3.0)
	s.update_kinds(SMITH, BAKER)
	s.set_kind(BAKER, SMITH, &"neighbour")


func _fill_society(s: Object) -> void:
	var baker: Object = s.add_agent(BAKER, BAKER, &"village")
	var smith: Object = s.add_agent(SMITH, SMITH)
	baker.area = &"square"
	baker.data = {"loaves": 3, "notes": ["early"]}
	smith.position = Vector3(1.5, 0, -2)
	smith.has_position = true
	s.set_protection(SMITH, 1)
	for state: Object in [baker, smith]:
		var senses: Object = make(&"BustleSenses")
		senses.now_minutes = 10
		state.brain.tick(0.1, senses)
	var lock: Object = make(&"BustleLock")
	lock.lock_id = &"curfew"
	lock.place = &"home"
	s.lock(BAKER, lock)
