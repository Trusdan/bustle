# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends BustleWorldPort

## The village's map, as a host adapter (docs/ports.md, "BustleWorldPort"). The game knows where
## each place is and which area each villager is in; Bustle asks. Positions are on the ground plane:
## x and z, with y 0. Bodies are the view's business, so spawn_body() keeps the default (none).

## Where each villager is: a place, or [code]street[/code] between places.
var areas: Dictionary[StringName, StringName] = {}
## Where each place is.
var spots: Dictionary[StringName, Vector3] = {}
## The area the player watches from.
var player_at: StringName = &"square"


## The area [param id] is in.
func area_of(id: StringName) -> StringName:
	return areas.get(id, &"street")


## The area the player is in.
func player_area() -> StringName:
	return player_at


## True when [param place] is on the map.
func has_place(place: StringName) -> bool:
	return spots.has(place)


## Where [param place] is; the origin for an unknown place (check [method has_place] first).
func place_position(place: StringName) -> Vector3:
	return spots.get(place, Vector3.ZERO)
