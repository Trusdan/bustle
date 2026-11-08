# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleInputs
extends RefCounted

## The fixed vocabulary of scorer inputs. An input key is a family and a name, such as
## [code]need.food[/code] or [code]trait.sociability[/code]; the families are fixed here, and the
## names within them are data. Adding a family is a reviewed code change; using one is data.
## Input values reach the scorer already normalised by whoever supplies them.
## @experimental

## Every family, by its prefix. [code]health[/code] stands alone; the others take a name.
const FAMILIES: PackedStringArray = [
	"need", "trait", "opinion", "memory", "distance", "schedule", "role", "fact", "time", "health", "threat",
]
## The input [code]mood[/code] the scorer's mood curves read (0 to 100). Not a family.
const MOOD := &"mood"


## True when [param key] is a well-formed input: [code]health[/code], [code]mood[/code], or a family
## followed by one or more dot-separated names of lower-case letters, digits and underscores.
## @experimental
static func is_valid_input(key: StringName) -> bool:
	var text := String(key)
	if text == "health" or key == MOOD:
		return true
	var parts := text.split(".")
	if parts.size() < 2 or not FAMILIES.has(parts[0]) or parts[0] == "health":
		return false
	for part: String in parts.slice(1):
		if part.is_empty() or not _is_name(part):
			return false
	return true


static func _is_name(part: String) -> bool:
	for i in part.length():
		var c := part.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true
