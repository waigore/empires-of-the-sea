class_name MarketBudget
extends RefCounted
## The crown's bid budget: the purse the turn's auction may spend, after the
## Build/work orders already waiting are paid (wiki: world-market § Treasury
## budget for bids; DR-20261115-13). Pure read — it prices the recruit queue and
## never spends, so the ledger, the order path and the tests read one figure
## (REQ-P2-03, REQ-P3-03).
##
## Only a net deficit narrows the budget: income never raises it, so a crown can
## never stage bids that, with its waiting orders, would leave the purse short
## (the wiki's conservative rule). A waiting order the turn later refuses still
## counts here — the projection is a promise, not a receipt.

## One waiting order's treasury cost, priced by the queue that owns the row:
## [method RecruitQueue.order_treasury] reads the same catalog the order pays at
## Build/work, so the market's budget and the recruit row cannot promise one
## purse twice. An unknown kind or key costs nothing, so a stale save never
## narrows a purse.
static func order_cost(kind: String, key: String) -> int:
	return RecruitQueue.order_treasury(kind, key)


## The name the order will land under, so the ledger can say what the purse is
## promised to. Empty for an unknown kind or key.
static func order_label(kind: String, key: String) -> String:
	match kind:
		RecruitQueue.KIND_WORKER:
			return WorkerPool.tier_one(int(key))
		RecruitQueue.KIND_CIVILIAN:
			return CivilianCatalog.display_name(key)
		RecruitQueue.KIND_REGIMENT:
			return RegimentCatalog.display_name(key)
		RecruitQueue.KIND_SHIP:
			return ShipStats.display_name(key)
	return ""


## Every order waiting for Build/work, in the order the crown placed them:
## `{kind, key, label, treasury}`. A zero-cost order is kept — it is still a
## promise the sheet counts, it just narrows nothing.
static func pending(economy: PlayerEconomy) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if economy == null or economy.recruits == null:
		return rows
	for raw: Variant in economy.recruits.orders:
		var order: Dictionary = raw
		var kind: String = String(order.get("kind", ""))
		var key: String = String(order.get("key", ""))
		rows.append({
			"kind": kind,
			"key": key,
			"label": order_label(kind, key),
			"treasury": order_cost(kind, key),
		})
	return rows


## Ducats the waiting orders will take from the purse in Build/work.
static func promised(economy: PlayerEconomy) -> int:
	var total: int = 0
	for row: Dictionary in pending(economy):
		total += int(row["treasury"])
	return total


## The signed non-bid treasury delta the market validator reads: negative when
## the waiting orders outrun the purse, zero when they ask nothing.
static func projected_non_bid_delta(economy: PlayerEconomy) -> int:
	return -promised(economy)


## The whole reading: the purse, what the waiting orders are promised, and what
## the auction may spend — `max(0, treasury − promised)`, the wiki's formula.
## `purse` is the crown's own balance with its debt kept: a sheet that printed
## `max(0, treasury)` as "the whole purse" would name a sum the crown does not
## hold (wiki: world-market § Treasury budget for bids; REQ-P5-05).
static func budget(economy: PlayerEconomy) -> Dictionary:
	var purse: int = economy.treasury if economy != null else 0
	var treasury: int = maxi(purse, 0)
	var orders: Array[Dictionary] = pending(economy)
	var promised_total: int = 0
	for row: Dictionary in orders:
		promised_total += int(row["treasury"])
	return {
		"treasury": treasury,
		"purse": purse,
		"promised": promised_total,
		"budget": maxi(treasury - promised_total, 0),
		"orders": orders,
	}
