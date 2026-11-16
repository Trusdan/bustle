# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHealthEffect
extends Resource

## How one host capacity scales one modifier key: at full capacity the key is untouched, and below
## it the key is multiplied by [code]at_zero + (1 - at_zero) × capacity^power[/code]. Several effects
## on one key multiply together. Bustle's defaults are in [method BustleHealthConfig.defaults].

## The capacity it reads ([method BustleHealthPort.capacity]).
@export var capacity: StringName = &""
## The modifier key it scales, such as [code]work.speed[/code] or [code]move.speed[/code].
@export var key: StringName = &""
## The multiplier at capacity 0. Not negative.
@export var at_zero: float = 0.0
## The curve's shape: 1 is a straight line, above 1 bends it down (slower at middling capacity).
## Above 0.
@export var power: float = 1.0


## True when it names a capacity and a valid modifier key, and its numbers are usable.
func is_valid() -> bool:
	return capacity != &"" and BustleModifierSet.is_valid_key(key) and is_finite(at_zero) and at_zero >= 0.0 \
			and is_finite(power) and power > 0.0


## The multiplier for [param amount] of the capacity, clamped to 0..1 first.
func mult(amount: float) -> float:
	return at_zero + (1.0 - at_zero) * pow(clampf(amount, 0.0, 1.0), power)
