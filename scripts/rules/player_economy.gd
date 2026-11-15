class_name PlayerEconomy
extends RefCounted
## One Great Power's economy: central stockpile, treasury, worker pool and the
## production board for the next turn (wiki: stockpiles-and-production).
## Storage is unbounded by design, so quantities are plain non-negative integers.
## Assignments and workshop WIP live on [ProductionPlan] so this bag stays
## ledger + labour under the P3 size bar (REQ-P3-01).

## Starting conditions (ruleset-config § Starting stockpiles; treasury is the
## slice's starting purse). Grain is seeded from peasants x turns of food. The
## manufactured lines also fund the opening civilian work orders (improvements,
## roads, training), which used to be a separate demo stockpile.
## The seed capital the income chain needs: the college trains, explorers survey
## and prospect, builders open mines and roads while the purse still exists
## (wiki: ruleset-config § Starting stockpiles; #676).
const START_TREASURY: int = 20000
const START_PEASANTS: int = 6
const START_GRAIN_TURNS: int = 20
## Materials the opening civilian work orders (improvements, roads, training)
## draw on; these were a separate demo stockpile before the economy landed.
const START_WORKS_LUMBER: int = 40
const START_WORKS_CAST_IRON: int = 40
## Cloth for the opening muster and worker training; regiments need fabric.
const START_WORKS_FABRIC: int = 12
const START_CIVILIAN_WORKS: Dictionary = {
	"bronze": 12,
	"steel": 8,
	"paper": 8,
}

var treasury: int = 0
var stockpile: Dictionary = {}
var workers: WorkerPool = WorkerPool.new()
## Share of last turn's hulls the granary fed in full (0..1); the next sea
## battle scales this crown's strength by it (wiki: workers-and-population
## § Consumption). Full rations until the first Consumption.
var navy_feeding: float = 1.0
## Slots, funding and progress for the Research phase (wiki: research-state).
var research: ResearchState = ResearchState.new()
## Next-phase assignment and workshop batches still in flight.
var production: ProductionPlan = ProductionPlan.new()
## Recruit / muster / launch / hire orders placed this Orders phase; Build/work
## resolves them one turn later (wiki: workers-and-population § Phase placement).
var recruits: RecruitQueue = RecruitQueue.new()
## Hull types this crown has flown — craft the yard may rebuild without the
## unlocking tech even after the last of that type is lost (issue #484).
var shipcraft: Array[String] = []
## Researched techs; the research state owns the table so there is one truth.
var tech_unlocked: Dictionary:
	get:
		return research.unlocked
	set(value):
		research.unlocked = value
## Workshop dictionary kept under this name for turn/fixture readers; the plan
## owns the store.
var production_wip: Dictionary:
	get:
		return production.wip
	set(value):
		production.wip = value


static func starting() -> PlayerEconomy:
	var econ := PlayerEconomy.new()
	econ.treasury = START_TREASURY
	econ.workers = WorkerPool.make(START_PEASANTS)
	econ.research = ResearchState.make()
	econ.production = ProductionPlan.new()
	econ.stockpile = {
		"grain": START_PEASANTS * START_GRAIN_TURNS,
		"lumber": START_WORKS_LUMBER,
		"castIron": START_WORKS_CAST_IRON,
		"fabric": START_WORKS_FABRIC,
		"wool": 4,
		"paper": int(START_CIVILIAN_WORKS["paper"]),
		"bronze": int(START_CIVILIAN_WORKS["bronze"]),
		"steel": int(START_CIVILIAN_WORKS["steel"]),
	}
	return econ


func quantity(id: String) -> int:
	return int(stockpile.get(id, 0))


func add(id: String, amount: int) -> int:
	if amount > 0:
		stockpile[id] = quantity(id) + amount
	return quantity(id)


