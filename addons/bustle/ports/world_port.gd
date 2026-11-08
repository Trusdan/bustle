# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWorldPort
extends RefCounted

## Where agents and places are, how areas connect, and how bodies are made. A host extends this and
## overrides every method. The standalone default is one area, [constant DEFAULT_AREA], with
## everyone in it, places at positions set with [method set_place] (the origin for any other), no
## travel time, and **no bodies**: it never spawns, frees or moves anything, so it is headless only.
## @experimental

## The default's only area.
const DEFAULT_AREA := &"default"

var _places: Dictionary[StringName, Vector3] = {}


## The area [param _id] is in.
## @experimental
func area_of(_id: StringName) -> StringName:
	return DEFAULT_AREA


## The area the player is in.
## @experimental
func player_area() -> StringName:
	return DEFAULT_AREA


## Where the player is. Default: the origin.
## @experimental
func player_position() -> Vector3:
	return Vector3.ZERO


## The areas next to [param _area]. Default: none.
## @experimental
func neighbour_areas(_area: StringName) -> Array[StringName]:
	return []


## True when [param place] has a known position.
## @experimental
func has_place(place: StringName) -> bool:
	return _places.has(place)


## Where [param place] is. Check [method has_place] first: an unknown place answers the origin.
## @experimental
func place_position(place: StringName) -> Vector3:
	return _places.get(place, Vector3.ZERO)


## Sets where [param place] is (the default's data). Non-finite positions and empty names are
## ignored.
## @experimental
func set_place(place: StringName, position: Vector3) -> void:
	if place != &"" and position.is_finite():
		_places[place] = position


## The areas from [param a] to [param b], both included. Default: [code][a][/code] when they are
## the same, else [code][a, b][/code]; empty when either is empty.
## @experimental
func path_between(a: StringName, b: StringName) -> Array[StringName]:
	if a == &"" or b == &"":
		return []
	return [a] if a == b else [a, b]


## Game minutes to travel from area [param _a] to [param _b]. Default: 0.
## @experimental
func travel_minutes(_a: StringName, _b: StringName) -> int:
	return 0


## Makes the body of [param _id] at [param _xf] and returns it. Default: null (no bodies).
## @experimental
func spawn_body(_id: StringName, _xf: Transform3D) -> Node3D:
	return null


## Removes the body of [param _id]. Default: nothing to remove.
## @experimental
func free_body(_id: StringName) -> void:
	pass
