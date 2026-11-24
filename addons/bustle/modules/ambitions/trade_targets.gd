# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTradeTargets
extends RefCounted

## Which skill the [code]learn_trade[/code] ambition is about, from the installed skills: fills the
## inputs [BustleAmbitions] reads for it. Call [method fill] before [method BustleAmbitions.update],
## like [BustleAmbitionTargets].
## [br][br]
## [b]Installed skills.[/b] Only skills the skill port knows count: with [BustleSkills] as the port,
## its [method BustleSkills.skill_ids]. With any other port (the default, where everyone's level is
## 0) no skill is installed, so [code]has_trade_target[/code] stays false and the template is never
## assigned.
## [br][b]The line.[/b] A skill qualifies while it's installed and the agent's level in it is below
## the [code]learn_trade[/code] template's [member BustleAmbitionDef.target] (5 by default). With no
## such template in [member config], none does.
## [br][b]Which skill.[/b] [code]trade_skill[/code] when the host already set it in the inputs (a
## pin); else, while [code]learn_trade[/code] is active, the skill it's about, for as long as it's
## installed; else the agent's first passion ([method BustleSkills.passions_of]) that qualifies,
## or the qualifying skill with the lowest level, ties by id. Nothing is random.
## [br][b]Inputs.[/b] [code]has_trade_target[/code] (that skill qualifies), [code]trade_skill[/code],
## [code]skill_level[/code] (the agent's level in it) and [code]trade_skill_gone[/code] (the active
## ambition's skill is no longer installed, which ends it moot; the next [method fill] then picks
## another skill). No job, teacher or way to practise
## is required: practice is the host's, reported as XP to [BustleSkills].
## @experimental: Added after 1.0; it may be frozen in a later minor release.

## The template this fills inputs for.
const TEMPLATE := &"learn_trade"

## The skill port: the levels, and the installed skills when it's a [BustleSkills].
var skills: BustleSkillSet
## The library holding the [code]learn_trade[/code] template, whose target is the line.
var config: BustleAmbitionConfig


func _init(p_skills: BustleSkillSet = null, p_config: BustleAmbitionConfig = null) -> void:
	skills = p_skills if p_skills != null else BustleSkillSet.new()
	config = p_config if p_config != null else BustleAmbitionConfig.new()


## Adds the learn-a-trade inputs for [param agent] to [param inputs], given its current ambition
## [param active] (from [method BustleAmbitions.active], or empty) and [param personality] (for
## passions derived from it; null: assigned passions only). See the class notes.
func fill(agent: StringName, active: Dictionary, inputs: Dictionary, personality: BustlePersonality = null) -> void:
	var current := StringName(str(active.get("target", ""))) if active.get("id", "") == String(TEMPLATE) else &""
	var skill := StringName(str(inputs.get("trade_skill", "")))
	if skill == &"":
		skill = current if current != &"" else target_for(agent, personality)
	inputs["has_trade_target"] = qualifies(agent, skill)
	inputs["trade_skill_gone"] = current != &"" and not installed().has(current)
	if skill != &"":
		inputs["trade_skill"] = String(skill)
		inputs["skill_level"] = skills.level(agent, skill)


## The skill [param agent] would set out to learn now, or empty: its first passion that qualifies,
## else the qualifying skill with the lowest level, ties by id.
func target_for(agent: StringName, personality: BustlePersonality = null) -> StringName:
	if skills is BustleSkills:
		for passion: StringName in (skills as BustleSkills).passions_of(agent, personality):
			if qualifies(agent, passion):
				return passion
	var best := &""
	var best_level := 0.0
	for skill: StringName in installed():
		var level := skills.level(agent, skill)
		if qualifies(agent, skill) and (best == &"" or level < best_level):
			best = skill
			best_level = level
	return best


## True when [param skill] is installed and [param agent]'s level in it is below the line.
func qualifies(agent: StringName, skill: StringName) -> bool:
	return skill != &"" and installed().has(skill) and skills.level(agent, skill) < line()


## The line: the [code]learn_trade[/code] template's target, or -INF (nothing qualifies) with no such
## template.
func line() -> float:
	var def := config.find(TEMPLATE)
	return def.target if def != null else -INF


## The installed skill ids, by id; empty unless the port is a [BustleSkills].
func installed() -> Array[StringName]:
	var out: Array[StringName] = []
	if skills is BustleSkills:
		out.assign((skills as BustleSkills).skill_ids())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
