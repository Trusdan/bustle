# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRoleTable
extends Resource

## Who holds each role at the start, for the default [BustleRolesPort].
## @experimental

## Role → the id holding it.
@export var holders: Dictionary[StringName, StringName] = {}
