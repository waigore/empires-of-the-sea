class_name MainlineAiClaims
extends RefCounted
## The reservation primitive the rival economy and the ledger share
## (docs/ai-objectives.md; issue #491 T3, #498).
##
## Four dialects reserved stock in four places: the ration the consumption phase
## eats, the inputs this turn's production promised, the row the next regiment
## is provisioned with, and the material each planned work will spend. They are
## one primitive now — a ranked claim per row, allocated against the stockpile
## pool exactly like every other objective.
##
## The numbers are the planners' own, computed where they always were, so the
## refactor is behaviour-parity by construction (REQ-P2-03). Only the *shape*
## changed: a row is an `AiObjective`, its `cost` is `commodity -> units`, and
## `AiObjectiveLedger` decides what each claim is actually granted.

## Claim ids, in the order the trace reads them (the order the market must keep
## stock in: rations the living eat first, then the regiment being raised, then
## the works, then this turn's production, then what the booked orders hold).
const RATIONS: String = "reserve.rations"
const MUSTER: String = "reserve.muster"
const WORKS: String = "reserve.works"
const PRODUCTION: String = "reserve.production"
const KEPT: String = "reserve.kept"
## The aim a running order keeps its own inputs back under.
const ORDER: Array[String] = [RATIONS, MUSTER, WORKS, PRODUCTION, KEPT]
## Utility per claim: rations outrank everything (a court that sells the food
## its regiments eat starves), then the muster's fabric, the works, and the
## production this turn already promised.
const UTILITY: Dictionary = {
	RATIONS: 95, MUSTER: 90, WORKS: 80, PRODUCTION: 70, KEPT: 85,
}


## The named rows one turn reserves, in reading order. An empty row is dropped,
## so a court that reserves nothing claims nothing.
static func sources(rows: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ORDER:
		var cost: Dictionary = rows.get(id, {})
		if cost.is_empty():
			continue
		out.append({"id": id, "utility": int(UTILITY.get(id, 80)), "cost": cost})
	return out


## Rank the rows, allocate them against `pool` (commodity -> units held, absent
## pool entries are unbounded) and return the merged reservation the market
## reads plus the ledger rows the turn trace prints.
static func reserve(rows: Array[Dictionary], pool: Dictionary = {}) -> Dictionary:
	var objectives: Array[AiObjective] = []
	for row: Dictionary in rows:
		var cost: Dictionary = row.get("cost", {})
		if cost.is_empty():
			continue
		objectives.append(
			AiObjective.create(
				String(row.get("id", "")), "economy", int(row.get("utility", 80)), cost
			)
		)
	var report: Dictionary = AiObjectiveLedger.run(objectives, pool)
	var reserved: Dictionary = {}
	for objective: AiObjective in objectives:
		for commodity: Variant in objective.claim.keys():
			var id: String = String(commodity)
			reserved[id] = int(reserved.get(id, 0)) + int(objective.claim[commodity])
	return {"reserved": reserved, "rows": report["objectives"], "lines": report["lines"]}


## The cash a crew may spend: the purse after the court's floor, as one claim
## against the treasury. The arithmetic is the published "spendable purse"
## (`treasury − floor`), so this stays a parity refactor, not a policy change.
static func purse(treasury: int, floor: int) -> Dictionary:
	var cost: Dictionary = {"treasury": maxi(treasury - maxi(floor, 0), 0)}
	var report: Dictionary = AiObjectiveLedger.run(
		[AiObjective.create("civilian.spend", "civilian", 90, cost)],
		{"treasury": maxi(treasury, 0)}
	)
	var row: Dictionary = (report["objectives"] as Array)[0]
	return row.get("claim", {})