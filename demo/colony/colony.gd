# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## The colony demo: four settlers with a bed each, a stove, a field plot and a crate, a day block of
## work in the field, and one cold snap the demo injects as a host event. Everything here is demo
## data, and every number is a starting point, not tuning.
##
## - **Needs:** food (rises while awake, slowly while asleep), sleep (rises while awake) and warmth
##   (still, until the cold snap: then it rises for everyone).
## - **Mood** (the needs_mood module): need thoughts while hungry, tired or cold, a good thought
##   after a hot meal, a night in bed or a harvest, and a bad one when the cold snap starts. A mood
##   low enough starts a mental state, which this demo only records.
## - **Social** (the built-in social store): settlers A and B are friends, and so are C and D. A
##   settler who notices a friend in a low mood or state may comfort them, through the demo's
##   [code]comfort[/code] goal and interaction.
## - **Perception:** who notices whom. Off, a settler notices everyone awake in its area.
## - **Goals:** [code]use_object[/code] (personal), [code]eat_now[/code], [code]sleep_now[/code] and
##   [code]warm_up[/code] (urgent), [code]farm[/code] (duty: work the field during the day
##   block), and [code]unwind[/code] (idle: sit by the hearth when nothing else calls, so a free
##   evening isn't hours of standing still). [code]comfort[/code] joins them with social on.
##
## Each module can be left out of a build ([method build]); the rest still runs.

const Harness := preload("res://demo/harness/demo_harness.gd")
const LONER := preload("res://demo/traits/loner.tres")
const OUTGOING := preload("res://demo/traits/outgoing.tres")
const LOW_SPIRITED := preload("res://demo/traits/low_spirited.tres")
const COMFORT_GOAL := preload("res://demo/social/comfort_goal.tres")
const SOCIAL_DIR := "res://demo/social/%s.tres"
const INTERACTIONS: Array[StringName] = [&"chitchat", &"deep_talk", &"kind_words", &"slight", &"insult", &"comfort"]

## The four settlers.
const SETTLER_A := &"settler_a"
const SETTLER_B := &"settler_b"
const SETTLER_C := &"settler_c"
const SETTLER_D := &"settler_d"
const SETTLERS: Array[StringName] = [SETTLER_A, SETTLER_B, SETTLER_C, SETTLER_D]
## Each settler's own bed.
const BEDS: Dictionary[StringName, StringName] = {SETTLER_A: &"bed_a", SETTLER_B: &"bed_b",
	SETTLER_C: &"bed_c", SETTLER_D: &"bed_d"}
## Each settler's age in years, with life stages on: two adults, an elder and a child.
const AGES: Dictionary[StringName, float] = {SETTLER_A: 30.0, SETTLER_B: 34.0, SETTLER_C: 66.0,
	SETTLER_D: 10.0}
## The modules a build can leave out.
const NEEDS_MOOD := &"needs_mood"
const SOCIAL := &"social"
const PERCEPTION := &"perception"
const MODULES: Array[StringName] = [NEEDS_MOOD, SOCIAL, PERCEPTION]
## The areas.
const HOME := &"home"
const FIELD := &"field"
## The goal and schedule activity for field work.
const FARM := &"farm"
## The field work block, in minutes of the day.
const WORK_START := 480
const WORK_END := 960
## The goal and schedule activity for the night in bed, from 22:00 to 07:00. A settler goes to bed
## in it while sleep presses at least [constant DROWSY], so it gets up once rested.
const REST := &"rest"
const REST_START := 1320
const REST_END := 420
const DROWSY := 0.3
## The goal and object for free time: sitting by the hearth.
const UNWIND := &"unwind"
const HEARTH := &"hearth"
## The cold snap: from 18:00 on the third day, for a day.
const COLD_SNAP := &"cold_snap"
const COLD_START := 2 * 1440 + 1080
const COLD_MINUTES := 1440
## How hard a need must press before it becomes urgent.
const URGENT_FOOD := 0.8
const URGENT_SLEEP := 0.95
const URGENT_WARMTH := 0.7
## Food counts for nothing below this, so a settler eats when peckish rather than all day.
const PECKISH := 0.3
## Sleep counts for nothing below this (about 16 hours up), so a settler doesn't nap.
const SLEEPY := 0.8
## The goal that takes posted jobs (with a board), in free time.
const TAKE_JOB := &"take_job"
## The demo work types: a harvest (diligence), an errand (curiosity) and mending (needs the
## [code]mender[/code] role).
const WORK_TYPES: Array[StringName] = [&"harvest", &"errand", &"mending"]
const JOBS_DIR := "res://demo/jobs/%s.tres"
## The run starts at 06:00 on the first day, as the settlers wake.
const START := 360


