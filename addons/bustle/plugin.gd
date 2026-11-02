# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
@tool
extends EditorPlugin

## Editor entry point for Bustle.
##
## @experimental
## Kept thin on purpose: all logic lives in plain [RefCounted] classes so it can be tested
## headless. This plugin registers nothing yet.


func _enter_tree() -> void:
	return


func _exit_tree() -> void:
	return
