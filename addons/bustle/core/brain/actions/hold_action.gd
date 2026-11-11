# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleHoldAction
extends BustleActionHandler

## [code]hold[/code]: stays put and never finishes ([code]held[/code] in the output), so an order
## that ends with it holds until it's cancelled, as a lock's order does.
## @experimental


func tick(context: BustleActionContext, _delta: float) -> Status:
	context.output["held"] = true
	return Status.RUNNING
