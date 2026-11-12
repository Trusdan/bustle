# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWyrdBridge
extends RefCounted

## The optional bridge between Bustle and the Wyrd narrative engine.
##
## @experimental
## It is pinned to one exact Wyrd release ([constant WYRD_VERSION]) and checks it before doing
## anything. It reads Wyrd's [code]VERSION[/code] file and calls Wyrd by name, so this script
## compiles, and Bustle's core works, with no Wyrd in the project. Nothing in [code]addons/bustle/[/code]
## refers to this folder.
##
## [method install] makes Wyrd a society's social and roles ports ([BustleWyrdSocialPort],
## [BustleWyrdRolesPort]) and registers the dialogue facts ([BustleWyrdFacts]). Wyrd then holds
## opinions, relationship kinds, deeds, rumours and roles; the built-in [BustleSocialStore] and
## [BustleRelationshipRules] are not used. See [code]docs/wyrd-bridge.md[/code].

## The exact Wyrd release this bridge is written for.
const WYRD_VERSION: String = "1.0.1"
## Where Wyrd keeps its version.
const WYRD_VERSION_FILE: String = "res://addons/wyrd/VERSION"

## The social port it installed.
var social: BustleWyrdSocialPort
## The roles port it installed.
var roles: BustleWyrdRolesPort
## The dialogue facts it registered.
var facts: BustleWyrdFacts
## The names Wyrd accepted from [member facts].
var registered: PackedStringArray = PackedStringArray()


## The installed Wyrd version, or an empty string when Wyrd is not in the project.
## @experimental
static func installed_wyrd_version() -> String:
	if not FileAccess.file_exists(WYRD_VERSION_FILE):
		return ""
	return FileAccess.get_file_as_string(WYRD_VERSION_FILE).strip_edges()


## True when the installed Wyrd is exactly the pinned release.
## @experimental
static func is_supported() -> bool:
	return installed_wyrd_version() == WYRD_VERSION


## True when [param wyrd] reports exactly the pinned release through [code]get_version[/code].
## @experimental
static func supports(wyrd: Object) -> bool:
	return wyrd != null and wyrd.has_method(&"get_version") and str(wyrd.call(&"get_version")) == WYRD_VERSION


## Installs the bridge: [param wyrd] (Wyrd's facade) becomes [param society]'s social and roles
## ports, and the dialogue facts are registered in it, reading moods through [param mood_of] (see
## [member BustleWyrdFacts.mood_of]). Returns the bridge, or null, changing nothing, when Wyrd isn't
## exactly [constant WYRD_VERSION] (in the project and in [param wyrd]) or an argument is missing.
## Install once per Wyrd: a second install's dialogue facts are refused by Wyrd.
## @experimental
static func install(society: BustleSociety, wyrd: Object, mood_of: Callable = Callable()) -> BustleWyrdBridge:
	if society == null or not is_supported() or not supports(wyrd):
		return null
	var bridge := BustleWyrdBridge.new()
	bridge.social = BustleWyrdSocialPort.new(wyrd)
	bridge.roles = BustleWyrdRolesPort.new(wyrd)
	bridge.facts = BustleWyrdFacts.new(society)
	bridge.facts.mood_of = mood_of
	society.set_port(&"social", bridge.social)
	society.set_port(&"roles", bridge.roles)
	bridge.registered = bridge.facts.register(wyrd)
	return bridge
