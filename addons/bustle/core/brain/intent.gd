# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleIntent
extends RefCounted

## What a [BustleBrain] wants its agent to do after one tick. A body (in the host) applies it.
## The goal fields say what was chosen and why; the action fields come from the running step's
## [member BustleActionContext.output], copied only when they have the right type.
## @experimental

## The chosen goal ([code]idle[/code] for the fallback).
var goal_id: StringName = &""
## The running order's id, or empty when a self-chosen goal (or nothing) runs.
var order_id: StringName = &""
## True while a player controls the agent: the brain chose nothing.
var player_controlled: bool = false
## Orders that ended this tick, each [code]{order, outcome, reason}[/code] (see
## [BustleOrderQueue]).
var order_results: Array[Dictionary] = []
## The chosen option, or empty.
var option_id: StringName = &""
## The goal's band.
var band: int = BustleBands.IDLE
## The choice's raw score.
var score: float = 0.0
## True when nothing was eligible and this is the IDLE fallback.
var idle: bool = false
## The running step's action id, or empty when no sequence is running.
var action: StringName = &""
## Where to move, when [member has_move_to].
var move_to: Vector3 = Vector3.ZERO
## True when the step asks to move.
var has_move_to: bool = false
## How fast to move, in metres a second (0 when not set).
var speed: float = 0.0
## Which movement gear to move in (for example hurry), or empty: the host maps it to its own
## gears, so speed comes from the character, not from Bustle.
var gear: StringName = &""
## Where to face, when [member has_face].
var face: Vector3 = Vector3.ZERO
## True when the step asks to face somewhere.
var has_face: bool = false
## Who to attack, or empty.
var attack_target: StringName = &""
## Which object to use, or empty.
var use_affordance: StringName = &""
## Who to talk to, or empty.
var talk_to: StringName = &""
## Which animation to play, or empty.
var animation: StringName = &""
## When the goal's sequence failed this tick: [code]{step, action, reason}[/code]; else empty.
var failure: Dictionary = {}
## Why the goal was chosen: the scorer's and keeper's reasons.
var reasons: Array[Dictionary] = []


## The intent as plain data (for comparing, logging and inspection).
## @experimental
func to_dictionary() -> Dictionary:
	return {
		"goal": goal_id, "order": order_id, "player_controlled": player_controlled,
		"order_results": order_results.duplicate(true), "option": option_id, "band": band, "score": score,
		"idle": idle, "action": action,
		"move_to": move_to if has_move_to else null, "speed": speed, "gear": gear, "face": face if has_face else null,
		"attack_target": attack_target, "use_affordance": use_affordance, "talk_to": talk_to,
		"animation": animation, "failure": failure.duplicate(true), "reasons": reasons.duplicate(true),
	}


## Copies the fields of a step's [param output] that have the right type.
## @experimental
func read_output(output: Dictionary) -> void:
	if output.get("move_to") is Vector3 and (output["move_to"] as Vector3).is_finite():
		move_to = output["move_to"]
		has_move_to = true
	if output.get("face") is Vector3 and (output["face"] as Vector3).is_finite():
		face = output["face"]
		has_face = true
	var raw_speed: Variant = output.get("speed")
	if typeof(raw_speed) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw_speed)) and float(raw_speed) >= 0.0:
		speed = float(raw_speed)
	attack_target = _name(output, "attack_target")
	use_affordance = _name(output, "use_affordance")
	talk_to = _name(output, "talk_to")
	gear = _name(output, "gear")
	animation = _name(output, "animation")


static func _name(output: Dictionary, key: String) -> StringName:
	var value: Variant = output.get(key)
	return value if value is StringName else &""
