# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleActionSequence
extends Resource

## A short plan as data: steps run in order, with no branching beyond each step's
## [member BustleActionStep.on_fail]. An empty sequence succeeds at once.
## @experimental

## The steps, in order.
@export var steps: Array[BustleActionStep] = []