## Removes up to amount; false when the stockpile could not cover all of it.
func take(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var have: int = quantity(id)
	if have < amount:
		return false
	stockpile[id] = have - amount
	return true


func total_units() -> int:
	var total: int = 0
	for key: Variant in stockpile.keys():
		total += int(stockpile[key])
	return total


func add_treasury(amount: int) -> void:
	if amount > 0:
		treasury += amount


func spend_treasury(amount: int) -> bool:
	if amount <= 0:
		return true
	if treasury < amount:
		return false
	treasury -= amount
	return true


## Remembers hull types currently afloat so a lost last sloop can still be laid
## without Navigation. Flying any warship also teaches the sloop rebuild so a
## lost frigate is not a 10,500-ducat dead end (issue #484).
func note_shipcraft(types: Array) -> void:
	var saw_warship: bool = false
	for raw: Variant in types:
		var type_id: String = ShipStats.normalize(String(raw))
		if type_id.is_empty():
			continue
		if ShipStats.is_warship(type_id):
			saw_warship = true
		if not shipcraft.has(type_id):
			shipcraft.append(type_id)
	if saw_warship and not shipcraft.has("sloop"):
		shipcraft.append("sloop")


# --- workers -----------------------------------------------------------------


## Peasants not yet committed to a trained-tier conversion or a build this
## phase. Orders already queued keep their peasant reserved, so a second order
## can never promise the same one (wiki: workers-and-population
## § Peasant reservation).
func available_peasants() -> int:
	return maxi(workers.count(WorkerPool.Tier.PEASANT) - recruits.reserved_peasants(), 0)


## Peasants waiting orders have promised to the next Build/work (labour the pool
## still shows but cannot be recruited twice).
func reserved_peasants() -> int:
	return recruits.reserved_peasants()


## Empty string when the recruit/train row is payable; otherwise the wiki reason.
## One head is payable exactly when the batch limit allows one, so the row and
## the batch read the same rule (REQ-P2-03).
func recruit_blocked_reason(tier: int) -> String:
	var limit: Dictionary = _recruit_limit(tier)
	if int(limit["limit"]) > 0:
		return ""
	return String(limit["reason"])


## Recruit or train one worker of the target tier (wiki: workers-and-population).
func recruit(tier: int) -> Dictionary:
	var reason: String = recruit_blocked_reason(tier)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	treasury -= int(cost.get("treasury", 0))
	var materials: Dictionary = cost.get("materials", {})
	for commodity: Variant in materials.keys():
		stockpile[String(commodity)] = quantity(String(commodity)) - int(materials[commodity])
	if WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier]:
		workers.remove(WorkerPool.Tier.PEASANT)
	workers.add(tier, 1)
	return {"ok": true, "reason": ""}


## How many workers of this tier the crown could queue right now: the tightest
## of the free peasants, the treasury and the materials the cost row asks per
## head (wiki: workers-and-population § Recruiting, § Peasant reservation). 0
## when the tier's tech is locked or the row is not payable at all.
func recruit_affordable(tier: int) -> int:
	return int(_recruit_limit(tier)["limit"])


## The tightest limit on a batch of this tier and the wiki reason it binds, so
## the ledger can name why a batch stopped short (REQ-P5-05). The order of the
## checks is `recruit_blocked_reason`'s own: tech, peasants, treasury, materials.
func _recruit_limit(tier: int) -> Dictionary:
	if tier < 0 or tier >= WorkerPool.TIER_COUNT:
		return {"limit": 0, "reason": "Unknown worker tier"}
	if not WorkerPool.techs_unlocked(tier, tech_unlocked):
		return {"limit": 0, "reason": "Required technology not unlocked"}
	var limit: int = 1 << 30
	var reason: String = ""
	if WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier]:
		var free: int = available_peasants()
		if free < limit:
			limit = free
			reason = "Insufficient workers"
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var gold: int = int(cost.get("treasury", 0))
	if gold > 0:
		var by_gold: int = treasury / gold
		if by_gold < limit:
			limit = by_gold
			reason = "Insufficient treasury"
	var materials: Dictionary = cost.get("materials", {})
	for commodity: Variant in materials.keys():
		var per: int = int(materials[commodity])
		if per <= 0:
			continue
		var by_stock: int = quantity(String(commodity)) / per
		if by_stock < limit:
			limit = by_stock
			reason = "Insufficient materials"
	return {"limit": maxi(limit, 0), "reason": reason}


