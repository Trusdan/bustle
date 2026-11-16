# Host walkthrough: clock, world and roles

This starts from an empty Godot 4.7 project and connects Bustle to three things a game always has: its own **clock**, its own **map** and its own **jobs**. It builds a village of three (a baker, a smith and a farmer), sorts them into simulation rings around the player, and gives each a routine from the role it holds. It runs headless, so it can live in a test or a tool script before any scene exists.

Every name below is real: `tests/docs/test_host_guides.gd` compiles the script in step 5 and runs it. Each port is described in full in [ports.md](ports.md).

## 1. Add the addon

Copy `addons/bustle/` into the project and enable **Bustle** under Project Settings → Plugins. Nothing else is needed: Bustle depends only on Godot. Every port starts as its standalone default, so the project already runs; the steps below replace three of them.

## 2. The clock

Bustle counts whole game minutes. Extend `BustleClockPort` and answer `now_minutes()` from the game's own time; `day_key()` names the day.

```gdscript
class HostClock:
	extends BustleClockPort

	var minutes: int = 0

	func now_minutes() -> int:
		return minutes

	func day_key() -> StringName:
		return StringName("day_%d" % floori(float(minutes) / MINUTES_PER_DAY))
```

The game moves `minutes` on; Bustle only reads it. `BustleSimRings` re-sorts when the minute changes and lets off-screen agents think once an interval of game time.

## 3. The world

Extend `BustleWorldPort` with the game's map: which area each agent is in, which areas touch, and where the player is. The rings use these to decide who is simulated in full.

```gdscript
class HostWorld:
	extends BustleWorldPort

	var areas: Dictionary[StringName, StringName] = {}
	var links: Dictionary[StringName, Array] = {}
	var player_at: StringName = &"square"

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"")

	func player_area() -> StringName:
		return player_at

	func neighbour_areas(area: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		out.assign(links.get(area, []))
		return out
```

A full game also answers `player_position()`, `is_in_view()`, `is_interior()`, the places, and makes bodies in `spawn_body()`; [ports.md](ports.md) lists them all. Here bodies are off (`BustleSimRingConfig.manage_bodies`), so the world never needs to make one.

## 4. The roles

The default `BustleRolesPort` already keeps a table, filled from a `BustleRoleTable` resource, so a game without its own job system needs no subclass. A `BustleScheduleRoster` turns roles into jobs: an agent holding a role that `BustleRoleSchedules` has a routine for follows that routine. When a holder changes (`set_holder()`), the roster swaps the routines at once.

A game that keeps its own offices extends `BustleRolesPort` instead and emits `holder_changed` when one changes hands ([ports.md](ports.md#bustlerolesport-roles)).

## 5. Putting it together

```gdscript
extends RefCounted

## A village of three on the host's own clock, map and roles.


class HostClock:
	extends BustleClockPort

	var minutes: int = 0

	func now_minutes() -> int:
		return minutes

	func day_key() -> StringName:
		return StringName("day_%d" % floori(float(minutes) / MINUTES_PER_DAY))


class HostWorld:
	extends BustleWorldPort

	var areas: Dictionary[StringName, StringName] = {}
	var links: Dictionary[StringName, Array] = {}
	var player_at: StringName = &"square"

	func area_of(id: StringName) -> StringName:
		return areas.get(id, &"")

	func player_area() -> StringName:
		return player_at

	func neighbour_areas(area: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		out.assign(links.get(area, []))
		return out


var society := BustleSociety.new()
var clock := HostClock.new()
var world := HostWorld.new()
var roster: BustleScheduleRoster
var rings: BustleSimRings


## Connects the ports, adds the agents, and makes the roster and the rings.
func setup() -> void:
	society.set_port(&"clock", clock)
	society.set_port(&"world", world)
	var table := BustleRoleTable.new()
	table.holders = {&"baker": &"ann", &"smith": &"bram"}
	society.set_port(&"roles", BustleRolesPort.new(table))

	var rest := BustleGoalDef.new()
	rest.id = &"rest"
	var library := BustleGoalLibrary.new()
	library.goals.append(rest)
	society.register_archetype(&"villager", library)
	for id: StringName in [&"ann", &"bram", &"cora"]:
		society.add_agent(id, &"villager")
	world.areas = {&"ann": &"square", &"bram": &"forge", &"cora": &"fields"}
	world.links = {&"square": [&"forge"], &"forge": [&"square"]}
	var ann := society.get_agent(&"ann")
	ann.position = Vector3(2, 0, 0)
	ann.has_position = true

	var jobs := BustleRoleSchedules.new()
	jobs.schedules = {&"baker": routine(&"bake", 360, 720), &"smith": routine(&"forge", 480, 960)}
	roster = BustleScheduleRoster.new(society.ports.roles, jobs)
	for id: StringName in society.agent_ids():
		roster.add_agent(id)

	var config := BustleSimRingConfig.new()
	config.manage_bodies = false
	rings = BustleSimRings.new(society, config)


## One routine with a single block of work.
static func routine(activity: StringName, start: int, end: int) -> BustleScheduleDef:
	var block := BustleScheduleBlock.new()
	block.activity = activity
	block.start_minute = start
	block.end_minute = end
	var def := BustleScheduleDef.new()
	def.id = activity
	def.day = BustleScheduleDay.new()
	def.day.blocks.append(block)
	return def


## The game's frame: its clock moves on, and the rings sort and think.
func step(game_minutes: int, real_seconds: float) -> void:
	clock.minutes += game_minutes
	rings.tick(real_seconds)


## Each agent's ring, job and the activity its routine has now.
func report() -> Dictionary:
	var out := {}
	for id: StringName in society.agent_ids():
		var block: Dictionary = roster.schedule_of(id).block_at(clock.now_minutes())
		out[id] = {
			"ring": BustleSimRings.Ring.keys()[rings.ring_of(id)],
			"job": roster.job_of(id),
			"doing": block["block"].activity if block.get("block") != null else &"",
		}
	return out
```

Run it from a tool script or a test:

```gdscript
extends RefCounted


func run(village: RefCounted) -> Dictionary:
	village.call(&"setup")
	for frame in 60:
		village.call(&"step", 10, 0.5)
	return village.call(&"report")
```

At 10:00 on the first day, `report()` says:

- **ann** is in the player's area near the player, so she is `FULL`. She holds `baker`, and her routine has her at `bake`.
- **bram** is next door in the forge, so he is `LIGHT`. He holds `smith` and is at `forge`.
- **cora** is out in the fields, so she is `OFF_SCREEN`. She holds no role, so she has no job and no routine.

Give the bakery to cora with `society.ports.roles.set_holder(&"baker", &"cora")`, and on the next read she has ann's job and routine, and ann has none.

## 6. Next

- Fill each agent's `BustleSenses` through `BustleSimRings.senses_provider`, so its brain has needs and options to choose from ([tutorial.md](tutorial.md) shows a brain on its own).
- Let the brain's `BustleIntent` move the agent's body. Bustle never moves anyone.
- Add modules one at a time ([modules.md](modules.md)), giving each the society's ports.
- Save the society and each module with `export_state()` ([saves.md](saves.md)).
