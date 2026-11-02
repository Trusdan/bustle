# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends Control

## The demo's start screen. A skeleton for now: later releases grow it into a small neutral town
## that shows each feature.


func _ready() -> void:
	($Title as Label).text = "Bustle %s demo" % BustleInfo.VERSION