## A colony run seeded [param world_seed] with [param modules] on (all three by default), and the
## cold snap unless [param cold_snap] is false. With [param board], settlers also weigh its postings
## in their free time ([constant TAKE_JOB]). With [param aspirations] (for example
## [method aspirations]), settlers also have wants, fears and points. With [param romance] (for
## example [method romance_rules], and the social module on), the courtship ladder runs: the third
## and fourth settlers start fond of each other, and the first two are fond too but recorded as
## siblings, so they never court. With [param life_stages] (for example [method life_stage_rules]),
## each settler has an age ([constant AGES]) and its stage's gates.
static func build(world_seed: int = 1, modules: Array[StringName] = MODULES, cold_snap: bool = true,
		board: BustleJobBoard = null, aspirations: BustleAspirationConfig = null,
		romance: BustleRomanceRules = null, life_stages: BustleLifeStageRules = null) -> Harness:
	var colony := Harness.new(world_seed)
	if life_stages != null:
		colony.enable_life_stages(life_stages)
	if board != null:
		colony.enable_jobs(board, TAKE_JOB)
	if aspirations != null:
		colony.enable_aspirations(aspirations)
	colony.now = START
	colony.home_area = HOME
	colony.sleep_object = &""
	colony.sleep_objects = BEDS.values()
	colony.scoring.need_curves[&"food"] = _from(PECKISH)
	colony.scoring.need_curves[&"sleep"] = _from(SLEEPY)
	var x := 0.0
	for id: StringName in SETTLERS:
		var bed := _object(BEDS[id], {&"sleep": 1.0}, [&"rest"], 1, 600, HOME, Vector3(x, 0, 0))
		bed.owner = id
		colony.add_object(bed, 480)
		x += 1.5
	colony.add_object(_object(&"stove", {&"food": 0.6, &"warmth": 0.8}, [&"cook"], 2, 60, HOME, Vector3(1.5, 0, 4)), 30)
	colony.add_object(_object(&"crate", {&"food": 0.35}, [&"stores"], 2, 30, HOME, Vector3(-2, 0, 4)), 10)
	colony.add_object(_object(&"field", {}, [&"work"], 4, 90, FIELD, Vector3(60, 0, 0)), 60)
	colony.add_object(_object(HEARTH, {}, [&"quiet"], 4, 60, HOME, Vector3(0, 0, 6)), 60)
	if modules.has(NEEDS_MOOD):
		colony.enable_mood(need_thoughts())
		colony.use_thoughts = {&"stove": thought(&"hot_meal", 5.0, 6.0, &"content", 1),
			&"field": thought(&"harvest", 3.0, 6.0, &"proud", 2)}
		var rested := thought(&"slept_well", 4.0, 8.0, &"rested", 1)
		for bed: StringName in BEDS.values():
			colony.use_thoughts[bed] = rested
	if modules.has(SOCIAL):
		colony.enable_social(BustleSocialStore.new(), interactions())
	if modules.has(PERCEPTION):
		var profile := BustlePerceptionProfile.new()
		profile.sight_angle_deg = 360.0
		profile.peripheral_angle_deg = 360.0
		colony.enable_perception(profile)
	var days := routine()
	var traits: Array = [[LONER], [OUTGOING], [LOW_SPIRITED], []]
	for i: int in SETTLERS.size():
		var own: Array[BustleTraitDef] = []
		own.assign(traits[i])
		var library := goals(BEDS[SETTLERS[i]], modules.has(SOCIAL))
		if board != null:
			library.goals.append(job_goal())
		colony.add_agent(SETTLERS[i], library, needs(), own, days)
		if colony.life_stages != null:
			colony.life_stages.set_age(SETTLERS[i], life_stages.days_of(AGES[SETTLERS[i]]))
	if colony.store != null:
		for pair: Array in [[SETTLER_A, SETTLER_B], [SETTLER_C, SETTLER_D]]:
			colony.store.set_kind(pair[0], pair[1], &"friend")
			colony.store.set_kind(pair[1], pair[0], &"friend")
	if cold_snap:
		colony.add_event(COLD_SNAP, COLD_START, COLD_MINUTES, &"cold", thought(&"bitter_weather", -6.0, 24.0, &"miserable", 1))
	if romance != null and colony.store != null:
		var ladder := colony.enable_romance(romance)
		for pair: Array in [[SETTLER_A, SETTLER_B], [SETTLER_C, SETTLER_D]]:
			for way: Array in [pair, [pair[1], pair[0]]]:
				colony.store.add_opinion(way[0], way[1], 30.0, {"why": "fond"}, 30.0)
		ladder.link_family(SETTLER_A, SETTLER_B, &"sibling")
	return colony


