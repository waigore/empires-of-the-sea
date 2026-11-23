class_name AiObjectiveWarPlan
extends RefCounted
## The court's one order a turn: press a war, open one, or spend it ending the
## war that blocks everything else (the peace window T2 funds, #497). Pure:
## readings in, objectives out (REQ-P2-03).


## The court's one order a turn: press a war, open one, or spend it ending the
## war that blocks everything else (the peace window T2 funds, #497). An aim
## that has lost the order to its sibling for the escalation bar's turns reads
## `blocked` with the sibling's name — the contention, said out loud once the
## stall is long (issue #603).
static func build(readings: Dictionary, at_war: bool) -> Array[AiObjective]:
	var desire: int = clampi(int(readings.get("war_desire", 0)), 0, 100)
	var blockings: Dictionary = readings.get("blockings", {})
	var orders: Array[AiObjective] = []
	if at_war:
		var press := AiObjective.create("war.press", "diplomacy", desire, {"orders": 1})
		var window := AiObjective.create(
			"peace.window", "diplomacy", 100 - desire, {"orders": 1}
		)
		var press_stall: int = int(blockings.get("war.press", 0))
		var window_stall: int = int(blockings.get("peace.window", 0))
		# The sibling that has been losing the order names why it waits.
		if window_stall > 0 and desire >= 50:
			window.block("the court presses its war (%d turns)" % window_stall)
		elif press_stall > 0 and desire < 50:
			press.block("the court sues for peace (%d turns)" % press_stall)
		orders.append(press)
		orders.append(window)
		return orders
	var declare := AiObjective.create("war.declare", "diplomacy", desire, {"orders": 1})
	var declare_stall: int = int(blockings.get("war.declare", 0))
	if declare_stall > 0:
		declare.block("the court does not want this war (%d turns)" % declare_stall)
	orders.append(declare)
	return orders
