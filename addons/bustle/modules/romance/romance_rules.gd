# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRomanceRules
extends Resource

## The lines of the courtship ladder, for [BustleRomance]. Opinions are 0 to 100 and compatibility
## -1 to 1 (see [BustleCompatibility]). Each release line sits below its forming line, so a status
## doesn't flicker. The numbers are experimental defaults.
## @experimental

## Both opinions at least this, with [member courting_compat], start courting.
@export var courting_opinion: int = 70
## The compatibility courting needs.
@export var courting_compat: float = 0.2
## Courting ends (a breakup) when either opinion falls below this.
@export var courting_release: int = 55
## Both opinions at least this, after [member partner_days] of courting, make partners.
@export var partner_opinion: int = 80
## Game days of courting before partnership.
@export var partner_days: float = 7.0
## A partnership ends (a breakup) when either opinion falls below this. An engagement or marriage
## never ends on opinion: only the host ends it ([method BustleRomance.end]).
@export var partner_release: int = 60
## The thought each of the two gets on a breakup (a timed [code]BustleThoughtDef[/code]), or null.
@export var breakup_thought: Resource = null
## Kinds that rule a pair out of courting (the host's family kinds).
@export var blocked_kinds: Array[StringName] = [&"parent", &"child", &"sibling", &"in_law"]
## Reserved for affairs, off by default. There is no affair path: whatever its value, an agent with
## a partner or more never starts courting anyone else.
@export var affairs_enabled: bool = false
## How many status changes each pair keeps in its history.
@export var history_limit: int = 10
## The timed thought an agent gets when its partner (courting or above) takes to someone else, or
## null for none (the [signal BustleRomance.jealous] signal still fires).
@export var jealousy_thought: Resource = null
## A partner's opinion of a third agent at or above this makes the agent jealous, once.
@export var jealousy_opinion: int = 75
## Jealousy over that third agent can come again only after the partner's opinion of them has
## fallen below this.
@export var jealousy_release: int = 60
## Interactions (by id) that make a partner's partner jealous when done to a third agent
## ([method BustleRomance.notice]). Empty: none. The host names its own.
@export var jealousy_verbs: Array[StringName] = []


## True when it can be used: opinions from 0 to 100 with each release line below its forming
## line (jealousy's too), a finite compatibility line, a non-negative finite courting time and a history of at least
## one entry.
## @experimental
func is_valid() -> bool:
	for line: int in [courting_opinion, courting_release, partner_opinion, partner_release, jealousy_opinion,
			jealousy_release]:
		if line < 0 or line > 100:
			return false
	return courting_release < courting_opinion and partner_release < partner_opinion and jealousy_release < jealousy_opinion \
			and is_finite(courting_compat) and is_finite(partner_days) and partner_days >= 0.0 and history_limit >= 1
