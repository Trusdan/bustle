# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCrimeConfig
extends Resource

## The numbers behind [BustleCrime]. Nothing here is a chance: a theft happens when its
## circumstances and the agent's personality add up, every time they do.
## @experimental

## The project setting a developer can turn agents' crime off with (default on). It isn't a game
## option: a host doesn't show it to players.
const SETTING := "bustle/simulation/npc_crime"

## The needs that can drive an agent to steal (it steals only something that eases one).
@export var needs: Array[StringName] = [&"food"]
## How pressing a need must be (0 to 1) before the agent even considers stealing.
@export_range(0.0, 1.0) var min_need: float = 0.6
## What the need's pressure plus the personality terms must reach for the agent to steal.
@export var threshold: float = 1.0
## Personality slider → weight: each adds [code]weight × (slider − 50) / 100[/code]. By default
## honesty holds an agent back twice as hard as greed and boldness push it on.
@export var slider_weights: Dictionary[StringName, float] = {&"honesty": -2.0, &"greed": 1.0, &"boldness": 1.0}


## True when the developer setting lets agents commit crimes (on unless set to false).
## @experimental
static func crime_allowed() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))
