# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree

## The population bench with the 1.1 load (opt-in; [code]tools/perf_bench.sh --load 1.1[/code]).
## It's the same town, run, budgets and summary line as bench/population_bench.gd, with
## [code], 1.1 load[/code] after the game minutes, so the performance gate reads it and the two runs
## line up. On top, the hooks added after 1.0 are called the way a host would, each time an agent
## thinks (through the rings' senses provider), so their cost lands in each ring's timings:
## [br]- the agent's ambitions: [code]learn_trade[/code] and [code]open_business[/code] on, the trade
##   filler ([BustleTradeTargets]) and [method BustleAmbitions.update]; the ambition's boost is the
##   brain's [member BustleBrain.score_boost];
## [br]- aspiration points under a cap ([member BustleAspirationConfig.max_points]);
## [br]- a career reviewed by period ([method BustleCareers.update_in_period],
##   [method BustleCareers.window_period]);
## [br]- the crime trace ([method BustleCrimeWatch.deed_of_item],
##   [method BustleCrimeWatch.stolen_goods_held_by]) over thefts passed on;
## [br]- the job board's capacity refusal ([method BustleJobBoard.refusal]), and
##   [method BustleJobBoard.release_unfit] once a game minute;
## [br]- the three health goals (seeking care, resting when sick, fetching a healer) in every
##   brain's library, with their inputs filled.
## [br]The save size adds these modules' saves to the society's. Every number is fixed by the seed
## and the agent: no rolls. Nobody is ill, downed or in need of care, so the health goals are
## scored but never chosen. Agents whose moving capacity is 0.3 are refused the hauling work.
##   godot --headless --path . -s res://bench/population_1_1_bench.gd [-- --full=40 --light=40 --offscreen=200 --frames=7200 --days=1 --seed=1]

const Population := preload("res://bench/population_bench.gd")
## The label in the summary line.
const LABEL := "1.1 load"
## The aspiration cap the load sets.
const ASPIRATION_CAP := 20
## Jobs posted on the board.
const JOBS := 20

var _full := 40
var _light := 40
var _offscreen := 200
var _frames := 7200
var _days := 1
var _seed := 1


## A health port where everyone is well, and one agent in five can barely move (capacity 0.3).
class LoadHealth extends BustleHealthPort:
	var world_seed := 1

	func capacity(id: StringName, name: StringName) -> float:
		return 0.3 if name == &"moving" and posmod(BustleBrain.seed_for(world_seed, id), 5) == 0 else 1.0


## The 1.1 hooks for one town, called from the rings' senses provider.
class Load extends RefCounted:
	var world_seed := 1
	var society: BustleSociety
	var personalities: Dictionary = {}
	var ambitions: Dictionary = {}
	var aspirations: Dictionary = {}
	var items: Dictionary = {}
	var jobs: Array[StringName] = []
	var trade: BustleTradeTargets
	var careers: BustleCareers
	var watch: BustleCrimeWatch
	var board: BustleJobBoard
	var seek: BustleSeekCare
	var rest: BustleRestSick
	var fetch: BustleFetchHealer
	var _last_minute := -1

	## The agent's senses as the plain bench gives them, after the host's 1.1 calls for it.
	func senses(id: StringName, _ring: int, minute: int) -> BustleSenses:
		var senses := Population.senses_for(world_seed, id, minute)
		seek.fill_inputs(id, senses.inputs)
		rest.fill_inputs(id, senses.inputs)
		fetch.fill_inputs(id, senses.inputs)
		var ambition: BustleAmbitions = ambitions[id]
		var facts := {"can_open_business": true}
		trade.fill(id, ambition.active(), facts, personalities[id])
		ambition.update(minute, personalities[id], facts)
		(aspirations[id] as BustleAspirations).add_points(1, &"bench")
		careers.update_in_period(id, minute, &"busy" if (minute / 1440) % 2 == 0 else &"")
		careers.window_period(id)
		watch.deed_of_item(items[id])
		watch.stolen_goods_held_by(id)
		board.refusal(BustleJobSeeker.new(id), jobs[posmod(BustleBrain.seed_for(world_seed, id), jobs.size())])
		if minute != _last_minute:
			_last_minute = minute
			board.release_unfit()
		return senses

	## The 1.1 modules' saves as JSON, in bytes.
	func save_bytes() -> int:
		var state := {"careers": careers.export_state(), "crime": watch.export_state(),
			"jobs": board.export_state(), "fetch": fetch.export_state(), "ambitions": {}, "aspirations": {}}
		for id: StringName in ambitions:
			state["ambitions"][String(id)] = (ambitions[id] as BustleAmbitions).export_state()
			state["aspirations"][String(id)] = (aspirations[id] as BustleAspirations).export_state()
		return JSON.stringify(state).to_utf8_buffer().size()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1).to_int()
		match arg.get_slice("=", 0):
			"--full": _full = value
			"--light": _light = value
			"--offscreen": _offscreen = value
			"--frames": _frames = value
			"--days": _days = value
			"--seed": _seed = value
	_run.call_deferred()


