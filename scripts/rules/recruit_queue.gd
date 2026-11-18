class_name RecruitQueue
extends RefCounted
## Orders the crown placed this Orders phase that land in the next Build/work:
## a `RecruitWorkerOrder`, a `BuildUnitOrder` for a regiment, a launched hull or
## a hired civilian (wiki: workers-and-population § Phase placement;
## military-armies § Recruitment; ships-and-naval § Ship muster;
## civilian-units § Training). Pure data, so the ledger and the turn pass read
## one list (REQ-P3-03).
##
## Costs are paid when an order resolves and a peasant is reserved while it
## waits, so a second order can never promise the same peasant twice
## (wiki: workers-and-population § Peasant reservation).

## Order kinds. A worker's key is its tier as a string; every other kind uses
## the catalog id of the type it builds.
const KIND_WORKER: String = "worker"
const KIND_CIVILIAN: String = "civilian"
const KIND_REGIMENT: String = "regiment"
const KIND_SHIP: String = "ship"

## Queued orders in the order the crown placed them: `{kind, key}`.
var orders: Array[Dictionary] = []

const _KNOWN: Array[String] = [KIND_WORKER, KIND_CIVILIAN, KIND_REGIMENT, KIND_SHIP]


static func order(kind: String, key: String) -> Dictionary:
	return {"kind": kind, "key": key}


## Appends one order. The caller has already validated it against the rules.
func add(kind: String, key: String) -> Dictionary:
	var row: Dictionary = order(kind, key)
	orders.append(row)
	return row


## Orders of this kind for this key still waiting for Build/work.
func pending(kind: String, key: String) -> int:
	var total: int = 0
	for row: Dictionary in orders:
		if String(row.get("kind", "")) == kind and String(row.get("key", "")) == key:
			total += 1
	return total


## Every waiting order of one kind, whatever its key.
func pending_kind(kind: String) -> int:
	var total: int = 0
	for row: Dictionary in orders:
		if String(row.get("kind", "")) == kind:
			total += 1
	return total


## Waiting worker orders, one count per tier: the hands that will join the pool
## at this turn's Build/work. They eat the turn they land, but their labour is
## the **next** Production phase's (wiki: workers-and-population § Phase
## placement — same-turn labour is not supported, the phase sequence is not
## reordered for it).
func arriving_by_tier() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(WorkerPool.TIER_COUNT)
	counts.fill(0)
	for row: Dictionary in orders:
		if String(row.get("kind", "")) != KIND_WORKER:
			continue
		var tier: int = int(String(row.get("key", "-1")))
		if tier >= 0 and tier < WorkerPool.TIER_COUNT:
			counts[tier] += 1
	return counts


func total() -> int:
	return orders.size()


func is_empty() -> bool:
	return orders.is_empty()


## Peasants promised to waiting orders: one per recruited/trained worker that
## converts a peasant, one per regiment and one per hull. Civilian builds take
## no headcount (wiki: workers-and-population § Peasant reservation).
func reserved_peasants() -> int:
	var total: int = 0
	for row: Dictionary in orders:
		match String(row.get("kind", "")):
			KIND_WORKER:
				var tier: int = int(String(row.get("key", "-1")))
				if tier >= 0 and tier < WorkerPool.TIER_COUNT \
						and WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier]:
					total += 1
			KIND_REGIMENT, KIND_SHIP:
				total += 1
	return total


## Ducats one waiting order costs when Build/work pays it: a worker's cost row,
## a civilian's hire, a regiment's muster or a hull's launch. The same figure
## the market's bid budget subtracts, so a recruit row and the auction cannot
## promise one purse twice (wiki: workers-and-population § Recruiting — "a batch
## is never a discount and never a promise the crown cannot keep";
## world-market § Treasury budget for bids).
static func order_treasury(kind: String, key: String) -> int:
	match kind:
		KIND_WORKER:
			var tier: int = _tier(key)
			if tier < 0:
				return 0
			return maxi(int(WorkerPool.recruit_cost(tier).get("treasury", 0)), 0)
		KIND_CIVILIAN:
			return maxi(CivilianCatalog.treasury_cost(key), 0)
		KIND_REGIMENT:
			return maxi(RegimentCatalog.treasury_cost(key), 0)
		KIND_SHIP:
			return maxi(ShipEconomy.treasury_cost(key), 0)
	return 0


