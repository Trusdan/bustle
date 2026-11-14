# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLifeStageRules
extends Resource

## The life stages and the calendar they are read with. Ages are game days; [member days_per_year]
## only converts years to days and back, so a host picks its own year length. Use [method validate]
## before relying on a set: [BustleLifeStages] ignores rules that aren't valid.
## @experimental

## Game days in one year, for [method days_of] and [method years_of]. Finite and above 0. An
## experimental default; Bustle assumes no calendar.
@export var days_per_year: float = 360.0
## The stages, youngest first.
@export var stages: Array[BustleLifeStageDef] = []


## Why these rules can't be used, or empty when they can: at least one stage; every stage present,
## with an id used once and finite, not negative [member BustleLifeStageDef.min_days] above the
## stage before it; no empty blocked tag; and [member days_per_year] finite and above 0.
## @experimental
func validate() -> String:
	if not is_finite(days_per_year) or days_per_year <= 0.0:
		return "days_per_year must be a finite number above 0"
	if stages.is_empty():
		return "there are no stages"
	var seen: Array[StringName] = []
	var previous: BustleLifeStageDef = null
	for i: int in stages.size():
		var stage := stages[i]
		if stage == null:
			return "stage %d is missing" % i
		if stage.id == &"":
			return "stage %d has no id" % i
		if seen.has(stage.id):
			return "stage id '%s' is used twice" % stage.id
		seen.append(stage.id)
		if not is_finite(stage.min_days) or stage.min_days < 0.0:
			return "stage '%s': min_days must be finite and not negative" % stage.id
		if previous != null and stage.min_days <= previous.min_days:
			return "stage '%s': min_days must be above the previous stage's ('%s')" % [stage.id, previous.id]
		if stage.blocked_goal_tags.has(&"") or stage.blocked_affordance_tags.has(&""):
			return "stage '%s': a blocked tag is empty" % stage.id
		previous = stage
	return ""


## True when [method validate] finds nothing wrong.
## @experimental
func is_valid() -> bool:
	return validate() == ""


## The stage an age of [param days] falls in: the last whose minimum it has reached. Null when it is
## younger than the first stage. Assumes valid rules.
## @experimental
func stage_for(days: float) -> BustleLifeStageDef:
	var out: BustleLifeStageDef = null
	for stage: BustleLifeStageDef in stages:
		if stage != null and days >= stage.min_days:
			out = stage
	return out


## The stage with [param id], or null.
## @experimental
func find(id: StringName) -> BustleLifeStageDef:
	for stage: BustleLifeStageDef in stages:
		if stage != null and stage.id == id:
			return stage
	return null


## [param years] in game days.
## @experimental
func days_of(years: float) -> float:
	return years * days_per_year


## [param days] in years.
## @experimental
func years_of(days: float) -> float:
	return days / days_per_year
