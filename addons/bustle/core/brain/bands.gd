# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleBands
extends RefCounted

## The priority bands goals sit in. A band is a whole number and the higher one wins: the scorer
## chooses only from the highest band that has an eligible candidate, and scores are never compared
## across bands. The gaps leave room for bands that later features add between these.
## @experimental

## Danger: fight, flee, search for a lost target.
const CRITICAL := 100
## Pressing matters: investigate a noise, help someone in trouble, eat when starving.
const URGENT := 80
## Desperate acts under guards, such as theft: below urgent self-care, above orders and duty. A
## goal here is offered only when its guards pass (see [BustleCrime]).
const GUARDED := 75
## A player or quest order: below urgent self-care, above duty.
const ORDERED := 70
## A forced order: above everything, danger included.
const FORCED := 110
## The current scheduled duty.
const DUTY := 60
## Free time: socialise, visit, buy something.
const PERSONAL := 40
## Always available: wander, sit, look around. Also the fallback when nothing is eligible.
const IDLE := 20


## The name of [param band], or its number when it isn't one of these.
## @experimental
static func name_of(band: int) -> String:
	match band:
		FORCED:
			return "FORCED"
		CRITICAL:
			return "CRITICAL"
		URGENT:
			return "URGENT"
		GUARDED:
			return "GUARDED"
		ORDERED:
			return "ORDERED"
		DUTY:
			return "DUTY"
		PERSONAL:
			return "PERSONAL"
		IDLE:
			return "IDLE"
	return str(band)
