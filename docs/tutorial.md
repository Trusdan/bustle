# Tutorial: a small demo from scratch

This builds a one-person household from nothing but the addon: a cook who gets hungry and tired, a stove and a bed, a brain that chooses between them, and then one optional module, a mood. It runs headless in a few dozen lines. At the end it points at the house demo, which does the same with every module.

Every name below is real: `tests/docs/test_tutorial.gd` checks that each class and path in this page exists, and runs the script in step 4.

## 1. Needs

A need is data: a `BustleNeedDef` with an id, a rate per hour and the conditions it rises under. A `BustleNeedSet` holds one agent's needs and their pressure (0 to 1).

```gdscript
static func need(id: StringName, rate: float) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = [&"awake"]
	return def
```

`needs.advance(minutes, [&"awake"])` moves them on, and `needs.relieve(id, amount)` brings one down.

## 2. Goals and a brain

A goal (`BustleGoalDef`) is also data. A goal with `uses_advertisements` makes one candidate per object on offer, and scores each by how much it relieves the pressing needs. The goals go in a `BustleGoalLibrary`, and a `BustleBrain` chooses from it. There is no randomness: the same senses give the same choice.

## 3. The loop

Each step the host fills a `BustleSenses`: the needs as inputs (`needs.fill_inputs`), and what is on offer as `BustleAdvertisement`s, each an option id and the needs it relieves. Then it ticks the brain and acts on the `BustleIntent` it returns. Bustle never moves anyone: acting is the host's job, here a few lines that relieve the needs.

## 4. One optional module: a mood

Optional modules sit in `addons/bustle/modules/`. The mood (`BustleMood`, from `addons/bustle/modules/needs_mood/`) holds thoughts. Here a hot meal leaves a good thought for six game hours. Without the module, nothing else changes: the brain runs the same.

The whole script:

```gdscript
extends RefCounted

## A one-person household: food and sleep, a stove and a bed, and a mood.
## Returns, for each object, how many 10-minute steps it was chosen in, and how many thoughts the mood holds.
func run(days: int = 2) -> Dictionary:
	var needs := BustleNeedSet.new()
	needs.add_need(need(&"food", 0.06))
	needs.add_need(need(&"sleep", 0.05))
	var use := BustleGoalDef.new()
	use.id = &"use_object"
	use.band = BustleBands.PERSONAL
	use.uses_advertisements = true
	var library := BustleGoalLibrary.new()
	library.goals.append(use)
	var brain := BustleBrain.new(&"cook", library)
	var stove := BustleAdvertisement.new(&"stove", {&"food": 0.6} as Dictionary[StringName, float])
	var bed := BustleAdvertisement.new(&"bed", {&"sleep": 0.8} as Dictionary[StringName, float])
	var mood := BustleMood.new()
	mood.start(0)
	var meal := BustleThoughtDef.new()
	meal.id = &"hot_meal"
	meal.value = 4.0
	meal.duration_hours = 6.0
	var chosen := {}
	var last := &""
	for minute: int in range(0, days * 1440, 10):
		needs.advance(10.0, [&"awake"])
		var senses := BustleSenses.new()
		senses.now_minutes = minute
		needs.fill_inputs(senses.inputs)
		senses.advertisements.append(stove)
		senses.advertisements.append(bed)
		var intent := brain.tick(600.0, senses)
		var option := intent.option_id
		if option != &"":
			chosen[option] = int(chosen.get(option, 0)) + 1
			var relief := stove.relief if option == &"stove" else bed.relief
			for id: StringName in relief:
				needs.relieve(id, relief[id] * 0.25)
			if option == &"stove" and last != &"stove":
				mood.add_thought(meal)
		last = option
		mood.advance_to(minute)
	return {"chosen": chosen, "thoughts": mood.count()}


static func need(id: StringName, rate: float) -> BustleNeedDef:
	var def := BustleNeedDef.new()
	def.id = id
	def.rate_per_hour = rate
	def.rises_when = [&"awake"]
	return def
```

Run it from a test or a tool script (`load("res://my_household.gd").new().run()`). The cook eats at the stove when hungry and sleeps in the bed when tired, and each meal leaves a thought.

## 5. Where to go next

- **The house demo** (`demo/house/house.gd`) is the worked example. `House.build()` is this household with two residents, schedules and traits, run by the shared harness (`demo/harness/demo_harness.gd`). `House.session()` adds every module the house uses, for a full week.
- **The module guide** (`docs/modules.md`) lists each optional module, how to switch it on, and what happens without it.
- **Ports** (`addons/bustle/ports/README.md`) are how a game answers the addon's questions: where people are, who holds which role, how healthy someone is. Every port has a safe default, so a demo like this one needs none.
