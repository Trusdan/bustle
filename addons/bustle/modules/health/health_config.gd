# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthConfig
extends Resource

## What the health behaviour does with the host's readings: the capacity effects on modifiers, the
## thoughts, and what a downed agent may not choose. [method defaults] gives experimental values.
## @experimental

## The capacity → modifier effects. Every capacity named here also writes
## [code]capacity.<name>[/code] (base 1) as its clamped amount.
@export var effects: Array[BustleHealthEffect] = []
## The pain and tag thoughts.
@export var thoughts: Array[BustleHealthThought] = []
## While downed ([method BustleHealthPort.is_incapacitated]), a goal whose id or tags, or an option
## whose advertisement tags, include any of these is not chosen.
@export var downed_blocks: Array[StringName] = [&"work", &"travel"]


## Experimental defaults:
## [br]- [code]moving[/code] scales [code]move.speed[/code], [code]manipulation[/code] scales
## [code]work.speed[/code], and [code]consciousness[/code] scales both, each in a straight line to
## 0 at no capacity;
## [br]- pain of 0.2 or more holds [code]in_pain[/code] (−6), and of 0.6 or more
## [code]in_great_pain[/code] (−14) instead;
## [br]- the [code]sick[/code] tag holds [code]feeling_sick[/code] (−8).
## @experimental
static func defaults() -> BustleHealthConfig:
	var config := BustleHealthConfig.new()
	for row: Array in [[&"moving", &"move.speed"], [&"manipulation", &"work.speed"],
			[&"consciousness", &"work.speed"], [&"consciousness", &"move.speed"]]:
		var effect := BustleHealthEffect.new()
		effect.capacity = row[0]
		effect.key = row[1]
		config.effects.append(effect)
	for row: Array in [[&"in_pain", -6.0, 0.2, &""], [&"in_great_pain", -14.0, 0.6, &""], [&"feeling_sick", -8.0, NAN, &"sick"]]:
		var def := BustleThoughtDef.new()
		def.id = row[0]
		def.value = row[1]
		def.reason_kind = &"health"
		var rule := BustleHealthThought.new()
		rule.thought = def
		rule.pain_at_least = row[2]
		rule.tag = row[3]
		config.thoughts.append(rule)
	return config


## Why it can't be used, or empty: an invalid or missing effect or thought rule, or an empty
## downed block.
## @experimental
func validate() -> String:
	for i: int in effects.size():
		if effects[i] == null or not effects[i].is_valid():
			return "effect %d is not valid" % i
	for i: int in thoughts.size():
		if thoughts[i] == null or not thoughts[i].is_valid():
			return "thought rule %d is not valid" % i
	if downed_blocks.has(&""):
		return "a downed block is empty"
	return ""
