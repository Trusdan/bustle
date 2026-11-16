# Implementing the ports

Bustle never reaches into a game. Everything it needs from one (time, places, who holds which job, money, health and the rest) it asks through a **port**: a small class in `addons/bustle/ports/` with a safe standalone default for every method. A host replaces only the ports it has something to say about, and keeps the defaults for the rest. [host-walkthrough.md](host-walkthrough.md) connects the clock, world and roles in an empty project; this page is the reference for every port.

What each method promises comes from its `##` doc comment in the code, which the API pages in [api/](api/) are generated from. The frozen list of ports and their signatures is in [public-api/PUBLIC_API.md](public-api/PUBLIC_API.md). How Bustle answers bad input (refuse with a reason, or warn once and carry on) is in [errors.md](errors.md), and every setting a module reads is in [config.md](config.md); neither is repeated here.

## Plugging a port in

`BustleSociety.ports` is a `BustlePorts`: one of each port, all starting as the defaults. Replace one by extending its class and handing an instance to the society:

```gdscript
extends RefCounted

## A society whose clock is the host's.
class HostClock:
	extends BustleClockPort

	var minutes: int = 0

	func now_minutes() -> int:
		return minutes


func make() -> BustleSociety:
	var society := BustleSociety.new()
	var ok := society.set_port(&"clock", HostClock.new())
	assert(ok)
	return society
```

- `set_port(name, port)` takes one of `BustlePorts.NAMES`: `social`, `roles`, `world`, `clock`, `combat`, `trade`, `disposition`, `work`, `skills`, `life_stages`, `health`, `environment`, `director`, `property`. It returns false, and changes nothing, for an unknown name, a null port, or a port that isn't an instance of the current one's class. Assigning `society.ports.clock = ...` directly skips that check.
- `BustlePorts.missing()` names any port set to null. Every port should stay set; set a default rather than null.
- Modules that need a port take it when they are made (for example `BustleScheduleRoster.new(roles, jobs)`, `BustleHealthBehaviour.new(config, ports)`). Give them the society's (`society.ports.roles`, `society.ports`), so every part of Bustle reads the same answers.

## Rules for every port

- **Override with the exact signature.** Parameter names may differ, but the types, the defaults and the return type must match the method you override, or GDScript refuses the script. A port's signature never changes within a major version ([public-api/VERSIONING.md](public-api/VERSIONING.md)); a new method only ever comes with a default that keeps the old behaviour.
- **Don't reuse the parent's private names.** The defaults keep their data in members such as `_minutes`, `_places`, `_holders`, `_deeds`, `_balances`, `_rooms`, `_items` and the constant `_Warn` (on `BustleRolesPort` and `BustleCombatPort`). A subclass that declares a member with one of these names fails to load. Name yours differently.
- **Answer quickly and change nothing when asked.** Queries (`area_of`, `opinion`, `holder_of`, `capacity` and the rest) are called from the simulation, some every tick for every agent. Keep them to a lookup, and keep side effects in the methods that ask for one (`set_holder`, `pay`, `transfer`, `care`, `request_spawn`).
- **Ids are `StringName`s.** Agent, role, area, place and item ids are compared as `StringName`; an empty one means "none".
- **Save what your port keeps.** The society's save holds its agents, not its ports. The defaults that keep data (`BustleTradePort`, `BustleEnvironmentPort`, `BustlePropertyPort`) have their own `export_state()` and `import_state()` ([saves.md](saves.md)); a host port saves its data with the rest of the game.

Some methods Bustle never calls itself. They are there for the host's code and for modules a host calls directly (the "Read by" column says "the host" for those). Overriding them keeps one source of truth.

## BustleClockPort (`clock`)

