# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDispositionTable
extends Resource

## A data table of dispositions between groups, and optionally between two actors. Change a
## [code].tres[/code] value and two actors become hostile, neutral or friendly with no code
## change. [BustleDispositionPort] reads it.
##
## Keys are [code]"a>b"[/code]: how [code]a[/code] regards [code]b[/code]. With
## [member symmetric], [code]"b>a"[/code] is used when [code]"a>b"[/code] is missing. Actor
## rules win over group rules; anything unlisted gets [member default_disposition]. Members of the
## same group are [member same_group] to each other unless a rule says otherwise.
## @experimental

## For anything no rule covers.
@export var default_disposition: BustleDispositionPort.Disposition = BustleDispositionPort.Disposition.NEUTRAL
## Between two members of the same group.
@export var same_group: BustleDispositionPort.Disposition = BustleDispositionPort.Disposition.NEUTRAL
## Group rules: [code]"group_a>group_b"[/code] to a [enum BustleDispositionPort.Disposition] value.
@export var groups: Dictionary = {}
## Actor rules: [code]"actor_a>actor_b"[/code] to a value. They win over group rules.
@export var actors: Dictionary = {}
## True: a missing [code]"a>b"[/code] falls back to [code]"b>a"[/code].
@export var symmetric := true


## How [param a_id] in [param a_group] regards [param b_id] in [param b_group].
## @experimental
func lookup(a_id: StringName, a_group: StringName, b_id: StringName, b_group: StringName) -> BustleDispositionPort.Disposition:
	var found: Variant = _rule(actors, a_id, b_id)
	if found == null:
		found = _rule(groups, a_group, b_group)
	if found == null and a_group != &"" and a_group == b_group:
		return same_group
	if found == null:
		return default_disposition
	return clampi(int(found), 0, BustleDispositionPort.Disposition.size() - 1) as BustleDispositionPort.Disposition


## Sets the rule for how group [param a] regards group [param b].
## @experimental
func set_group_rule(a: StringName, b: StringName, value: BustleDispositionPort.Disposition) -> void:
	groups["%s>%s" % [a, b]] = value


func _rule(rules: Dictionary, a: StringName, b: StringName) -> Variant:
	if a == &"" or b == &"":
		return null
	var key := "%s>%s" % [a, b]
	if rules.has(key):
		return rules[key]
	var back := "%s>%s" % [b, a]
	if symmetric and rules.has(back):
		return rules[back]
	return null