func _run() -> void:
	var memory_before := OS.get_static_memory_usage()
	var town := build(_full, _light, _offscreen, _seed)
	var memory := OS.get_static_memory_usage() - memory_before
	var perf := Population.time_hour(town, _frames)
	var save := save_bytes(town)
	var stuck := Population.stuck_pass(build(_full, _light, _offscreen, _seed), _days)
	var agents := _full + _light + _offscreen
	var line := summary(perf, _seed, _frames, _days, memory, agents, save, stuck)
	print(line)
	for spell: Dictionary in stuck["spells"]:
		print("  stuck: %s" % JSON.stringify(spell, "", true))
	quit(0 if line.ends_with(": OK") else 1)


## The summary line: the population bench's, with [constant LABEL] after the game minutes. OK when
## every average and the save size are within budget and nobody was stuck, else OVER BUDGET.
static func summary(perf: Dictionary, world_seed: int, frames: int, days: int, memory: int, agents: int,
		save: int, stuck: Dictionary) -> String:
	var counts: Dictionary = perf["counts"]
	var ok: bool = perf["full_avg"] <= Population.BUDGET_FULL_MS and perf["full_p99"] <= Population.BUDGET_FULL_P99_MS \
		and perf["light_avg"] <= Population.BUDGET_LIGHT_MS and perf["off_avg"] <= Population.BUDGET_OFFSCREEN_MS \
		and save / agents <= Population.BUDGET_SAVE_BYTES and (stuck["spells"] as Array).is_empty()
	return "population bench: %d FULL, %d LIGHT, %d OFF_SCREEN, seed %d, %d frames (%d game min), %s, %d stuck days, Godot %s, build %s: FULL average %.3f ms p99 %.3f ms (budget %.1f / %.1f), LIGHT average %.3f ms p99 %.3f ms (budget %.1f), OFF_SCREEN average %.3f ms p99 %.3f ms (budget %.1f), frame average %.3f ms p99 %.3f ms, memory %.1f KiB (%.0f B an agent), save %d B an agent (budget %d), stuck spells %d, longest still %d min: %s" % [
		counts["FULL"], counts["LIGHT"], counts["OFF_SCREEN"], world_seed, frames, perf["minutes"], LABEL, days,
		Engine.get_version_info()["string"], Population._build_sha(), perf["full_avg"], perf["full_p99"],
		Population.BUDGET_FULL_MS, Population.BUDGET_FULL_P99_MS, perf["light_avg"], perf["light_p99"],
		Population.BUDGET_LIGHT_MS, perf["off_avg"], perf["off_p99"], Population.BUDGET_OFFSCREEN_MS,
		perf["frame_avg"], perf["frame_p99"], memory / 1024.0, float(memory) / agents, save / agents,
		Population.BUDGET_SAVE_BYTES, (stuck["spells"] as Array).size(), stuck["longest"], "OK" if ok else "OVER BUDGET"]