## Queues up to `count` recruit / train orders, stopping at the first head the
## rules refuse (wiki: workers-and-population § Phase placement). Nothing is
## paid now: each order reserves its peasant and pays in Build/work, so a batch
## never promises a purse or a peasant the crown does not hold. Returns
## {ok, asked, queued, reason} — `reason` is why the batch stopped, empty when
## every order was filed.
func queue_recruit(tier: int, count: int = 1) -> Dictionary:
	var asked: int = maxi(count, 1)
	var limit: Dictionary = _recruit_limit(tier)
	var queued: int = mini(asked, int(limit["limit"]))
	for _index in queued:
		recruits.add(RecruitQueue.KIND_WORKER, str(tier))
	var reason: String = ""
	if queued < asked:
		reason = String(limit["reason"])
		if reason.is_empty():
			reason = "Recruit refused"
	return {"ok": queued > 0, "asked": asked, "queued": queued, "reason": reason}


## Queues a civilian hire, a regiment muster or a hull launch. The caller has
## already run that build's own gate, so this only files the order.
func queue_build(kind: String, key: String) -> void:
	recruits.add(kind, key)


## Empty string when one worker of this tier may be disbanded; otherwise the
## reason the control is inert. Trained tiers only, and only while the pool holds
## one (wiki: workers-and-population § Disband — strict demotion to peasant).
func disband_blocked_reason(tier: int) -> String:
	if tier <= WorkerPool.Tier.PEASANT or tier >= WorkerPool.TIER_COUNT:
		return "Only a trained worker returns to the fields"
	if workers.count(tier) < 1:
		return "No %s to send back" % WorkerPool.tier_one(tier).to_lower()
	return ""


## Demotion to peasant is immediate, pays no refund and skips no tiers.
func disband(tier: int) -> bool:
	if not disband_blocked_reason(tier).is_empty():
		return false
	workers.remove(tier)
	workers.add(WorkerPool.Tier.PEASANT, 1)
	return true


func copy() -> PlayerEconomy:
	var clone := PlayerEconomy.new()
	clone.treasury = treasury
	clone.stockpile = stockpile.duplicate()
	clone.workers = workers.copy()
	clone.navy_feeding = navy_feeding
	clone.research = research.copy()
	clone.production = production.copy()
	clone.recruits = recruits.copy()
	clone.shipcraft = shipcraft.duplicate()
	return clone


## Plain data for local saves: ledger, labour pool, research and assignments.
func snapshot() -> Dictionary:
	var plan: Dictionary = production.snapshot()
	return {
		"treasury": treasury,
		"stockpile": stockpile.duplicate(),
		"workers": workers.counts.duplicate(),
		"navy_feeding": navy_feeding,
		"shipcraft": shipcraft.duplicate(),
		"research": {
			"unlocked": research.unlocked.duplicate(),
			"progress": research.progress.duplicate(),
			"slots": research.slots.duplicate(true),
			"revealed": research.revealed.duplicate(),
			"goal": research.goal,
		},
		"assignments": plan["assignments"],
		"production_wip": plan["production_wip"],
		"production_made": plan["production_made"],
		"recruit_orders": recruits.snapshot(),
	}


## Replaces every field from a snapshot; safe on a freshly started economy.
func apply_snapshot(data: Dictionary) -> void:
	treasury = int(data.get("treasury", treasury))
	stockpile.clear()
	var saved_stock: Dictionary = data.get("stockpile", {})
	for key: Variant in saved_stock.keys():
		stockpile[String(key)] = int(saved_stock[key])
	var counts: Array = data.get("workers", [])
	for tier in WorkerPool.TIER_COUNT:
		workers.set_count(tier, int(counts[tier]) if tier < counts.size() else 0)
	navy_feeding = clampf(float(data.get("navy_feeding", 1.0)), 0.0, 1.0)
	shipcraft.clear()
	note_shipcraft(data.get("shipcraft", []) as Array)
	var research_data: Variant = data.get("research", {})
	if typeof(research_data) == TYPE_DICTIONARY:
		_apply_research(research_data)
	production = ProductionPlan.new()
	production.read_assignments(data.get("assignments", []))
	production.read_wip(data.get("production_wip", {}))
	production.read_made(data.get("production_made", {}))
	recruits = RecruitQueue.new()
	recruits.read(data.get("recruit_orders", []))


## Research, slots included, is restored by ResearchSlots: it drops entries the
## catalog or the roster cannot hold and forfeits progress no slot binds
## (wiki: research-state § Slot Occupancy Persistence).
func _apply_research(data: Dictionary) -> void:
	research = ResearchState.new()
	ResearchSlots.restore(research, data)
