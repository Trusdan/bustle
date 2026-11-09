# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleScheduleDay
extends Resource

## One day's blocks, for a [BustleScheduleDef]. Blocks shouldn't overlap; where they do, the one
## listed first wins.
## @experimental

## The day's blocks.
@export var blocks: Array[BustleScheduleBlock] = []
