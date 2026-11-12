# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleSkillDef
extends Resource

## One skill, as data: its id, its top level, how much practice each level costs and how it fades
## without practice. [BustleSkills] reads it. Bustle ships no skills; the host supplies every def.
## The numbers here are experimental defaults.
## @experimental

## Its id, chosen by the host (for example [code]cooking[/code]).
@export var id: StringName = &""
## The highest level. A point of skill is one band of [member xp_curve].
@export var max_level: int = 20
## The level decay stops at. Skill at or below it never fades.
@export var decay_floor: float = 0.0
## Levels lost per game day while above [member decay_floor]. 0: no decay.
@export var decay_per_day: float = 0.0
## XP needed for each level, from level 0 to 1 onwards. The last entry repeats for the levels
## after it, so [code][100.0][/code] costs 100 XP a level.
@export var xp_curve: Array[float] = [100.0]


## True when it can be used: an id, a positive top level, a floor in [code]0..max_level[/code],
## a non-negative decay rate, and a curve of positive finite costs.
## @experimental
func is_valid() -> bool:
	if id == &"" or max_level <= 0 or xp_curve.is_empty():
		return false
	if not is_finite(decay_floor) or decay_floor < 0.0 or decay_floor > max_level:
		return false
	if not is_finite(decay_per_day) or decay_per_day < 0.0:
		return false
	for cost: float in xp_curve:
		if not is_finite(cost) or cost <= 0.0:
			return false
	return true


## The XP that level [param band] costs (from [param band] to [param band] + 1).
## @experimental
func cost_of(band: int) -> float:
	return xp_curve[mini(maxi(band, 0), xp_curve.size() - 1)]


## The level [param xp] gives: whole levels for each band paid, plus the fraction of the next,
## never above [member max_level].
## @experimental
func level_for(xp: float) -> float:
	var left := maxf(xp, 0.0)
	for band: int in max_level:
		var cost := cost_of(band)
		if left < cost:
			return band + left / cost
		left -= cost
	return float(max_level)


## The XP that reaches [param level] exactly, the inverse of [method level_for].
## @experimental
func xp_for(level: float) -> float:
	var target := clampf(level, 0.0, float(max_level))
	var xp := 0.0
	var band := 0
	while band + 1 <= target:
		xp += cost_of(band)
		band += 1
	if band < max_level:
		xp += (target - band) * cost_of(band)
	return xp


## The XP at [member max_level]; practice past it is not kept.
## @experimental
func max_xp() -> float:
	return xp_for(float(max_level))
