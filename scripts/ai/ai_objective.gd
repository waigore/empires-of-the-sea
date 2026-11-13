class_name AiObjective
extends RefCounted
## One ranked objective in a rival court's ledger (T1, trace-only).
##
## The ledger's shared currency is `utility` (0–100): every planner normalizes
## its own score into it, so priorities from different domains can finally be
## compared (wiki: ai-architecture; DR-20261113-15). `cost` declares what the
## objective needs from the court's resource pools; `claim` records what the
## allocate pass actually granted. Nothing here spends or mutates rules state —
## the ledger is a read model until a later task converts a spender
## (REQ-P2-03, REQ-P4-03).

const STATUS_RANKED: String = "ranked"
const STATUS_FUNDED: String = "funded"
const STATUS_DEFERRED: String = "deferred"
const STATUS_BLOCKED: String = "blocked"

## The pools an objective can claim. `orders` is the court's per-turn order
## attention: one diplomatic order, one civilian train slot, and so on.
const RESOURCES: Array[String] = [
	"treasury", "hull", "civilian", "regiment", "labour", "orders",
]

var id: String = ""
var domain: String = ""
var utility: int = 0
var cost: Dictionary = {}
var claim: Dictionary = {}
var status: String = STATUS_RANKED
var blocked: String = ""
## 1-based position after the rank pass; 0 before it.
var rank: int = 0
var shortfall: Dictionary = {}
var children: Array[AiObjective] = []


static func make(
	objective_id: String,
	objective_domain: String,
	objective_utility: int,
	objective_cost: Dictionary = {},
	objective_blocked: String = ""
) -> AiObjective:
	var objective := AiObjective.new()
	objective.id = objective_id
	objective.domain = objective_domain
	objective.utility = clampi(objective_utility, 0, 100)
	objective.cost = _clean_cost(objective_cost)
	objective.blocked = objective_blocked
	if not objective.blocked.is_empty():
		objective.status = STATUS_BLOCKED
	return objective


## A cost dictionary with only the known pools and positive amounts, so a
## planner cannot invent a resource the allocator would silently ignore.
static func _clean_cost(raw: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	for resource: String in RESOURCES:
		var amount: int = int(raw.get(resource, 0))
		if amount > 0:
			cost[resource] = amount
	return cost


func is_blocked() -> bool:
	return not blocked.is_empty()


func cost_of(resource: String) -> int:
	return int(cost.get(resource, 0))


func claim_of(resource: String) -> int:
	return int(claim.get(resource, 0))


func shortfall_of(resource: String) -> int:
	return int(shortfall.get(resource, 0))


## Total units of every pool the objective asks for; the trace's headline.
func total_cost() -> int:
	var total: int = 0
	for resource: String in cost.keys():
		total += int(cost[resource])
	return total


func to_dict() -> Dictionary:
	var kids: Array = []
	for child: AiObjective in children:
		kids.append(child.to_dict())
	return {
		"id": id,
		"domain": domain,
		"utility": utility,
		"cost": cost.duplicate(),
		"claim": claim.duplicate(),
		"status": status,
		"blocked": blocked,
		"rank": rank,
		"shortfall": shortfall.duplicate(),
		"children": kids,
	}


static func from_dict(data: Dictionary) -> AiObjective:
	var objective := AiObjective.new()
	objective.id = String(data.get("id", ""))
	objective.domain = String(data.get("domain", ""))
	objective.utility = clampi(int(data.get("utility", 0)), 0, 100)
	objective.cost = _clean_cost(_dictionary(data.get("cost", {})))
	objective.claim = _clean_cost(_dictionary(data.get("claim", {})))
	objective.status = String(data.get("status", STATUS_RANKED))
	objective.blocked = String(data.get("blocked", ""))
	objective.rank = int(data.get("rank", 0))
	objective.shortfall = _clean_cost(_dictionary(data.get("shortfall", {})))
	for raw: Variant in _array(data.get("children", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			objective.children.append(from_dict(raw))
	return objective


static func _dictionary(raw: Variant) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func _array(raw: Variant) -> Array:
	return raw if typeof(raw) == TYPE_ARRAY else []