The game clock, in whole game minutes. The default keeps its own count from 0, moved on with `advance()`; a day is `MINUTES_PER_DAY` (1440) minutes.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `now_minutes()` | the current game minute, `int` | its own count, from 0 | `BustleSimRings` (re-sorting, OFF_SCREEN thinking, catch-up) |
| `day_key()` | a key for today, `StringName` | `day_<n>`, counting from 0 | the host |
| `season()` | the current season, `StringName` | empty: no season | the host, passing it to `BustleSchedule.block_at()` and friends |
| `advance(minutes)` | true when moved; false and no change when negative | moves its own count | the host (the default's data) |

**Override** `now_minutes()` and `day_key()`; `season()` too when the game has seasons.

```gdscript
extends BustleClockPort

## The host's clock: a game-time node that counts minutes.
var minutes: int = 0


func now_minutes() -> int:
	return minutes


func day_key() -> StringName:
	return StringName("day_%d" % floori(float(minutes) / MINUTES_PER_DAY))
```

**Common mistakes**

- Returning real seconds or fractions. It is whole game minutes; the modules that take a `now` expect the same number.
- Letting the minute go backwards. Modules record times against it; the built-in social store warns once and keeps its clock when told an earlier time.
- A day that isn't 1440 minutes without telling the modules that count days, such as `BustleLifeStageRules.minutes_per_day` ([config.md](config.md)).
- Jumping the clock far ahead and expecting every missed hour to be thought: off-screen agents are caught up only within `BustleSimRingConfig.catch_up_cap_game_days`, and the rest is summarised.

## BustleWorldPort (`world`)

Where agents and places are, how areas connect, and how bodies are made. The default is one area, `DEFAULT_AREA` (`&"default"`), with everyone in it, places set with `set_place()`, no travel time and no bodies, so it is headless only.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `area_of(id)` | the area agent `id` is in | `DEFAULT_AREA` | `BustleSimRings`, `BustleDirectorEffects` |
| `player_area()` | the player's area | `DEFAULT_AREA` | `BustleSimRings` |
| `player_position()` | the player's position, `Vector3` | the origin | `BustleSimRings` |
| `is_in_view(position)` | true when the player could see it now | false | `BustleSimRings` (no pop-in) |
| `is_interior(area)` | true for a building or cave seen whole | false | `BustleSimRings` |
| `neighbour_areas(area)` | the areas next to it, `Array[StringName]` | none | `BustleSimRings`, `BustleMentalBehaviour` |
| `has_place(place)` | true when it has a known position | from `set_place()` | the host |
| `place_position(place)` | its position; the origin when unknown | from `set_place()` | `BustleSociety` (locks), `BustleCrimeWatch`, `BustleMentalBehaviour` |
| `set_place(place, position)` | nothing; empty names and non-finite positions are ignored | stores it | the host (the default's data) |
| `path_between(a, b)` | the areas from `a` to `b`, both included | `[a]`, `[a, b]`, or empty when either is empty | the host |
| `travel_minutes(a, b)` | game minutes from area `a` to `b` | 0 | the host |
| `spawn_body(id, xf)` | the new body, `Node3D` | null: no bodies | `BustleSimRings` (with `manage_bodies`) |
| `free_body(id)` | nothing | nothing | `BustleSimRings` (with `manage_bodies`) |
| `request_spawn(kind, area, count, event)` | true when the host brought them in | false | `BustleDirectorEffects` |

**Override** every method you have an answer for; the class doc asks a host to override them all. `BustleCrimeWatch` and `BustleMentalBehaviour` look an agent's area up as a place (`place_position(area)`), so give every area a place of the same name.

```gdscript
extends BustleWorldPort

## The host's map: which area each agent is in, which areas touch, and where places are.
var areas: Dictionary[StringName, StringName] = {}
var links: Dictionary[StringName, Array] = {}
var spots: Dictionary[StringName, Vector3] = {}
var player_at: StringName = &"square"


func area_of(id: StringName) -> StringName:
	return areas.get(id, &"")


func player_area() -> StringName:
	return player_at


func neighbour_areas(area: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(links.get(area, []))
	return out


func has_place(place: StringName) -> bool:
	return spots.has(place)


func place_position(place: StringName) -> Vector3:
	return spots.get(place, Vector3.ZERO)
```

**Common mistakes**

- Keeping the default's `spawn_body()` with `BustleSimRingConfig.manage_bodies` on: it returns null, so nobody ever appears. Return a body, or turn `manage_bodies` off and place bodies yourself.
- Calling `place_position()` without `has_place()`: an unknown place answers the origin.
- Moving an agent to another area without telling the rings: call `BustleSimRings.request_sort()`, or the change waits for the next re-sort.
- Creating agents or things in `request_spawn()` behind Bustle's back is fine (the host decides), but return false when nothing came, so the director knows.

## BustleRolesPort (`roles`)

Who holds which role, a job or an office; what a role means is the host's business. The default is a table read from a `BustleRoleTable` resource (`holders`: role → id) if one is given, changed with `set_holder()`.

| Member | Returns | Default | Read by |
| --- | --- | --- | --- |
| `holder_of(role)` | who holds it, or empty | from the table | `BustleCrimeWatch`, `BustleWitnessJudge`, `BustleLifeStages` |
| `roles_of(id)` | the roles `id` holds, sorted, `PackedStringArray` | from the table | `BustleScheduleRoster`, `BustleJobBoard`, `BustleLifeStages` |
| `set_holder(role, id)` | nothing; an empty `id` vacates the role, an empty role warns once and is ignored | changes the table and emits `holder_changed` | `BustleLifeStages` (a death vacates the roles) |
| signal `holder_changed(role, old, new)` | | emitted by `set_holder()` when anything changed | `BustleScheduleRoster`, `BustleCareers` |

**Override** `holder_of()` and `roles_of()`, and **emit `holder_changed`** whenever a holder changes in your game. Override `set_holder()` too if Bustle should be able to change holders (a death in `BustleLifeStages` vacates roles through it); then re-read in `holder_of()` what you were given. `BustleWyrdRolesPort` in the optional bridge is a ready implementation over Wyrd ([wyrd-bridge.md](wyrd-bridge.md)).

```gdscript
extends BustleRolesPort

## The host's offices: role → holder, kept by the game.
var offices: Dictionary[StringName, StringName] = {}


func holder_of(role: StringName) -> StringName:
	return offices.get(role, &"")


func roles_of(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for role: StringName in offices:
		if id != &"" and offices[role] == id:
			out.append(String(role))
	out.sort()
	return out


func set_holder(role: StringName, id: StringName) -> void:
	var old := holder_of(role)
	if role == &"" or old == id:
		return
	offices[role] = id
	holder_changed.emit(role, old, id)
```

**Common mistakes**

- Not emitting `holder_changed`. A schedule roster then keeps the old holder's routine, and careers miss the change.
- Returning `roles_of()` unsorted. The roster takes an agent's job as the first role, in sorted order, that has a routine.
- Using the default without a table and expecting holders: `BustleRolesPort.new()` holds nothing until `set_holder()` is called.

## BustleSocialPort (`social`)

How agents feel about each other and what they know of each other's deeds. The default has no opinions (everyone is `NEUTRAL_OPINION`, 50) and no relationship kinds, and keeps a small list of deeds that spreads one hop only. `BustleSocialStore` is the built-in store with opinions, reasons and kinds ([social.md](social.md)); `BustleWyrdSocialPort` answers through Wyrd.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `opinion(a, b)` | how `a` regards `b`, 0 to 100, `int` | 50 | `BustleConversation`, `BustleRomance`, `BustleAmbitionTargets`, `BustleMentalBehaviour`, `BustleWitnessJudge` |
| `kinds_between(a, b)` | the kinds from `a` to `b`, `PackedStringArray` | none | the same, and `BustleComfort` |
| `supports_kinds()` | true when it keeps kinds written with `set_kind()` | false | `BustleRomance` |
| `set_kind(a, b, kind)` / `clear_kind(a, b, kind)` | nothing; one way, `a` towards `b` | nothing | `BustleRomance` |
| `reasons(a, b, max = 3)` | up to `max` reasons, `Array[Dictionary]` | none | `BustleConflict` |
| `record_deed(actor, verb, target, place, witnesses, magnitude = 1.0, return_magnitude = 0.0)` | the deed's key, or empty when the actor or verb is empty | keeps it; the actor and witnesses with an `id` know it | `BustleSocialInteractions`, `BustleAmbitions` |
| `knows(agent, key)` | true when the agent knows the deed | from its list | the host |
| `share_news(teller, listener, place)` | how many deeds were told | first-hand deeds only, one hop | the host |

**Override** every method you have a source for. A port that keeps relationship kinds overrides `supports_kinds()` to return true, with `set_kind()` and `clear_kind()`; romance changes no kinds otherwise.

```gdscript
extends BustleSocialPort

## Opinions from the host's reputation table: "a>b" → 0 to 100.
var regard: Dictionary[String, int] = {}


func opinion(a: StringName, b: StringName) -> int:
	return clampi(regard.get("%s>%s" % [a, b], NEUTRAL_OPINION), 0, 100)
```

**Common mistakes**

- Returning an opinion outside 0 to 100, or on another scale. Every line Bustle compares it with (romance, ambitions, relationships, [config.md](config.md)) is on 0 to 100 with 50 neutral.
- Treating kinds as two-way. `set_kind(a, b, kind)` gives `a` the kind towards `b` only; romance's family links call it once in each direction.
- Returning true from `supports_kinds()` while `set_kind()` does nothing: romance then believes a courtship was recorded.

## BustleCombatPort (`combat`)

Fighting, handed to the host. Every fight has an intent, `subdue` (the default) or `kill`. The default resolves at once and harmlessly: the fighter is `RESOLVED` with nobody killed or downed.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `engage(id, target, intent = &"subdue")` | nothing; engaging again changes the intent; empty or equal ids warn once and are ignored | resolves at once | `BustleFightAction` |
| `disengage(id)` | nothing | forgets the fight | `BustleFightAction`, `BustleConflict` |
| `status(id)` | `Status.NONE`, `ENGAGED` or `RESOLVED` | `RESOLVED` after `engage()`, else `NONE` | `BustleFightAction` |
| `outcome(id)` | once `RESOLVED`: `{target, intent, killed, downed}`; empty before | nobody killed or downed | `BustleConflict` |

**Override** all four to drive your own combat: report `ENGAGED` while the fight runs and `RESOLVED` with an outcome when it ends. Pass a subdue fight's immediate damage through `BustleConflict.filter_damage()` ([conflict.md](conflict.md)).

```gdscript
extends BustleCombatPort

## Fights the host's combat system runs: id → {target, intent}, and the results it reports.
var running: Dictionary[StringName, Dictionary] = {}
var results: Dictionary[StringName, Dictionary] = {}


func engage(id: StringName, target: StringName, intent: StringName = &"subdue") -> void:
	if id != &"" and target != &"" and id != target:
		running[id] = {"target": target, "intent": intent}


func disengage(id: StringName) -> void:
	running.erase(id)
	results.erase(id)


func status(id: StringName) -> Status:
	if results.has(id):
		return Status.RESOLVED
	return Status.ENGAGED if running.has(id) else Status.NONE


func outcome(id: StringName) -> Dictionary:
	return results.get(id, {}).duplicate()
```

**Common mistakes**

- Returning an outcome before the fight is `RESOLVED`; it should be empty until then.
- Reporting a death only elsewhere. Conflict learns that a target died from `killed` in the outcome (a missing `killed` reads as false), and emits its `killed` signal from that.

## BustleTradePort (`trade`)

Money and buying in one abstract unit, whole numbers; what the unit is, and any currencies behind it, is the host's business. The default keeps balances in memory and a `prices` list (item → price), and never creates or loses money.

| Member | Returns | Default | Read by |
| --- | --- | --- | --- |
| `balance(id)` | what `id` has, `int` | its own balances, 0 when unknown | `BustleAffordance` |
| `pay(from, to, amount)` | true when paid; false, changing nothing, for an amount that isn't positive, an empty or equal id, or too little money | moves it | `BustleAffordance`, `BustleScheduleRoster` (wages), `BustleJobBoard` |
| `price_of(item, seller)` | the price, or -1 when it isn't sold | `prices`, -1 when unlisted | its own `can_buy()` |
| `can_buy(id, item, seller)` | true when `buy()` would go through; changes nothing | sold, two different named agents, can pay | `BustleAffordance` |
| `buy(id, item, seller)` | true when bought; false, changing nothing, otherwise | pays the price | `BustleAffordance` |
| `can_take(id, item)` / `take(id, item)` | an owner using its own stock, without paying | any named agent may | `BustleAffordance` |
| `set_balance(id, amount)`, `prices`, `export_state()`, `import_state(saved)` | the default's data and its save | | the host |

**Override** `balance()` and `pay()` to use your own wallets, `can_buy()` and `buy()` **together** for your shops, and `can_take()` and `take()` **together** for stock.

```gdscript
extends BustleTradePort

## The host's wallets: id → coins.
var wallets: Dictionary[StringName, int] = {}


func balance(id: StringName) -> int:
	return wallets.get(id, 0)


func pay(from: StringName, to: StringName, amount: int) -> bool:
	if amount <= 0 or from == &"" or to == &"" or from == to or balance(from) < amount:
		return false
	wallets[from] = balance(from) - amount
	wallets[to] = balance(to) + amount
	return true
```

**Common mistakes**

- Overriding `buy()` without `can_buy()` (or `take()` without `can_take()`). Bustle offers an item when `can_buy()` says yes, so the two must agree.
- A `pay()` that succeeds partly or changes a balance before failing. It moves the whole amount or nothing.
- Overriding `balance()` but not `pay()`, so payments land in the default's private balances.

## BustleDispositionPort (`disposition`)

How one actor regards another: `Disposition.HOSTILE`, `NEUTRAL` or `FRIENDLY`. The default reads its `table`, a `BustleDispositionTable`, if one is given, and is neutral otherwise.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `disposition(a_id, a_group, b_id, b_group)` | how `a` regards `b` | `table.lookup(...)`, or `NEUTRAL` with no table | `BustleConflict`, `BustlePerceptionWorld` |

**Override** `disposition()` to plug in factions or reputation, or give the default a table.

```gdscript
extends BustleDispositionPort

## Groups at war with each other.
var enemies: Dictionary[StringName, StringName] = {&"bandits": &"village", &"village": &"bandits"}


func disposition(_a_id: StringName, a_group: StringName, _b_id: StringName, b_group: StringName) -> Disposition:
	if enemies.get(a_group, &"") == b_group:
		return Disposition.HOSTILE
	return Disposition.FRIENDLY if a_group == b_group and a_group != &"" else Disposition.NEUTRAL
```

**Common mistakes**

- Assuming it is symmetric. Conflict asks both how an agent regards another and how the other regards it.
- Forgetting agents' groups: the group comes from `BustleNpcState.group` (set in `add_agent()`), or from conflict's `group_of` hook.

## BustleWorkPort (`work`)

Jobs. The default has none unless it is given a `BustleScheduleRoster` (jobs as roles with routines, [schedules.md](schedules.md)) and, for posted one-off work, a `BustleJobBoard` ([work.md](work.md)).

| Member | Returns | Default | Read by |
| --- | --- | --- | --- |
| `roster` | the roster, or null | from `_init(roster, board)` | |
| `board` | the job board, or null | from `_init(roster, board)` | |
| `job_of(id)` | the job `id` has, or empty | `roster.job_of(id)`, empty with no roster | `BustleCareers` |
| `can_do(id, job, tags = [])` | true when `id` passes the gates of posting `job` | the board's gates; false with no board | the host |
| `claimed_of(id)` | the posting `id` has claimed, or empty | the board's claim | `BustleLifeStages` (a death releases it) |

**Override** `job_of()` when jobs live in your game rather than in a roster; most hosts give the default a roster and a board instead.

```gdscript
extends BustleWorkPort

## Jobs kept by the host: id → job.
var jobs: Dictionary[StringName, StringName] = {}


func job_of(id: StringName) -> StringName:
	return jobs.get(id, &"")
```

**Common mistakes**

- Expecting a job from `BustleWorkPort.new()` alone: with no roster it has none.
- Giving the work port a different roster or roles port than the society's, so `job_of()` and the schedules disagree.

## BustleSkillSet (`skills`)

Skill levels. The default makes everyone equally skilled (0). The skills module, `BustleSkills`, is a ready skill set with XP, levels and passions ([skills.md](skills.md)).

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `level(id, skill)` | `id`'s level in `skill`, `float` | 0.0 | `BustleCareers`, `BustleJobBoard` |

**Override** `level()`, or use `BustleSkills`.

```gdscript
extends BustleSkillSet

## Levels the host's character sheets keep: id → skill → level.
var sheets: Dictionary[StringName, Dictionary] = {}


func level(id: StringName, skill: StringName) -> float:
	return float(sheets.get(id, {}).get(skill, 0.0))
```

**Common mistakes**

- Levels on another scale than the skill definitions and work types use (`BustleSkillDef.max_level`, `BustleWorkType.min_skill`, [config.md](config.md)).

## BustleLifeStagePort (`life_stages`)

Life stages (child, adult and so on, as the host defines them). The default is ageless: no stage, and everything allowed. `BustleLifeStages` is the module that ages agents on the clock ([life_stages.md](life_stages.md)).

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `stage_of(id)` | the stage, or empty | empty | `BustleBrain` |
| `allows_goal(id, tags)` | whether the stage lets `id` choose a goal with any of `tags` (its id and tags) | true | `BustleBrain` |
| `allows_affordance(id, tags)` | whether the stage lets `id` use an option with any of `tags` | true | `BustleBrain` |

**Override** all three from your own stages, or use `BustleLifeStages`.

```gdscript
extends BustleLifeStagePort

## Children don't work or fight.
var children: Dictionary[StringName, bool] = {}


func stage_of(id: StringName) -> StringName:
	return &"child" if children.has(id) else &"adult"


func allows_goal(id: StringName, tags: Array[StringName]) -> bool:
	return not (children.has(id) and (tags.has(&"work") or tags.has(&"fight")))
```

**Common mistakes**

- Answering false for an empty tag list. A goal with no tags still has its id in `tags`; refuse only what you mean to.

## BustleHealthPort (`health`)

Health, owned by the host: damage, illness and medicine. Bustle keeps none of its own; the health module, `BustleHealthBehaviour`, reacts to what this port says ([health.md](health.md)). The default says everyone is healthy.

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `is_injured(id)` | true when hurt | false | the host |
| `is_incapacitated(id)` | true when it can't act at all | false | `BustleHealthBehaviour`, `BustleCrime`, `BustleCrimeWatch` |
| `is_life_threatened(id)` | true when its life is in danger now | false | `BustleConflict` |
| `capacity(id, name)` | 1 full to 0 none; names are the host's, such as `moving` | 1.0 | `BustleHealthBehaviour` |
| `pain(id)` | 0 none to 1 | 0.0 | `BustleHealthBehaviour` |
| `needs_care(id)` | 0 not at all to 1 | 0.0 | `BustleHealthBehaviour`, `BustleTendJob` |
| `is_contagious(id)` | true when it can pass an illness on | false | `BustleHealthBehaviour` |
| `visible_tags(id)` | what others can see, such as `sick`, `Array[StringName]` | none | `BustleHealthBehaviour` |
| `care(healer, patient)` | true when the host did the treatment | false | `BustleTendJob` |

**Override** whichever readings your game has; each default means "healthy". Override `care()` to let the tend job ask for treatment.

```gdscript
extends BustleHealthPort

## Wounds the host tracks: id → 0 (none) to 1 (gravely hurt).
var wounds: Dictionary[StringName, float] = {}


func is_injured(id: StringName) -> bool:
	return wounds.get(id, 0.0) > 0.0


func capacity(id: StringName, name: StringName) -> float:
	return clampf(1.0 - wounds.get(id, 0.0), 0.0, 1.0) if name == &"moving" else 1.0


func pain(id: StringName) -> float:
	return clampf(wounds.get(id, 0.0), 0.0, 1.0)
```

**Common mistakes**

- Readings outside 0 to 1. Capacities, pain and care urgency are fractions.
- Capacity names that the health config doesn't use: `BustleHealthEffect.capacity` names the capacities the module reads, so they must match yours ([config.md](config.md)).
- Treating in `needs_care()`. It only reports; `care()` is the one call that asks the host to act.

## BustleEnvironmentPort (`environment`)

Rooms and surroundings. The host computes its rooms and their scores; Bustle never detects rooms. Either extend it or fill the built-in store with `set_room()` and `set_scores()`. The default has no rooms. An agent in a room is indoors, and one in no room outdoors.

| Member | Returns | Default | Read by |
| --- | --- | --- | --- |
| `room_of(id)` | the room `id` is in, or empty | the store | `BustleRoomThoughts` |
| `scores(room)` | `beauty`, `comfort`, `cleanliness`, `impressiveness` (`SCORES`), each 0 to 1; a missing score is unset | the store | `BustleRoomThoughts` |
| `is_indoors(id)` | true while indoors | in a room | `conditions()` |
| `conditions(id)` | `[INDOORS]` or `[OUTDOORS]`, for `BustleNeedSet.advance()` | from `is_indoors()` | the host, through `conditions_of()` |
| `conditions_of(port, id)` (static) | the port's conditions, or none for a null port | | the host |
| `set_room()`, `set_scores()`, `export_state()`, `import_state()` | the built-in store and its save | | the host |

**Override** `room_of()` and `scores()` (and `is_indoors()` for a roofless room), or fill the store.

```gdscript
extends BustleEnvironmentPort

## Rooms from the host's building system.
var occupants: Dictionary[StringName, StringName] = {}
var rated: Dictionary[StringName, Dictionary] = {}


func room_of(id: StringName) -> StringName:
	return occupants.get(id, &"")


func scores(room: StringName) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	out.assign(rated.get(room, {}))
	return out
```

**Common mistakes**

- Scoring a missing value as 0. Leave it out: 0 is a real, bad score, while a missing one is unset.
- Expecting needs to change indoors without passing the conditions on: `BustleNeedSet.advance()` only sees the conditions it is given.

## BustleDirectorPort (`director`)

A storyteller that paces events. The default allows everything; the director module, `BustleDirector`, asks it before firing an event ([director.md](director.md)).

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `allows(event_kind)` | true when an event of that kind may happen now | true | `BustleDirector` |

**Override** `allows()` to veto events, for example during a cutscene.

```gdscript
extends BustleDirectorPort

## No events while the host shows a cutscene.
var in_cutscene: bool = false


func allows(_event_kind: StringName) -> bool:
	return not in_cutscene
```

**Common mistakes**

- Using it to schedule events. It only vetoes; the director chooses.

## BustlePropertyPort (`property`)

Who owns which things, and where they are. The default keeps an in-memory register of plain records, `{id, owner_id, place, relieves, protected}`. Only the host makes items (`register()`) or uses them up (`remove()`); theft only moves an item to a new owner ([crime.md](crime.md)).

| Method | Returns | Default | Read by |
| --- | --- | --- | --- |
| `register(id, owner_id, place, relieves = {}, protected = false)` | true when registered; false, changing nothing, for an empty or taken id, no owner, or a bad `relieves` | adds the record | the host |
| `item(id)` | a copy of the record, or empty | | the host |
| `owner_of(id)` | the owner, or empty | | `BustleCrimeWatch` |
| `items_at(place)` / `items_of(owner_id)` | the records there or owned, by id | | `BustleCrime` |
| `is_protected(id)` / `set_protected(id, protected)` | whether it can never be taken / false when unknown | | the host |
| `transfer(id, from, to)` | true when moved; false, changing nothing, for an unknown, protected or not-owned item, or a bad `to` | changes the owner only | `BustleCrime` |
| `remove(id)` | true when it was there | | the host |
| `export_state()`, `import_state(saved)` | the register and its save | | the host |

**Override** the queries and `transfer()` to use your own inventory, or register your items with the default.

```gdscript
extends BustlePropertyPort

## Owners from the host's inventory: item → owner.
var owners: Dictionary[StringName, StringName] = {}


func owner_of(id: StringName) -> StringName:
	return owners.get(id, &"")


func transfer(id: StringName, from: StringName, to: StringName) -> bool:
	if owner_of(id) != from or to == &"" or to == from or is_protected(id):
		return false
	owners[id] = to
	return true
```

**Common mistakes**

- A `transfer()` that also moves the item. Only the owner changes; the item stays at its place until the host moves it.
- Forgetting to protect things a story needs. Protected items can never be taken.
- Mixing: if you override `owner_of()` and `transfer()`, override `items_at()` and `items_of()` too, or crime looks at the default's empty register.

## BustlePorts and BustleRoleTable

`BustlePorts` is the holder above, not a port: it has one member per port and `missing()`. `BustleRoleTable` is the resource the default roles port reads its first holders from (`holders`: role → id). Neither is extended by a host.
