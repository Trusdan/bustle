# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## OPT-IN DEMO, OFF BY DEFAULT: the hooks Bustle added after 1.0, each called on a demo run's clock
## so a host can see it used. The house session attaches it only when its modules include
## [code]House.NEW_HOOKS[/code]. Without that, nothing here runs: the demos, their pinned timeline
## hashes and the soak are unchanged. Every scene happens at a fixed minute, and nothing is random.
## The numbers are demo data, not tuning.
## [br][br]
## In the run itself:[br]
## - aspiration points stop at a cap ([member BustleAspirationConfig.max_points]), with
##   aspirations on;[br]
## - the demo rooms are installed, and a resident at home is in the house room
##   ([code]demo/environment/demo_rooms.gd[/code]).[br]
## In side scenes on the same clock, with the run's two residents:[br]
## - a career judged by period, its window reset after closed days
##   ([member BustleCareerRank.periods], [method BustleCareers.update_in_period],
##   [method BustleCareers.window_period], [method BustleCareers.reset_window]);[br]
## - a stolen item traced after it's sold on ([method BustleCrimeWatch.deed_of_item],
##   [method BustleCrimeWatch.stolen_goods_held_by]);[br]
## - work with a capacity minimum, refused and then released
##   ([member BustleWorkType.min_capacities], [method BustleJobBoard.refusal],
##   [method BustleJobBoard.release_unfit]);[br]
## - a bystander fetching a healer, moved by the shared fetch-help rule ([BustleFetchHealer],
##   [BustleFetchHealerAction], [method BustleFetchHelpAction.approach]).[br]
## Each logs [code]hook[/code] entries on the run's timeline, with the hook's name in
## [code]"hook"[/code].

const DemoRooms := preload("res://demo/environment/demo_rooms.gd")

## The timeline kind of every entry this logs.
const KIND := &"hook"
const DAY := 1440
## The demo's cap on aspiration points.
const ASPIRATION_CAP := 12
## The career scene: days 0 to 2 are a busy period, and the job is closed on weekdays 3 and 4.
const CAREER := &"house_work"
const BUSY := &"busy"
const BUSY_DAYS := 3
const CLOSED_WEEKDAYS: Array[int] = [3, 4]
## The theft scene: an item taken from resident A by a passer-by, then sold on to resident B.
const ITEM := &"lamp"
const THIEF := &"passer_by"
const THEFT_AT := DAY + 720
const SOLD_AT := DAY + 900
## The capacity scene: work that needs moving at 0.5 or more.
const WORK := &"carry"
const POSTED_AT := 2 * DAY + 840
const STRAINED_AT := 2 * DAY + 900
## The healer scene: resident B is downed, resident A fetches the healer 40 m away.
const HEALER := &"neighbour"
const HEALER_ROLE := &"healer"
const DOWNED_AT := 4 * DAY + 960
const RECOVERED_AT := 4 * DAY + 1140
const WALK_PER_STEP := 10.0


## A health port for the side scenes: capacities and who is downed, set by the scenes.
class DemoHealthPort extends BustleHealthPort:
	var capacities: Dictionary = {}
	var downed: Array[StringName] = []

	func capacity(id: StringName, name: StringName) -> float:
		return float(capacities.get(id, {}).get(name, 1.0))

	func is_incapacitated(id: StringName) -> bool:
		return downed.has(id)


var careers: BustleCareers
var watch: BustleCrimeWatch
var board: BustleJobBoard
var fetch: BustleFetchHealer
var rooms := BustleEnvironmentPort.new()
var _run: WeakRef
var _a: StringName
var _b: StringName
var _home: StringName
var _roster: BustleScheduleRoster
var _crime: BustleCrime
var _health := DemoHealthPort.new()
var _fetch_action: BustleFetchHealerAction
var _at: Dictionary = {}
var _attended_day: int = -1
var _walked: int = 0