## The modules a full session can leave out, beyond [constant MODULES]: each one switched on
## through the shared harness (an enable call or, for the modules it has no switch for, an agent
## hook in [method session]).
const JOBS := &"jobs"
const SKILLS := &"skills"
const CAREERS := &"careers"
const ENVIRONMENT := &"environment"
const ASPIRATIONS := &"aspirations"
const AMBITIONS := &"ambitions"
const ROMANCE := &"romance"
const LIFE_STAGES := &"life_stages"
const HEALTH := &"health"
const DIRECTOR := &"director"
const SESSION_MODULES: Array[StringName] = [NEEDS_MOOD, SOCIAL, PERCEPTION, JOBS, SKILLS, CAREERS, ENVIRONMENT,
	ASPIRATIONS, AMBITIONS, ROMANCE, LIFE_STAGES, HEALTH, DIRECTOR]
## The farming career's role, held by settler A.
const FARMER := &"farmer"
## Settler C is ill (in some pain, needing care, visibly sick) from day 5 to day 8, with health on.
const ILL_FROM := 5 * 1440
const ILL_TO := 8 * 1440


## A roster that reads the harness's own schedules, so careers see real attendance.
class SharedRoster extends BustleScheduleRoster:
	var run: WeakRef

	func schedule_of(id: StringName) -> BustleSchedule:
		return run.get_ref().schedule_of(id)