## Stockpile goods one waiting order spends when Build/work pays it, commodity
## to units: a worker's cost row, a civilian's paper, a regiment's training
## inputs or a hull's build inputs. An unknown kind or key spends nothing, so a
## stale save never narrows a store (wiki: workers-and-population § Recruiting;
## § Peasant reservation — the reserve a second order must respect).
static func order_materials(kind: String, key: String) -> Dictionary:
	match kind:
		KIND_WORKER:
			var tier: int = _tier(key)
			if tier < 0:
				return {}
			return (WorkerPool.recruit_cost(tier).get("materials", {}) as Dictionary).duplicate()
		KIND_CIVILIAN:
			var paper: int = maxi(CivilianCatalog.paper_cost(key), 0)
			return {"paper": paper} if paper > 0 else {}
		KIND_REGIMENT:
			return RegimentEconomy.training_inputs(key)
		KIND_SHIP:
			return ShipEconomy.build_inputs(key)
	return {}


## Ducats the waiting orders have already promised to Build/work. A second press
## reads the purse net of this, so it can never file an order the queue has
## already spent (wiki: workers-and-population § Peasant reservation — the same
## reserve the peasant count keeps).
func promised_treasury() -> int:
	var total: int = 0
	for row: Dictionary in orders:
		total += order_treasury(String(row.get("kind", "")), String(row.get("key", "")))
	return total


## Stockpile goods the waiting orders have already promised to Build/work,
## commodity to units, for the same reason as [method promised_treasury].
func promised_materials() -> Dictionary:
	var total: Dictionary = {}
	for row: Dictionary in orders:
		var cost: Dictionary = order_materials(
			String(row.get("kind", "")), String(row.get("key", ""))
		)
		for commodity: Variant in cost.keys():
			var id: String = String(commodity)
			total[id] = int(total.get(id, 0)) + int(cost[commodity])
	return total


## A worker order's tier, or -1 for a key that names no tier (a stale save).
static func _tier(key: String) -> int:
	var tier: int = int(key)
	if tier < 0 or tier >= WorkerPool.TIER_COUNT:
		return -1
	return tier


## Hands the whole queue to Build/work and clears it, so an order resolves
## exactly once (wiki: workers-and-population § Phase placement).
func take_all() -> Array[Dictionary]:
	var taken: Array[Dictionary] = orders.duplicate(true)
	orders.clear()
	return taken


func copy() -> RecruitQueue:
	var clone := RecruitQueue.new()
	clone.orders = orders.duplicate(true)
	return clone


## What the court reads on its ledger for one order: the tier for a worker, the
## catalog name for a civilian, a regiment or a hull.
static func label(row: Dictionary) -> String:
	match String(row.get("kind", "")):
		KIND_WORKER:
			return WorkerPool.tier_one(int(String(row.get("key", "-1"))))
		KIND_CIVILIAN:
			return CivilianCatalog.display_name(String(row.get("key", "")))
		KIND_REGIMENT:
			return RegimentCatalog.display_name(String(row.get("key", "")))
		KIND_SHIP:
			return ShipStats.display_name(String(row.get("key", "")))
	return String(row.get("key", ""))


## Plain data for local saves: the queue in order.
func snapshot() -> Array:
	return orders.duplicate(true)


## Restores a saved queue; a row that is not a known order is dropped rather
## than trusted.
func read(data: Variant) -> void:
	orders.clear()
	if typeof(data) != TYPE_ARRAY:
		return
	for raw: Variant in data:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var kind: String = String(row.get("kind", ""))
		if not _KNOWN.has(kind):
			continue
		orders.append(order(kind, String(row.get("key", ""))))