## Attaches the opt-in to [param run], a demo harness, before its agents are added: caps
## aspiration points (with aspirations on), installs the demo rooms, and sets up the side scenes for
## residents [param a] and [param b] at home in [param home], whose work follows [param routine].
## Returns the attached opt-in. The run keeps it (as its [code]new_hooks[/code] metadata), and it
## reaches back to the run only through a weak reference.
static func attach(run: RefCounted, a: StringName, b: StringName, home: StringName,
		routine: BustleScheduleDef) -> RefCounted:
	var hooks: RefCounted = (load("res://demo/hooks/demo_hooks.gd") as GDScript).new()
	hooks._setup(run, a, b, home, routine)
	run.set_meta(&"new_hooks", hooks)
	return hooks


func _setup(run: RefCounted, a: StringName, b: StringName, home: StringName, routine: BustleScheduleDef) -> void:
	_run = weakref(run)
	_a = a
	_b = b
	_home = home
	if run.aspiration_config != null:
		var capped: BustleAspirationConfig = run.aspiration_config.duplicate()
		capped.max_points = ASPIRATION_CAP
		run.aspiration_config = capped
	DemoRooms.install(rooms)
	run.enable_environment(rooms)
	_setup_career(routine)
	_setup_crime(run.world_seed)
	_setup_health()
	run.agent_hooks.append(_on_agent)


func _setup_career(routine: BustleScheduleDef) -> void:
	var closed := routine.duplicate(true) as BustleScheduleDef
	for weekday: int in CLOSED_WEEKDAYS:
		closed.weekdays[weekday] = BustleScheduleDay.new()
	var table := BustleRoleTable.new()
	table.holders = {&"house_hand": _a}
	var jobs := BustleRoleSchedules.new()
	jobs.schedules = {&"house_hand": closed}
	_roster = BustleScheduleRoster.new(BustleRolesPort.new(table), jobs)
	_roster.add_agent(_a)
	var busy := BustleCareerPeriod.new()
	busy.review_days = 2
	var hand := BustleCareerRank.new()
	hand.id = &"hand"
	hand.review_days = 3
	hand.periods = {BUSY: busy}
	var def := BustleCareerDef.new()
	def.id = CAREER
	def.role = &"house_hand"
	def.activity = &"work"
	def.ranks = [hand]
	careers = BustleCareers.new([def] as Array[BustleCareerDef], _roster)
	careers.assign(_a, CAREER, &"hand", 0)
	careers.reviewed.connect(_on_reviewed)


func _setup_crime(seed: int) -> void:
	var society := BustleSociety.new(seed)
	society.register_archetype(&"resident", BustleGoalLibrary.new())
	for id: StringName in [_a, _b]:
		society.add_agent(id, &"resident").area = _home
	society.ports.property.register(ITEM, _a, _home)
	_crime = BustleCrime.new(society)
	watch = BustleCrimeWatch.new(_crime)


func _setup_health() -> void:
	var ports := BustlePorts.new()
	ports.health = _health
	ports.roles.set_holder(HEALER_ROLE, HEALER)
	var carry := BustleWorkType.new()
	carry.id = WORK
	carry.minutes = 60
	carry.min_capacities = {&"moving": 0.5}
	board = BustleJobBoard.new([carry] as Array[BustleWorkType], ports)
	fetch = BustleFetchHealer.new(BustleHealthBehaviour.new(null, ports), [HEALER_ROLE] as Array[StringName])
	fetch.where = _where
	fetch.errand_started.connect(_on_errand_started)
	fetch.summoned.connect(_on_summoned)
	_fetch_action = BustleFetchHealerAction.new(fetch)
	_at = {_a: Vector3.ZERO, _b: Vector3(1, 0, 0), HEALER: Vector3(40, 0, 0)}


