# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePorts
extends RefCounted

## One of each port, starting with every standalone default, so Bustle runs with no host. A host
## replaces the ones it implements by assigning its own subclass.
## @experimental

## Opinions, relationship kinds and deeds.
var social := BustleSocialPort.new()
## Who holds which role.
var roles := BustleRolesPort.new()
## Areas, places and bodies.
var world := BustleWorldPort.new()
## The game clock.
var clock := BustleClockPort.new()
## Fighting.
var combat := BustleCombatPort.new()
## Money and buying.
var trade := BustleTradePort.new()
## How actors regard each other.
var disposition := BustleDispositionPort.new()
## Jobs.
var work := BustleWorkPort.new()
## Skill levels.
var skills := BustleSkillSet.new()
## Life stages.
var life_stages := BustleLifeStagePort.new()
## Health.
var health := BustleHealthPort.new()
## Rooms and surroundings.
var environment := BustleEnvironmentPort.new()
## Event pacing.
var director := BustleDirectorPort.new()

## The port names, in a fixed order.
const NAMES: PackedStringArray = [
	"social", "roles", "world", "clock", "combat", "trade", "disposition",
	"work", "skills", "life_stages", "health", "environment", "director",
]


## The names of ports that have been set to null. Empty when all are present.
## @experimental
func missing() -> PackedStringArray:
	var out := PackedStringArray()
	for port_name: String in NAMES:
		if get(port_name) == null:
			out.append(port_name)
	return out
