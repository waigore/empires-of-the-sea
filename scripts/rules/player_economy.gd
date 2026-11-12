class_name PlayerEconomy
extends RefCounted
## One Great Power's economy: central stockpile, treasury, worker pool and the
## production assignment for the next turn (wiki: stockpiles-and-production).
## Storage is unbounded by design, so quantities are plain non-negative integers.

## Starting conditions (ruleset-config § Starting stockpiles; treasury is the
## slice's starting purse). Grain is seeded from peasants x turns of food. The
## manufactured lines also fund the opening civilian work orders (improvements,
## roads, training), which used to be a separate demo stockpile.
const START_TREASURY: int = 2500
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
## Researched techs; the research state owns the table so there is one truth.
var tech_unlocked: Dictionary:
	get:
		return research.unlocked
	set(value):
		research.unlocked = value
var _assignments: Array[Dictionary] = []
## Workshop carried between turns: recipe id -> array of batches
## {"units", "turns_left"} still serving their turns (DR-20261112-11). Inputs and
## labour were paid when each batch started; only the output is outstanding.
var production_wip: Dictionary = {}


static func starting() -> PlayerEconomy:
	var econ := PlayerEconomy.new()
	econ.treasury = START_TREASURY
	econ.workers = WorkerPool.make(START_PEASANTS)
	econ.research = ResearchState.make()
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
	for value: Variant in stockpile.values():
		total += int(value)
	return total


func add_treasury(amount: int) -> void:
	treasury += amount


func spend_treasury(amount: int) -> bool:
	if amount < 0 or treasury < amount:
		return false
	treasury -= amount
	return true


# --- production assignment ---------------------------------------------------


func assignment_units(recipe_id: String) -> int:
	for entry: Dictionary in _assignments:
		if String(entry.get("recipe", "")) == recipe_id:
			return int(entry.get("units", 0))
	return 0


## Desired output units for the next Production phase; 0 or less clears the row.
func set_assignment(recipe_id: String, units: int) -> void:
	if not ProductionRecipes.known(recipe_id):
		return
	for index in _assignments.size():
		if String(_assignments[index].get("recipe", "")) == recipe_id:
			if units <= 0:
				_assignments.remove_at(index)
			else:
				_assignments[index] = {"recipe": recipe_id, "units": units}
			return
	if units > 0:
		_assignments.append({"recipe": recipe_id, "units": units})


func assignments() -> Array[Dictionary]:
	return _assignments.duplicate(true)


func clear_assignments() -> void:
	_assignments.clear()


func assigned_labour() -> int:
	var total: int = 0
	for entry: Dictionary in _assignments:
		var recipe_id: String = String(entry.get("recipe", ""))
		total += int(entry.get("units", 0)) * ProductionRecipes.labour(recipe_id)
	return total


# --- workshop ----------------------------------------------------------------


## Units of this recipe started on an earlier turn whose output has not landed.
func wip_units(recipe_id: String) -> int:
	return ProductionRecipes.in_flight(production_wip, recipe_id)


## Phases the oldest batch of this recipe still has to serve; 0 when idle.
func wip_turns(recipe_id: String) -> int:
	var most: int = 0
	for raw: Variant in (production_wip.get(recipe_id, []) as Array):
		if typeof(raw) == TYPE_DICTIONARY:
			most = maxi(most, int((raw as Dictionary).get("turns_left", 0)))
	return most


func wip_total() -> int:
	var total: int = 0
	for recipe_id: Variant in production_wip.keys():
		total += ProductionRecipes.in_flight(production_wip, String(recipe_id))
	return total


# --- workers -----------------------------------------------------------------


## Peasants not yet committed to a trained-tier conversion this phase.
func available_peasants() -> int:
	return workers.count(WorkerPool.Tier.PEASANT)


## Empty string when the recruit/train row is payable; otherwise the wiki reason.
func recruit_blocked_reason(tier: int) -> String:
	if tier < 0 or tier >= WorkerPool.TIER_COUNT:
		return "Unknown worker tier"
	if not WorkerPool.techs_unlocked(tier, tech_unlocked):
		return "Required technology not unlocked"
	if WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier] and available_peasants() < 1:
		return "Insufficient workers"
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	if treasury < int(cost.get("treasury", 0)):
		return "Insufficient treasury"
	var materials: Dictionary = cost.get("materials", {})
	for commodity: Variant in materials.keys():
		if quantity(String(commodity)) < int(materials[commodity]):
			return "Insufficient materials"
	return ""


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
	clone._assignments = _assignments.duplicate(true)
	clone.production_wip = production_wip.duplicate(true)
	return clone


## Plain data for local saves: ledger, labour pool, research and assignments.
func snapshot() -> Dictionary:
	return {
		"treasury": treasury,
		"stockpile": stockpile.duplicate(),
		"workers": workers.counts.duplicate(),
		"navy_feeding": navy_feeding,
		"research": {
			"unlocked": research.unlocked.duplicate(),
			"progress": research.progress.duplicate(),
			"slots": research.slots.duplicate(true),
			"revealed": research.revealed.duplicate(),
			"goal": research.goal,
		},
		"assignments": _assignments.duplicate(true),
		"production_wip": production_wip.duplicate(true),
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
	var research_data: Variant = data.get("research", {})
	if typeof(research_data) == TYPE_DICTIONARY:
		_apply_research(research_data)
	_assignments.clear()
	for raw: Variant in data.get("assignments", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var recipe_id: String = String(entry.get("recipe", ""))
		var units: int = int(entry.get("units", 0))
		if not recipe_id.is_empty() and units > 0:
			_assignments.append({"recipe": recipe_id, "units": units})
	production_wip = _read_wip(data.get("production_wip", {}))


## The workshop a save carries; a recipe the catalogue no longer knows, a batch
## with no units, or a batch already served is dropped rather than trusted.
func _read_wip(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for raw_recipe: Variant in (data as Dictionary).keys():
		var recipe_id: String = String(raw_recipe)
		if not ProductionRecipes.known(recipe_id):
			continue
		var batches: Array = []
		for raw_batch: Variant in ((data as Dictionary)[raw_recipe] as Array):
			if typeof(raw_batch) != TYPE_DICTIONARY:
				continue
			var batch: Dictionary = raw_batch
			var units: int = int(batch.get("units", 0))
			var turns_left: int = int(batch.get("turns_left", 0))
			if units <= 0 or turns_left <= 0:
				continue
			batches.append({"units": units, "turns_left": turns_left})
		if not batches.is_empty():
			out[recipe_id] = batches
	return out


## Research, slots included, is restored by ResearchSlots: it drops entries the
## catalog or the roster cannot hold and forfeits progress no slot binds
## (wiki: research-state § Slot Occupancy Persistence).
func _apply_research(data: Dictionary) -> void:
	research = ResearchState.new()
	ResearchSlots.restore(research, data)
