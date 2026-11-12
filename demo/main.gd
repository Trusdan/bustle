# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends Control

## The demo's start screen: the version, and a button for each demo scene.


func _ready() -> void:
	($Title as Label).text = "Bustle %s demo" % BustleInfo.VERSION
	($House as Button).pressed.connect(func() -> void: get_tree().change_scene_to_file("res://demo/house/house.tscn"))
	($Colony as Button).pressed.connect(func() -> void: get_tree().change_scene_to_file("res://demo/colony/colony.tscn"))
