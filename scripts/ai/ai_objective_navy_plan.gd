class_name AiObjectiveNavyPlan
extends RefCounted
## The fleet's turn: a squadron with hulls sorts out; a court with no fighting
## hull (peace or war), or one outmatched on its own coast, lays one down. The
## merchant tonnage short of the seat's need sails home (docs/ai.md; issue #491
## T5, #484, #591). Pure: readings in, objectives out (REQ-P2-03).

## A court at war with no fighting hull puts the yard ahead of a sortie: it has
## nothing to sortie with (issue #484, #500).
const W_NAVY_BUILD: int = 90
## The same yard, while the court cannot yet fill its chest and a regiment is
## due: below the muster's 85 (`W_MUSTER` + `W_MUSTER_WAR`), so the ledger funds
## the line first and the hull it never reaches stops starving the army
## (issue #591).
const W_NAVY_BUILD_WAITING: int = 80
## The sortie's and the cargo route's own weights: a squadron that sorts out,
## and the hulls that sail the tonnage home.
const W_NAVY: int = 60
const W_CARGO: int = 40


## The fleet's turn: a squadron with hulls sorts out; a court with no fighting
## hull (peace or war), or one outmatched on its own coast, lays one down. The
## build claims the yard's treasury row; a chest not yet reached ranks below the
## muster (issue #491 T5, #484, #591).
static func navy(readings: Dictionary, at_war: bool) -> AiObjective:
	var own: int = int(readings.get("warships", 0))
	var hostile: int = int(readings.get("hostile_warships", 0))
	if AiNavy.due(at_war, own, hostile):
		return _build(readings, own, hostile)
	if not at_war:
		return null
	var threat: int = AiUtility.ratio(hostile, maxi(own + hostile, 1))
	return AiObjective.create(
		"navy.sortie", "naval", AiUtility.clamp_utility(W_NAVY + threat / 2),
		{"hull": 1}
	)


## The hull the yard is saving for, blocked with the reason its own gate reads —
## the techs that open it, the free hand the slip takes, or the stall it has
## been deferred past (issue #1126, #1275).
static func _build(readings: Dictionary, own: int, hostile: int) -> AiObjective:
	var threat: int = AiUtility.ratio(hostile, maxi(own + hostile, 1))
	var utility: int = W_NAVY_BUILD
	if own > 0:
		utility = AiUtility.clamp_utility(W_NAVY_BUILD - 20 + threat / 2)
	# A chest the court has not reached waits behind the army: the yard is
	# still its aim, but a yard price it cannot pay must not claim the purse
	# the muster needs, or the hull is never laid and the line never rises
	# (issue #591).
	if _chest_beyond_reach(readings):
		utility = mini(utility, W_NAVY_BUILD_WAITING)
	var build := AiObjective.create("navy.build", "naval", utility, _build_cost(readings))
	var gate: String = _refusal(readings)
	if not gate.is_empty():
		build.block(gate)
	return build


## Why the yard may not lay the hull it funds, in its gate's own words: no tech
## opens it, no free hand leaves the pool at launch (issue #1126), or the chest
## has stalled past the escalation bar while a line is due (issue #603, #1275).
static func _refusal(readings: Dictionary) -> String:
	if not bool(readings.get("warship_open", false)):
		return "no warship its techs open"
	if int(readings.get("warship_hands", ShipEconomy.WORKER_COST)) \
			< ShipEconomy.WORKER_COST:
		# One peasant leaves the pool at launch: a court with no free hand
		# funds no hull the yard would refuse (issue #1126).
		return "no free hand for the slip"
	# The naming rides the same valve the chest reads (issue #1275): once the
	# line is no longer due the stand-down is over — the frozen stall is the
	# fill's history, not its present, and the row reads the bank again.
	var stall: Dictionary = (readings.get("blockings", {}) as Dictionary)
	var yard_stall: int = int(stall.get("navy.build", 0))
	if yard_stall <= 0 or not bool(readings.get("muster_due", false)):
		return ""
	# The yard's own gate rides in the same words, so a court that cannot lay the
	# hull it funds reads why instead of banking the chest again (issue #1126).
	var gate: String = String(readings.get("warship_refusal", ""))
	return (
		"the yard is out of reach %d turns" % yard_stall
		if gate.is_empty()
		else "the yard is out of reach %d turns (%s)" % [yard_stall, gate]
	)


## True while the court is still short of the yard's price and a regiment is
## due: the chest it means to fill is out of reach, so the army's claim outranks
## it (issue #591, `AiIncome.hull_held`). A fleetless court keeps the yard ahead
## of the muster — the same own-warships gate as `hull_held` (issue #484).
static func _chest_beyond_reach(readings: Dictionary) -> bool:
	if int(readings.get("warships", -1)) == 0:
		return false
	if not bool(readings.get("muster_due", false)):
		return false
	var price: int = int(readings.get("warship_price", 0))
	return price > 0 and int(readings.get("treasury", 0)) < price


## Treasury claim only: cloth stays on `AiClaims.NAVY` so the objective does not
## double-book the bolt the market already held (issue #484). The hand the yard
## takes at launch is a gate, not a claim — reading it out of the shared labour
## pool would starve the production run ranked under it (issue #1126).
static func _build_cost(readings: Dictionary) -> Dictionary:
	return {"treasury": int(readings.get("warship_price", 0))}


## Merchant tonnage short of the seat's need: sail the hulls home.
static func cargo(readings: Dictionary) -> AiObjective:
	var shortfall: int = int(readings.get("cargo_shortfall", 0))
	if shortfall <= 0:
		return null
	return AiObjective.create(
		"cargo.route", "economy", AiUtility.clamp_utility(W_CARGO + shortfall),
		{"hull": shortfall}
	)
