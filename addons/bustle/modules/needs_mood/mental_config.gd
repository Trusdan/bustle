# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleMentalConfig
extends Resource

## The numbers behind [BustleMentalState]. A starting point, not tuning: a host sets its own. The
## modifiers [code]mental.break_threshold[/code] (added to [member break_threshold], so traits
## can move it) and [code]mental.inspired[/code] (above 0: a trait that opts in to inspiration)
## adjust them per agent.
## @experimental

## The project setting a developer or a test turns mental states off with (default on). It isn't
## a game option.
const SETTING := "bustle/simulation/mental_states"

## The states, in tie-break order: quieter low states first.
@export var states: Array[BustleMentalStateDef] = default_states()
## Below this mood, a low state starts.
@export var break_threshold: float = 30.0
## Below this share of the threshold, a low state is major (4/7, about 17 by default).
@export var major_fraction: float = 4.0 / 7.0
## Below this share of the threshold, a low state is extreme (1/7, about 4 by default).
@export var extreme_fraction: float = 1.0 / 7.0
## A low state ends early once mood rises to the threshold plus this (40 by default).
@export var recover_margin: float = 10.0
## Above this mood, high spirits can start.
@export var high_spirits_above: float = 80.0
## High spirits end early below this.
@export var high_spirits_exit: float = 75.0
## Above this mood, inspiration can start (with a slider or trait match).
@export var inspired_above: float = 90.0
## Inspiration ends early below this.
@export var inspired_exit: float = 85.0
## A slider above this counts as a match for inspiration: diligence or curiosity.
@export var inspired_slider: float = 50.0
## Below this opinion of the target, it counts as disliked: lashing out needs a target that's
## disliked or marked as a rival.
@export var dislike_line: float = 50.0
## How much a disliked target pushes lashing out: [code]weight × (50 − opinion) / 100[/code].
@export var dislike_weight: float = 1.0
## The aftermath thought after a low state ends: mood points, game hours, how many can stack and
## how much each repeat counts of the one before.
@export var catharsis_value: float = 20.0
@export var catharsis_hours: float = 48.0
@export var catharsis_stack: int = 3
@export var catharsis_stack_mult: float = 0.5


## The seven states with their default weights and durations.
## @experimental
static func default_states() -> Array[BustleMentalStateDef]:
	var b := BustleMentalStateDef.Behaviour
	var low := BustleMentalStateDef.LOW
	var high := BustleMentalStateDef.HIGH
	return [
		BustleMentalStateDef.make(&"withdraw", b.WITHDRAW, low, {&"sociability": -2.0, &"diligence": -1.0}, 8.0),
		BustleMentalStateDef.make(&"sulk", b.SULK, low, {&"temper": 1.0, &"sociability": -1.0}, 12.0),
		BustleMentalStateDef.make(&"wander", b.WANDER, low, {&"curiosity": 1.0, &"diligence": -1.0}, 24.0),
		BustleMentalStateDef.make(&"binge", b.BINGE, low, {&"greed": 1.0}, 8.0, BustleMentalStateDef.INDULGENCE),
		BustleMentalStateDef.make(&"lash_out", b.LASH_OUT, low, {&"temper": 2.0, &"boldness": 1.0}, 12.0, BustleMentalStateDef.TARGET),
		BustleMentalStateDef.make(&"high_spirits", b.HIGH_SPIRITS, high, {&"sociability": 1.0}, 8.0),
		BustleMentalStateDef.make(&"inspired", b.INSPIRED, high, {&"diligence": 1.0, &"curiosity": 1.0}, 12.0),
	]


## True unless a developer or a test turned [constant SETTING] off.
## @experimental
static func allowed() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))


## The catharsis thought, for [BustleMood]: a host passes it with its other thought defs when it
## loads a mood.
## @experimental
func catharsis_def() -> BustleThoughtDef:
	var def := BustleThoughtDef.new()
	def.id = &"catharsis"
	def.value = catharsis_value
	def.duration_hours = catharsis_hours
	def.stack_limit = catharsis_stack
	def.stack_mult = catharsis_stack_mult
	def.emotion = &"relieved"
	def.reason_kind = &"event"
	return def
