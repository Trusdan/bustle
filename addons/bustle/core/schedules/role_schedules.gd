# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRoleSchedules
extends Resource

## Jobs as roles, as data: the routine that comes with each role, and who pays its wages. An agent
## holding one of these roles (through the roles port) has that role as its job and follows its
## routine. See [BustleScheduleRoster].
## @experimental

## Role → its routine.
@export var schedules: Dictionary[StringName, BustleScheduleDef] = {}
## Role → who pays its wages when a block names no payer.
@export var employers: Dictionary[StringName, StringName] = {}
