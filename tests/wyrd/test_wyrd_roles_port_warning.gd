# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The Wyrd roles port with no Wyrd roles: set_holder() warns once and changes nothing.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")


func before_each() -> void:
	_Warn.reset()


func test_set_holder_without_roles_warns_once() -> void:
	var port := BustleWyrdRolesPort.new()
	port.set_holder(&"keeper", &"baker")
	port.set_holder(&"keeper", &"smith")
	assert_eq(port.holder_of(&"keeper"), &"", "nothing is set")
	assert_true(_Warn.has_warned("BustleWyrdRolesPort.no_roles"))
	assert_push_warning_count(1)
