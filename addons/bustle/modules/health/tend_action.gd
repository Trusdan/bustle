# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleTendAction
extends BustleActionHandler

## [code]tend[/code]: asks the host to have the agent care for its patient
## ([method BustleTendJob.patient_for]), through [method BustleTendJob.tend]. It names the patient
## in the output ([code]tend[/code]) so the host can move and animate the healer. Done when the
## host did the care; failed with [code]no_patient[/code] or [code]care_refused[/code] otherwise.

## The tend job it works for.
var job: BustleTendJob


func _init(p_job: BustleTendJob = null) -> void:
	job = p_job


func tick(context: BustleActionContext, _delta: float) -> Status:
	var patient := job.patient_for(context.agent_id) if job != null else &""
	if patient == &"":
		context.failure = &"no_patient"
		return Status.FAILED
	context.output["tend"] = patient
	if not job.tend(context.agent_id, patient):
		context.failure = &"care_refused"
		return Status.FAILED
	return Status.DONE