# The run's agent hook: rooms for each resident, then the side scenes once a step (on resident A).
func _on_agent(id: StringName, _senses: BustleSenses) -> void:
	var run: RefCounted = _run.get_ref()
	var room := DemoRooms.HOUSE_ROOM if run.area_of(id) == _home and not run.is_away(id) else &""
	if rooms.room_of(id) != room:
		rooms.set_room(id, room)
		_log(id, "room", {"room": String(room), "indoors": int(rooms.is_indoors(id)),
			"beauty": roundi(rooms.scores(room).get(&"beauty", -0.01) * 100.0)})
	if id != _a:
		return
	var now: int = run.now
	_career_step(run, now)
	_theft_step(now)
	_capacity_step(now)
	_healer_step(now)


func _career_step(run: RefCounted, now: int) -> void:
	var day := now / DAY
	if run.is_away(_a) and _attended_day != day:
		_attended_day = day
		_roster.schedule_of(_a).attend(now, &"work")
	if now == 0 or now % DAY != 0:
		return
	if day == 5:
		_log(_a, "reset_window", {"ok": int(careers.reset_window(_a)), "period": String(careers.window_period(_a))})
	careers.update_in_period(_a, now, BUSY if day <= BUSY_DAYS else &"", run.mood_of(_a))
	_log(_a, "window_period", {"day": day, "period": String(careers.window_period(_a))})


func _theft_step(now: int) -> void:
	var property := _crime.society.ports.property
	if now == THEFT_AT:
		_crime.record_theft(THIEF, _a, ITEM, {"place": &"lane", "at": now})
		property.transfer(ITEM, _a, THIEF)
		_log(_a, "theft", {"item": String(ITEM), "deed": int(watch.deed_of_item(ITEM).get("deed", false))})
	elif now == SOLD_AT:
		property.transfer(ITEM, THIEF, _b)
		_log(_b, "deed_of_item", {"item": String(ITEM), "deed": int(watch.deed_of_item(ITEM).get("id", 0)),
			"stolen_goods_of_thief": watch.stolen_goods_of(THIEF).size(),
			"stolen_goods_held_by": watch.stolen_goods_held_by(_b).size()})


func _capacity_step(now: int) -> void:
	if now == POSTED_AT:
		_health.capacities[_b] = {&"moving": 0.3}
		var job := board.post(WORK, _home, now)
		_log(_b, "refusal", {"job": String(job), "reason": String(board.refusal(BustleJobSeeker.new(_b), job))})
		_log(_a, "claim", {"job": String(job), "ok": int(board.claim(BustleJobSeeker.new(_a), job, now))})
	elif now == STRAINED_AT:
		_health.capacities[_a] = {&"moving": 0.2}
		_log(_a, "release_unfit", {"released": board.release_unfit().size()})


func _healer_step(now: int) -> void:
	if now == DOWNED_AT:
		_health.downed = [_b]
		fetch.notice(_a, _b, now)
	elif now == RECOVERED_AT:
		_health.downed = []
		_log(_b, "recovered", {"summons": String(fetch.summoned_to(HEALER))})
	if fetch.errand_of(_a).is_empty():
		return
	var context := BustleActionContext.new()
	context.agent_id = _a
	context.now_minutes = now
	if _fetch_action.tick(context, 1.0) == BustleActionHandler.Status.RUNNING:
		# The host moves the bystander toward where the fetch-help rule asked.
		_at[_a] = (_at[_a] as Vector3).move_toward(context.output["move_to"], WALK_PER_STEP)
		_walked += 1


func _on_reviewed(id: StringName, _career: StringName, _performance: float, outcome: StringName, at: int) -> void:
	_log(id, "career_review", {"outcome": String(outcome), "at": at})


func _on_errand_started(bystander: StringName, patient: StringName, healer: StringName) -> void:
	_log(bystander, "fetch_healer", {"patient": String(patient), "healer": String(healer)})


func _on_summoned(healer: StringName, patient: StringName) -> void:
	_log(healer, "summoned", {"patient": String(patient), "steps": _walked})


func _where(id: StringName) -> Variant:
	return _at.get(id)


func _log(agent: StringName, hook: String, payload: Dictionary) -> void:
	var run: RefCounted = _run.get_ref()
	payload["hook"] = hook
	run.timeline.add(run.now, agent, KIND, payload)
