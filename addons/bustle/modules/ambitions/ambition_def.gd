# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAmbitionDef
extends Resource

## One ambition template, as data: who it suits (personality and circumstances), when it's done,
## and when it can no longer happen. [BustleAmbitions] reads it. Every circumstance, progress
## input and fact is a name the host fills each update, so a template refers to no particular
## person, place or system.
## @experimental

## Its id. Ties between equal scores break by id.
@export var id: StringName = &""
## False: never assigned, whatever it would score. A host turns templates off here.
@export var enabled: bool = true
## Slider → weight; the score is [code]Σ weight × (slider − 50) / 100[/code].
@export var weights: Dictionary[StringName, float] = {}
## Slider → the least it must be for the template to suit the agent.
@export var min_sliders: Dictionary[StringName, float] = {}
## Circumstances that must all be true for the template to be assigned (a work role, a rival, ...).
@export var requires: Array[StringName] = []
## The progress input, a number; with [member done_facts], done once it reaches [member target].
## Empty: no progress line.
@export var progress_input: StringName = &""
## What [member progress_input] must reach.
@export var target: float = 0.0
## Facts that must all be true too, for the progress line to complete it.
@export var done_facts: Array[StringName] = []
## A fact that completes it on its own (a host marking it done). Empty: none.
@export var done_fact: StringName = &""
## Facts that make it impossible for good (its target is dead or gone, a role lost for good). Any
## one ends an active ambition as moot.
@export var moot_facts: Array[StringName] = []
## The template to take next after it's completed, when that one is eligible and enabled. Empty:
## score the library again.
@export var next: StringName = &""


## True when it can be used: an id, known sliders with finite weights and minimums, a finite
## target, and some way to complete (a progress line or a done fact).
## @experimental
func is_valid() -> bool:
	if id == &"" or not is_finite(target) or (progress_input == &"" and done_fact == &""):
		return false
	for table: Dictionary in [weights, min_sliders]:
		for slider: StringName in table:
			if not BustlePersonality.SLIDERS.has(slider) or not is_finite(float(table[slider])):
				return false
	return true


## True when [param inputs] say it's done: [member done_fact] is true, or [member progress_input]
## has reached [member target] and every [member done_facts] is true.
## @experimental
func is_done(inputs: Dictionary) -> bool:
	if done_fact != &"" and bool(inputs.get(done_fact, false)):
		return true
	if progress_input == &"" or float(inputs.get(progress_input, -INF)) < target:
		return false
	return done_facts.all(func(fact: StringName) -> bool: return bool(inputs.get(fact, false)))


## True when [param inputs] say it can no longer happen: any [member moot_facts] is true.
## @experimental
func is_moot(inputs: Dictionary) -> bool:
	return moot_facts.any(func(fact: StringName) -> bool: return bool(inputs.get(fact, false)))


## A template with these values.
## @experimental
static func make(p_id: StringName, p_weights: Dictionary[StringName, float], p_requires: Array[StringName] = [],
		p_progress: StringName = &"", p_target: float = 0.0) -> BustleAmbitionDef:
	var def := BustleAmbitionDef.new()
	def.id = p_id
	def.weights = p_weights
	def.requires = p_requires
	def.progress_input = p_progress
	def.target = p_target
	return def
