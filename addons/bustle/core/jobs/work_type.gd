# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWorkType
extends Resource

## One kind of posted, one-off work, as data: who may take it (a role, a skill level, tags), how
## much a given agent wants it (personality and circumstances), and what it involves (place,
## minutes, wage). [BustleJobBoard] reads it. Standing jobs are roles and schedules, not work types.
## Bustle ships none; the host supplies every type.

## Its id, chosen by the host.
@export var id: StringName = &""
## The skill it uses, or empty. With [member min_skill], a gate; later parts also practise it.
@export var skill: StringName = &""
## The least level in [member skill] a taker needs (read through the skill port). 0: no gate.
@export var min_skill: float = 0.0
## The role a taker must hold, or empty for none.
@export var required_role: StringName = &""
## Tags a taker must all have (the host's own capabilities), or none.
@export var required_tags: Array[StringName] = []
## The score every agent starts from.
@export var priority: float = 0.0
## Slider → weight; adds [code]Σ weight × (slider − 50) / 100[/code] to the score.
@export var priority_weights: Dictionary[StringName, float] = {}
## Input → weight; adds [code]Σ weight × input[/code] to the score. Inputs are numbers the host
## fills for each agent (for example how much it needs money, from 0 to 1).
@export var need_weights: Dictionary[StringName, float] = {}
## XP of practice in [member skill] per game hour of work, added through the skill port when it
## can take practice (the skills module). 0: none.
@export var xp_per_hour: float = 10.0
## The wage a completed posting pays, in the trade port's unit.
@export var wage: int = 0
## How long the work takes, in game minutes.
@export var minutes: int = 60
## Where the work is done, unless a posting names another place. Empty: not tied to a place.
@export var place: StringName = &""
## Capacity name → the least amount, 0 to 1, a taker must have of it (read through
## [method BustleHealthPort.capacity]; names are the host's, for example [code]moving[/code]). An
## agent below any of them isn't offered the work, can't claim it, and lets go of a claim it holds
## (see [method BustleJobBoard.release_unfit]). Empty (the default): no health gate.
## @experimental: Added after 1.0 for the health module. No minimums are set by default; any a host sets are its own.
@export var min_capacities: Dictionary[StringName, float] = {}


## True when it can be used: an id, finite numbers, known sliders, a non-negative skill minimum
## and wage, a positive duration, and capacity minimums with names between 0 and 1.
func is_valid() -> bool:
	if id == &"" or not is_finite(min_skill) or min_skill < 0.0 or not is_finite(priority):
		return false
	if wage < 0 or minutes <= 0 or (min_skill > 0.0 and skill == &"") or not is_finite(xp_per_hour) or xp_per_hour < 0.0:
		return false
	for slider: StringName in priority_weights:
		if not BustlePersonality.SLIDERS.has(slider) or not is_finite(priority_weights[slider]):
			return false
	for input: StringName in need_weights:
		if input == &"" or not is_finite(need_weights[input]):
			return false
	for capacity: StringName in min_capacities:
		var least := min_capacities[capacity]
		if capacity == &"" or not is_finite(least) or least < 0.0 or least > 1.0:
			return false
	return true


## The first capacity in [member min_capacities] (in name order) that [param id] has less of than
## its minimum, by [param health]; empty when it has enough of each, or with no port. A reading
## that isn't a number counts as full, as [BustleHealthBehaviour] reads it.
## @experimental: Added after 1.0 for the health module.
func short_capacity(id: StringName, health: BustleHealthPort) -> StringName:
	if min_capacities.is_empty() or health == null:
		return &""
	var names: Array[StringName] = min_capacities.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for capacity: StringName in names:
		var amount := health.capacity(id, capacity)
		if is_finite(amount) and clampf(amount, 0.0, 1.0) < min_capacities[capacity]:
			return capacity
	return &""


## How much [param seeker] wants this work: [member priority], plus the slider and input terms.
## Missing sliders count as 50 and missing inputs as 0.
func score(seeker: BustleJobSeeker) -> float:
	var total := priority
	for slider: StringName in priority_weights:
		var value := seeker.personality.slider(slider) if seeker.personality != null else 50.0
		total += priority_weights[slider] * (value - 50.0) / 100.0
	for input: StringName in need_weights:
		total += need_weights[input] * seeker.inputs.get(input, 0.0)
	return total
