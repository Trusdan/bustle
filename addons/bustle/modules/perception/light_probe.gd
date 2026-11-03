# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleLightProbe
extends RefCounted

## Answers how much light reaches a point. Abstract: a project extends it (or uses
## [BustlePointLightProbe]) and overrides [method sample]. The base is always dark.
## @experimental


## The light at [param position].
func sample(_position: Vector3) -> BustleLightSample:
	return BustleLightSample.new(0.0)
