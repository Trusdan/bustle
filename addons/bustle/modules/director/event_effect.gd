# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleEventEffect
extends Resource

## One thing a fired [BustleEventDef] does, as host data, applied by [BustleDirectorEffects]:
## [br]- [constant THOUGHT]: gives [member thought] to each target;
## [br]- [constant ORDER]: orders each target to run [member sequence] (at [member place], if set);
## [br]- [constant SPAWN]: asks the world port to bring [member count] of [member spawn_kind] into
## [member spawn_area]. The host makes them, or not; Bustle creates nothing.
## [br]Targets are the agents in [member target_ids], plus those with [member target_tag], plus
## everyone in [member target_area]. Nobody else is touched.

## Gives a thought.
const THOUGHT := &"thought"
## Gives an order.
const ORDER := &"order"
## Asks for a spawn.
const SPAWN := &"spawn"

## What it does: [constant THOUGHT], [constant ORDER] or [constant SPAWN].
@export var kind: StringName = THOUGHT
## Agents named directly.
@export var target_ids: Array[StringName] = []
## Agents carrying this tag (the host's tags). Empty: none by tag.
@export var target_tag: StringName = &""
## Everyone in this area. Empty: none by area.
@export var target_area: StringName = &""
## The thought: a timed one ([member BustleThoughtDef.duration_hours] above 0).
@export var thought: BustleThoughtDef
## The order's actions.
@export var sequence: BustleActionSequence
## Where the order is carried out. Empty: anywhere.
@export var place: StringName = &""
## What to spawn (the host's kind).
@export var spawn_kind: StringName = &""
## Where to spawn it. Empty: the host's choice.
@export var spawn_area: StringName = &""
## How many to ask for. At least 1.
@export var count: int = 1


## True when it names at least one target.
func has_targets() -> bool:
	return not target_ids.is_empty() or target_tag != &"" or target_area != &""


## Why it can't be used, or empty: a known kind; a thought or order with targets and a valid timed
## thought or a sequence; a spawn with a kind and a count of at least 1.
func validate() -> String:
	match kind:
		THOUGHT:
			if thought == null or not thought.is_valid() or thought.duration_hours <= 0.0:
				return "a thought effect needs a valid timed thought"
		ORDER:
			if sequence == null or sequence.steps.is_empty():
				return "an order effect needs a sequence"
		SPAWN:
			if spawn_kind == &"" or count < 1:
				return "a spawn effect needs a kind and a count of at least 1"
			return ""
		_:
			return "unknown effect kind '%s'" % kind
	if not has_targets() or target_ids.has(&""):
		return "a %s effect needs targets" % kind
	return ""
