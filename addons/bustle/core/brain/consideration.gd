# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleConsideration
extends Resource

## One factor in a goal's score: a [Curve] sampled at one input (see [BustleInputs]). The curve's
## output is used as it is, signed and unclamped: a curve's tangents can overshoot its value range.
## @experimental

## The input it reads.
@export var input: StringName = &""
## The response curve. [method Curve.sample] clamps the input to the curve's domain.
@export var curve: Curve
