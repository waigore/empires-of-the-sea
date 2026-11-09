class_name AiResearchPlanner
extends RefCounted
## Rival research policy (wiki: research-state, tech-tree § Research Model).
##
## A rival fills its free slots with the cheapest researchable tech, funded from
## its own treasury at a preset the court can carry. Rival exploration is not
## simulated, so the discovery gate is treated as open: the court is assumed to
## know the world's commodities. Pure rules: the economy is the only state and
## the map adapter calls it before EconomyTurn resolves the Research phase
## (REQ-P2-03, REQ-P3-03).

const FUNDING_HIGH: String = "high"
const FUNDING_MEDIUM: String = "medium"
const FUNDING_LOW: String = "low"
## Treasury needed before a court opens a new study; research never borrows.
const MEDIUM_FLOOR: int = 300
const LOW_FLOOR: int = 50


## Fills at most one free slot so a rival's research reads like the player's
## one-decision-per-turn ledger. Returns {ok, tech, funding, reason}.
static func plan(economy: PlayerEconomy, _config: AiConfig = null) -> Dictionary:
	if economy == null or economy.research == null:
		return _no("no ledger")
	var state: ResearchState = economy.research
	state.ensure_slots()
	_reveal_world(state)
	if state.free_slot() < 0:
		return _no("no free slot")
	var funding: String = funding_for(economy.treasury)
	if funding.is_empty():
		return _no("treasury too thin")
	var tech_id: String = next_tech(state)
	if tech_id.is_empty():
		return _no("nothing researchable")
	var result: Dictionary = state.assign(tech_id, funding, state.free_slot())
	if bool(result.get("ok", false)):
		result["tech"] = tech_id
		result["funding"] = funding
	return result


## Cheapest researchable tech, ties broken by id: deterministic per court state.
static func next_tech(state: ResearchState) -> String:
	var best: String = ""
	var best_cost: int = 1 << 30
	for tech_id: String in state.researchable():
		if state.is_active(tech_id):
			continue
		var cost: int = TechCatalog.cost(tech_id)
		if cost < best_cost or (cost == best_cost and tech_id < best):
			best = tech_id
			best_cost = cost
	return best


static func funding_for(treasury: int) -> String:
	if treasury >= MEDIUM_FLOOR:
		return FUNDING_MEDIUM
	if treasury >= LOW_FLOOR:
		return FUNDING_LOW
	return ""


## Rival courts are assumed to know every commodity: exploration is not part of
## their planner, and the discovery gate would otherwise stall research forever.
static func _reveal_world(state: ResearchState) -> void:
	var revealed: Dictionary = state.revealed.duplicate()
	for commodity: String in CommodityCatalog.all_ids():
		revealed[commodity] = true
	state.set_revealed(revealed)


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "tech": "", "funding": ""}