## The population bench's town ([method Population.build]) with the 1.1 load attached:
## {society, rings, town, load}.
static func build(full: int, light: int, offscreen: int, world_seed: int) -> Dictionary:
	var town := Population.build(full, light, offscreen, world_seed)
	var society: BustleSociety = town["society"]
	var load := Load.new()
	load.world_seed = world_seed
	load.society = society
	var health := LoadHealth.new()
	health.world_seed = world_seed
	society.ports.health = health
	var skill_defs: Array[BustleSkillDef] = []
	for skill: StringName in [&"cooking", &"crafts", &"farming"]:
		var def := BustleSkillDef.new()
		def.id = skill
		skill_defs.append(def)
	var skills := BustleSkills.new(skill_defs)
	society.ports.skills = skills
	var config := BustleAmbitionConfig.new()
	config.find(&"learn_trade").enabled = true
	config.find(&"open_business").enabled = true
	load.trade = BustleTradeTargets.new(skills, config)
	var capped := BustleAspirationConfig.new()
	capped.max_points = ASPIRATION_CAP
	var behaviour := BustleHealthBehaviour.new(null, society.ports)
	load.seek = BustleSeekCare.new(behaviour, [&"healer"] as Array[StringName])
	load.rest = BustleRestSick.new(behaviour, [&"sick"] as Array[StringName])
	load.rest.seek_care = load.seek
	load.fetch = BustleFetchHealer.new(behaviour, [&"healer"] as Array[StringName])
	var library := (society.get_agent(society.agent_ids()[0]) as BustleNpcState).brain.library
	library.goals.append(BustleSeekCare.goal_def())
	library.goals.append(BustleRestSick.goal_def())
	library.goals.append(BustleFetchHealer.goal_def())
	var crime := BustleCrime.new(society)
	load.watch = BustleCrimeWatch.new(crime)
	var haul := BustleWorkType.new()
	haul.id = &"haul"
	haul.minutes = 60
	haul.min_capacities = {&"moving": 0.5}
	load.board = BustleJobBoard.new([haul] as Array[BustleWorkType], society.ports)
	for job: int in JOBS:
		load.jobs.append(load.board.post(&"haul", &"square", 0))
	var table := BustleRoleTable.new()
	var schedules := BustleRoleSchedules.new()
	var defs: Array[BustleCareerDef] = []
	var routine := _routine()
	var ids := society.agent_ids()
	for i: int in ids.size():
		var id: StringName = ids[i]
		var seed := BustleBrain.seed_for(world_seed, id)
		var person := BustlePersonality.new()
		for slider: StringName in [&"curiosity", &"greed", &"diligence", &"boldness"]:
			person.set_slider(slider, float(20 + posmod(seed >> (8 * [&"curiosity", &"greed", &"diligence", &"boldness"].find(slider)), 61)))
		load.personalities[id] = person
		var ambition := BustleAmbitions.new(id, config)
		load.ambitions[id] = ambition
		load.aspirations[id] = BustleAspirations.new(id, capped)
		var state: BustleNpcState = society.get_agent(id)
		state.brain.score_boost = ambition.boost
		state.brain.runner.register(BustleSeekCare.ACTION, BustleSeekCareAction.new(load.seek))
		state.brain.runner.register(BustleRestSick.ACTION, BustleRestSickAction.new(load.rest))
		state.brain.runner.register(BustleFetchHealer.ACTION, BustleFetchHealerAction.new(load.fetch))
		for skill: StringName in [&"cooking", &"crafts", &"farming"]:
			skills.set_level(id, skill, float(posmod(seed >> [&"cooking", &"crafts", &"farming"].find(skill), 8)))
		var item := StringName("goods_%03d" % i)
		society.ports.property.register(item, id, &"far")
		load.items[id] = item
		var role := StringName("job_%03d" % i)
		table.holders[role] = id
		schedules.schedules[role] = routine
		var def := BustleCareerDef.new()
		def.id = StringName("career_%03d" % i)
		def.role = role
		def.activity = &"work"
		def.ranks = [_rank()]
		defs.append(def)
	# Every seventh agent's goods are taken unseen by the next agent and sold on to the one after.
	for i: int in range(0, ids.size() - 2, 7):
		var item: StringName = load.items[ids[i]]
		crime.record_theft(ids[i + 1], ids[i], item, {"place": &"nowhere", "at": 0})
		society.ports.property.transfer(item, ids[i], ids[i + 1])
		society.ports.property.transfer(item, ids[i + 1], ids[i + 2])
	var roster := BustleScheduleRoster.new(BustleRolesPort.new(table), schedules)
	for id: StringName in ids:
		roster.add_agent(id)
	load.careers = BustleCareers.new(defs, roster, society.ports)
	for i: int in ids.size():
		load.careers.assign(ids[i], StringName("career_%03d" % i), &"hand", 0)
	(town["rings"] as BustleSimRings).senses_provider = load.senses
	town["load"] = load
	return town


## [param town]'s save: the society's export plus the 1.1 modules', as JSON, in bytes.
static func save_bytes(town: Dictionary) -> int:
	return Population.save_bytes(town) + (town["load"] as Load).save_bytes()


# A working day of eight hours.
static func _routine() -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = &"work"
	block.start_minute = 480
	block.end_minute = 960
	var day := BustleScheduleDay.new()
	day.blocks.append(block)
	var routine := BustleScheduleDef.new()
	routine.day = day
	return routine


# A rank reviewed every 3 working days, or every 2 in a busy period.
static func _rank() -> BustleCareerRank:
	var busy := BustleCareerPeriod.new()
	busy.review_days = 2
	var rank := BustleCareerRank.new()
	rank.id = &"hand"
	rank.review_days = 3
	rank.periods = {&"busy": busy}
	return rank
