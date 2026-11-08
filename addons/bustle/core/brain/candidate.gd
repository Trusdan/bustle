# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCandidate
extends RefCounted

## One scored choice: a goal, and the option it would use (empty for a goal without
## advertisements). It keeps the raw score, the score used for selecting, whether it is eligible,
## and the reasons behind the numbers.
## @experimental

## The goal.
var goal_id: StringName = &""
## The option, or empty.
var option_id: StringName = &""
## The goal's band.
var band: int = BustleBands.IDLE
## The score from the formulas, signed.
var raw_score: float = 0.0
## The score selection compares. The same as [member raw_score] unless something (such as momentum
## for the current choice) adjusts it.
var selection_score: float = 0.0
## True when it may be chosen: its preconditions pass, its inputs are valid, and its raw score is
## above zero and at least its goal's minimum.
var eligible: bool = false
## True for the IDLE fallback made when nothing was eligible.
var fallback: bool = false
## The breakdown: one dictionary per factor or problem, each with a [code]kind[/code].
var reasons: Array[Dictionary] = []


## The fallback chosen when no candidate is eligible: IDLE, scoring zero. It is a sentinel, the one
## exception to the rule that eligible means a score above zero; it is never put into a pick
## window with authored goals.
## @experimental
static func idle_fallback() -> BustleCandidate:
	var out := BustleCandidate.new()
	out.goal_id = &"idle"
	out.band = BustleBands.IDLE
	out.eligible = true
	out.fallback = true
	out.reasons = [{"kind": &"fallback"}]
	return out
