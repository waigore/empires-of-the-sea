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