## The demo's host health: settler C falls ill for three days. Readings only; Bustle keeps none.
class SickBay extends BustleHealthPort:
	var run: WeakRef

	func _ill(id: StringName) -> bool:
		var now: int = run.get_ref().now
		return id == SETTLER_C and now >= ILL_FROM and now < ILL_TO

	func pain(id: StringName) -> float:
		return 0.4 if _ill(id) else 0.0

	func needs_care(id: StringName) -> float:
		return 0.5 if _ill(id) else 0.0

	func visible_tags(id: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		if _ill(id):
			out.append(&"sick")
		return out


## A full colony session seeded [param world_seed], with [param modules] on (all by default): the
## colony of [method build] with its board, wants, courtship and life stages, plus the story deck,
## farming skill, a farming career for settler A (with an ambition to be promoted), rooms indoors at
## home, a three-day illness, and a log of who first notices whom. Run it for 15 days. Without any
## module it runs like [code]build(seed, [])[/code]. Every number is a starting point, not tuning.
static func session(world_seed: int = 1, modules: Array[StringName] = SESSION_MODULES) -> Harness:
	var core: Array[StringName] = []
	core.assign(MODULES.filter(func(m: StringName) -> bool: return modules.has(m)))
	var ports := BustlePorts.new()
	ports.trade.set_balance(&"store", 100)
	var board := BustleJobBoard.new(work_types(), ports) if modules.has(JOBS) else null
	var run := build(world_seed, core, true, board, aspirations() if modules.has(ASPIRATIONS) else null,
		romance_rules() if modules.has(ROMANCE) else null, life_stage_rules() if modules.has(LIFE_STAGES) else null)
	var me: WeakRef = weakref(run)
	if board != null:
		for i: int in 3:
			board.post(&"errand", &"store", run.now)
	if modules.has(DIRECTOR):
		var rules := BustleDirectorRules.new()
		rules.beat_gap_minutes = 360
		run.enable_director(director_events(), rules)
	if modules.has(SKILLS):
		var farming := BustleSkillDef.new()
		farming.id = &"farming"
		farming.xp_curve = [60.0]
		ports.skills = BustleSkills.new([farming] as Array[BustleSkillDef])
		run.agent_hooks.append(func(id: StringName, _senses: BustleSenses) -> void:
			var skills: BustleSkills = ports.skills
			var before: int = floori(skills.level(id, &"farming"))
			if me.get_ref().using_of(id) == &"field":
				skills.add_xp(id, &"farming", 1.0)
			if floori(skills.level(id, &"farming")) > before:
				me.get_ref().timeline.add(me.get_ref().now, id, &"skill", {"skill": "farming", "level": floori(skills.level(id, &"farming"))}))
	if modules.has(CAREERS):
		ports.roles.set_holder(FARMER, SETTLER_A)
		var schedules := BustleRoleSchedules.new()
		schedules.schedules = {FARMER: routine()}
		var roster := SharedRoster.new(ports.roles, schedules)
		roster.run = me
		roster.add_agent(SETTLER_A)
		var rank := BustleCareerRank.new()
		rank.id = &"hand"
		var lead := BustleCareerRank.new()
		lead.id = &"lead_hand"
		var track := BustleCareerDef.new()
		track.id = &"farming"
		track.role = FARMER
		track.activity = FARM
		track.off_site = false
		track.ranks = [rank, lead]
		var careers := BustleCareers.new([track] as Array[BustleCareerDef], roster, ports)
		careers.assign(SETTLER_A, &"farming", &"hand", run.now)
		careers.reviewed.connect(func(id: StringName, career: StringName, _performance: float, outcome: StringName, _at: int) -> void:
			me.get_ref().timeline.add(me.get_ref().now, id, &"career", {"career": String(career), "outcome": String(outcome)}))
		var track_ref: WeakRef = weakref(careers)
		careers.promotion_due.connect(func(id: StringName, career: StringName, _from: StringName, to: StringName) -> void:
			track_ref.get_ref().assign(id, career, to, me.get_ref().now))
		run.agent_hooks.append(func(id: StringName, senses: BustleSenses) -> void:
			if id == SETTLER_A:
				careers.update(id, me.get_ref().now, me.get_ref().mood_of(id))
				careers.fill_inputs(id, senses.inputs))
	if modules.has(AMBITIONS):
		var hopes := BustleAmbitions.new(SETTLER_A)
		hopes.pin = &"get_promoted"
		hopes.ambition_started.connect(func(agent: StringName, id: StringName, _info: Dictionary) -> void:
			me.get_ref().timeline.add(me.get_ref().now, agent, &"ambition", {"ambition": String(id), "what": "started"}))
		hopes.ambition_completed.connect(func(agent: StringName, id: StringName, _info: Dictionary) -> void:
			me.get_ref().timeline.add(me.get_ref().now, agent, &"ambition", {"ambition": String(id), "what": "completed"}))
		run.agent_hooks.append(func(id: StringName, senses: BustleSenses) -> void:
			if id == SETTLER_A:
				var facts: Dictionary = senses.inputs.duplicate()
				facts[&"has_role"] = true
				hopes.update(me.get_ref().now, me.get_ref().personality_of(id), facts))
	if modules.has(ENVIRONMENT):
		var rooms := BustleEnvironmentPort.new()
		run.enable_environment(rooms)
		run.agent_hooks.append(func(id: StringName, _senses: BustleSenses) -> void:
			var room: StringName = &"hall" if me.get_ref().area_of(id) == HOME else &""
			if rooms.room_of(id) != room:
				rooms.set_room(id, room)
				me.get_ref().timeline.add(me.get_ref().now, id, &"room", {"room": String(room)}))
	if modules.has(PERCEPTION):
		var seen := {}
		run.agent_hooks.append(func(id: StringName, _senses: BustleSenses) -> void:
			for other: StringName in me.get_ref().noticed_by(id):
				if not seen.has([id, other]):
					seen[[id, other]] = true
					me.get_ref().timeline.add(me.get_ref().now, id, &"notice", {"of": String(other)}))
	if modules.has(HEALTH):
		var sick_bay := SickBay.new()
		sick_bay.run = me
		ports.health = sick_bay
		var health := BustleHealthBehaviour.new(null, ports)
		var held := {}
		for id: StringName in SETTLERS:
			run.brain_of(id).gate = health.allows
		run.agent_hooks.append(func(id: StringName, senses: BustleSenses) -> void:
			health.apply(id, null)
			health.fill_inputs(id, senses.inputs)
			var thoughts: Array[StringName] = health.sync(id, me.get_ref().mood_of(id))
			if thoughts != held.get(id, []):
				held[id] = thoughts
				me.get_ref().timeline.add(me.get_ref().now, id, &"health", {"thoughts": thoughts.map(func(t: StringName) -> String: return String(t))}))
	return run


## The demo's courtship lines: lower than the defaults so a week shows a partnership (courting at
## 70, partners after two days at 75). It carries a breakup thought and a jealousy thought for when
## they happen; the fixture itself shows no breakup, and jealousy only once a partner takes to
## someone else.
static func romance_rules() -> BustleRomanceRules:
	var rules := BustleRomanceRules.new()
	rules.partner_opinion = 75
	rules.partner_days = 2.0
	rules.jealousy_opinion = 70
	rules.breakup_thought = thought(&"heartbroken", -10.0, 48.0, &"miserable", 1)
	rules.jealousy_thought = thought(&"jealous", -5.0, 12.0, &"miserable", 2)
	return rules


## The demo's life stages, with experimental ages: a child (no field work: neither the
## [constant FARM] goal nor anything tagged [code]work[/code]), an adult from 16 and an elder from 60,
## with a 360-day year. Demo data, not a calendar.
static func life_stage_rules() -> BustleLifeStageRules:
	var rules := BustleLifeStageRules.new()
	rules.days_per_year = 360.0
	for row: Array in [[&"child", 0.0, [FARM], [&"work"]], [&"adult", 16.0, [], []], [&"elder", 60.0, [], []]]:
		var stage := BustleLifeStageDef.new()
		stage.id = row[0]
		stage.min_days = rules.days_of(row[1])
		stage.blocked_goal_tags.assign(row[2])
		stage.blocked_affordance_tags.assign(row[3])
		rules.stages.append(stage)
	return rules


## A small neutral story deck for [method Harness.enable_director], with experimental values:
## [br]- [code]gale[/code] raises tension (0.4): everyone feels windswept (−4 for 12 hours); every 2 days;
## [br]- [code]fair_day[/code] relieves it (−0.4): everyone enjoys the fine weather (+3 for 12 hours),
## with at least 2 settlers; every day;
## [br]- [code]travellers[/code] asks the world for a visitor (the default world makes none), with
## at most 10 settlers; every 3 days.
## [br]Beside the fixed cold snap, which it doesn't replace.
static func director_events() -> Array[BustleEventDef]:
	var out: Array[BustleEventDef] = []
	for row: Array in [[&"gale", 0.4, 2, &"windswept", -4.0, {"input": BustleDirector.INPUT_POPULATION}],
			[&"fair_day", -0.4, 1, &"fine_weather", 3.0, {"input": BustleDirector.INPUT_POPULATION, "at_least": 2}]]:
		var effect := BustleEventEffect.new()
		effect.thought = thought(row[3], row[4], 12.0, &"", 1)
		effect.target_area = BustleWorldPort.DEFAULT_AREA
		out.append(_story_event(row[0], row[1], row[2], row[5], effect))
	var visit := BustleEventEffect.new()
	visit.kind = BustleEventEffect.SPAWN
	visit.spawn_kind = &"visitor"
	visit.spawn_area = BustleWorldPort.DEFAULT_AREA
	out.append(_story_event(&"travellers", 0.0, 3, {"input": BustleDirector.INPUT_POPULATION, "at_most": 10}, visit))
	return out


static func _story_event(id: StringName, tension: float, days: int, rule: Dictionary, effect: BustleEventEffect) -> BustleEventDef:
	var def := BustleEventDef.new()
	def.id = id
	def.tension = tension
	def.cooldown_minutes = days * 1440
	def.requires = [rule]
	def.effects = [effect]
	return def


## The settlers' needs.
static func needs() -> Array[BustleNeedDef]:
	return [
		_need(&"food", 0.055, [&"awake"], {&"asleep": 0.02}),
		_need(&"sleep", 0.05, [&"awake"], {}),
		_need(&"warmth", 0.0, [], {&"cold": 0.12, &"asleep": -0.12}),
	]


## The need thoughts: hungry, tired and cold, held while the need presses.
static func need_thoughts() -> Array[BustleThoughtDef]:
	var out: Array[BustleThoughtDef] = []
	for row: Array in [[&"hungry", &"food", 0.6, -8.0], [&"tired", &"sleep", 0.75, -6.0], [&"cold", &"warmth", 0.3, -12.0]]:
		var def := thought(row[0], row[3], 0.0, &"miserable", 1)
		def.reason_kind = &"need"
		def.need = row[1]
		def.need_at_least = row[2]
		out.append(def)
	return out


## A thought [param id] worth [param value] for [param hours] game hours (0: held).
static func thought(id: StringName, value: float, hours: float, emotion: StringName, stack: int) -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = id
	def.value = value
	def.duration_hours = hours
	def.emotion = emotion
	def.stack_limit = stack
	return def


## The demo interaction set. Comfort, the friend's opener, also leaves its recipient a thought.
static func interactions() -> Array[BustleInteractionDef]:
	var out: Array[BustleInteractionDef] = []
	for id: StringName in INTERACTIONS:
		var def: BustleInteractionDef = load(SOCIAL_DIR % id)
		if id == &"comfort":
			def = def.duplicate()
			def.recipient_thought = thought(&"comforted", 15.0, 12.0, &"relieved", 1)
		out.append(def)
	return out


## The goals of a settler who sleeps in [param bed], with [code]comfort[/code] when
## [param social].
static func goals(bed: StringName, social: bool) -> BustleGoalLibrary:
	var library := BustleGoalLibrary.new()
	var use := BustleGoalDef.new()
	use.id = &"use_object"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	use.sequence = _sequence(&"use", {})
	library.goals.append(use)
	library.goals.append(_urgent(&"eat_now", &"need.food", URGENT_FOOD, &"stove"))
	library.goals.append(_urgent(&"sleep_now", &"need.sleep", URGENT_SLEEP, bed))
	library.goals.append(_urgent(&"warm_up", &"need.warmth", URGENT_WARMTH, &"stove"))
	var farm := BustleGoalDef.new()
	farm.id = FARM
	farm.band = BustleBands.DUTY
	farm.considerations.append(_consider(&"schedule.farm", 0.5))
	farm.sequence = _sequence(&"use", {"object": &"field"})
	library.goals.append(farm)
	var rest := BustleGoalDef.new()
	rest.id = REST
	rest.band = BustleBands.DUTY
	rest.considerations.append(_consider(&"schedule.rest", 0.5))
	rest.considerations.append(_consider(&"need.sleep", DROWSY))
	rest.sequence = _sequence(&"use", {"object": bed})
	library.goals.append(rest)
	var unwind := BustleGoalDef.new()
	unwind.id = UNWIND
	unwind.band = BustleBands.IDLE
	unwind.sequence = _sequence(&"use", {"object": HEARTH})
	library.goals.append(unwind)
	if social:
		library.goals.append(COMFORT_GOAL)
	return library


## The colony's wants and fears, from [code]demo/aspirations/[/code]: a hearty meal at the stove
## (diligence; 5 points; boosts using the stove) and a warm evening at the hearth (sociability;
## 3 points; boosts unwinding there), and a fear of the cold formed by the cold snap, which makes the
## field less appealing for two days.
static func aspirations() -> BustleAspirationConfig:
	var config := BustleAspirationConfig.new()
	config.wants = [load("res://demo/aspirations/hearty_meal.tres"),
		load("res://demo/aspirations/warm_by_the_hearth.tres")] as Array[BustleWantDef]
	config.fears = [load("res://demo/aspirations/fear_of_cold.tres")] as Array[BustleFearDef]
	return config


## The demo work types, loaded from [code]demo/jobs/[/code].
static func work_types() -> Array[BustleWorkType]:
	var out: Array[BustleWorkType] = []
	for id: StringName in WORK_TYPES:
		out.append(load(JOBS_DIR % id))
	return out


## Taking a posted job: free time, one candidate per posting the board offers, kept for at least an
## hour. With no sequence, the settler holds it while the harness adds its work.
static func job_goal() -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = TAKE_JOB
	goal.band = BustleBands.PERSONAL
	goal.uses_advertisements = true
	goal.min_commit_minutes = 60
	return goal


## The settlers' routine, every day: the field in the day and the night in bed.
static func routine() -> BustleScheduleDef:
	var day := BustleScheduleDay.new()
	day.blocks.append(_block(FARM, WORK_START, WORK_END, FIELD))
	day.blocks.append(_block(REST, REST_START, REST_END, HOME))
	var out := BustleScheduleDef.new()
	out.id = &"settler_days"
	out.day = day
	return out


static func _block(activity: StringName, start: int, end: int, place: StringName) -> BustleScheduleBlock:
	var block := BustleScheduleBlock.new()
	block.activity = activity
	block.start_minute = start
	block.end_minute = end
	block.place = place
	return block


static func _object(id: StringName, relief: Dictionary[StringName, float], tags: Array[StringName],
		capacity: int, hold: int, area: StringName, position: Vector3) -> BustleAffordance:
	var def := BustleAffordanceDef.new()
	def.id = id
	def.relief = relief
	def.tags = tags
	def.capacity = capacity
	def.hold_minutes = hold
	return BustleAffordance.new(id, def, area, position)


static func _need(id: StringName, rate: float, rises_when: Array[StringName], conditions: Dictionary[StringName, float]) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = rises_when
	def.condition_rates = conditions
	return def


# A goal that goes to [param object] once [param input] reaches [param at].
static func _urgent(id: StringName, input: StringName, at: float, object: StringName) -> BustleGoalDef:
	var goal := BustleGoalDef.new()
	goal.id = id
	goal.band = BustleBands.URGENT
	goal.considerations.append(_consider(input, at))
	goal.sequence = _sequence(&"use", {"object": object})
	return goal


# A need curve: 0 up to [param at], then rising straight to 1 at full pressure.
static func _from(at: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(at, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


# A step consideration: 0 below [param at], 1 from it.
static func _consider(input: StringName, at: float) -> BustleConsideration:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(maxf(at - 0.001, 0.0), 0.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(at, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var consideration := BustleConsideration.new()
	consideration.input = input
	consideration.curve = curve
	return consideration


static func _sequence(action: StringName, params: Dictionary) -> BustleActionSequence:
	var step := BustleActionStep.new()
	step.action = action
	step.params = params
	var sequence := BustleActionSequence.new()
	sequence.steps.append(step)
	return sequence
