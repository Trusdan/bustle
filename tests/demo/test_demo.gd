# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The demo skeleton loads and shows the version.


func test_the_demo_shows_the_version() -> void:
	var main := (load("res://demo/main.tscn") as PackedScene).instantiate() as Control
	add_child_autofree(main)
	assert_eq((main.get_node("Title") as Label).text, "Bustle %s demo" % BustleInfo.VERSION)
