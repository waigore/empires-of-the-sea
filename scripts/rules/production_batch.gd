class_name ProductionBatch
extends RefCounted
## The ceiling a PRODUCTION row's "+" is capped by: the runs the coming phase
## could start from the projected post-Consumption store and idle labour, less
## the other rows' claims and the pieces already on the bench (REQ-P2-03).
##
## Pure: the economy and the projection the page prints in, a figure out. No
## nodes, no order of its own (REQ-P3-03). The page sets runs one row at a time
## with its own steppers, so this is the only arithmetic it shares with the
## rules.

## Units a row may still be set to, read from the projection the page prints:
## the post-Consumption store and the idle labour the phase will see, less the
## other rows' claims and the pieces already on the bench. The rules own the
## arithmetic; this only picks which state the phase will see (REQ-P2-03). The
## court's study set rides along so a row the phase would skip for want of a
## technology is offered nothing here either (wiki: production-recipes
## § Technology-gated recipes).
static func allowance(
	economy: PlayerEconomy,
	recipe_id: String,
	town_level: int,
	stock: Dictionary,
	labour: int,
	assignments: Array
) -> int:
	if economy == null:
		return 0
	return ProductionPhase.allowance(
		recipe_id,
		stock,
		labour,
		assignments,
		economy.workers,
		economy.production_wip,
		town_level,
		economy.tech_unlocked
	)


## The store and the idle labour the phase will see, from the projection the page
## prints; a page filled without one reads the live store and pool, so the ceiling
## still answers (REQ-P2-03).
static func budget(economy: PlayerEconomy, report: Dictionary) -> Dictionary:
	if economy == null:
		return {"stock": {}, "labour": 0}
	var stock: Dictionary = report.get("after_consumption", economy.stockpile) as Dictionary
	var labour: int = economy.workers.labour()
	if not report.is_empty():
		labour = int((report.get("consumption", {}) as Dictionary).get("idle_labour", 0))
	return {"stock": stock, "labour": labour}
