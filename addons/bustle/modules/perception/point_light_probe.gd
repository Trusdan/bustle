# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustlePointLightProbe
extends BustleLightProbe

## An ambient level plus point sources. Each enabled source adds
## [code]energy × (1 − distance / range)²[/code] inside its range; the total is clamped to 1.
## An optional [member occluded] check lets a project drop a source that something blocks.
## @experimental

## Light everywhere, 0..1.
var ambient: float = 0.0
## The point sources.
var sources: Array[BustleLightSource] = []
## Optional: [code]func(from: Vector3, to: Vector3) -> bool[/code], true when something blocks
## the light from a source at [code]from[/code] to the sample point [code]to[/code]. Unset:
## nothing ever blocks.
var occluded: Callable


func _init(p_ambient: float = 0.0) -> void:
	ambient = p_ambient


## Adds [param source] and returns it.
func add_source(source: BustleLightSource) -> BustleLightSource:
	if not sources.has(source):
		sources.append(source)
	return source


## Removes [param source].
func remove_source(source: BustleLightSource) -> void:
	sources.erase(source)


## The light at [param position]: the ambient level plus every source that reaches it.
func sample(position: Vector3) -> BustleLightSample:
	var total := clampf(ambient, 0.0, 1.0)
	var lit: Array[StringName] = []
	for source: BustleLightSource in sources:
		var amount := source.contribution(position)
		if amount <= 0.0:
			continue
		if occluded.is_valid() and occluded.call(source.position, position) == true:
			continue
		total += amount
		lit.append(source.id)
	var result := BustleLightSample.new(total)
	result.sources = lit
	return result
