# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends "res://tests/health/fake_health_port.gd"

## A test host that owns recovery: each patient's need for care falls by [member rate] a minute,
## three times as fast once it has been cared for. [method care] answers [member answer].

var rate := 0.001
var answer := true
var cared: Array[StringName] = []
var calls: Array = []


func care(healer: StringName, patient: StringName) -> bool:
	calls.append([healer, patient])
	if answer and care_needed.get(patient, 0.0) > 0.0 and not cared.has(patient):
		cared.append(patient)
	return answer


func advance(minutes: int) -> void:
	for patient: Variant in care_needed.keys():
		var speed := rate * (3.0 if cared.has(patient) else 1.0)
		care_needed[patient] = maxf(float(care_needed[patient]) - speed * minutes, 0.0)
