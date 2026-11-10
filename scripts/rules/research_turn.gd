class_name ResearchTurn
extends RefCounted
## The Research phase (wiki: tech-tree § Research Model; research-state). It
## runs after Production: every occupied slot pays its gold, earns research
## points and unlocks its tech the turn the cost is met.
##
## Two percentage bonuses can lift a slot's points: Industrial Funding of
## Research (+20% on the military and naval branches) and a spy network posted in
## a rival Great Power's province (+15% per rival that already knows the tech;
## wiki: civilian-units § Spy; DR-20261110-03). Percentages add, then the sum is
## floored once, so the two rules never compound into a third figure.

const INDUSTRIAL_FUNDING: String = "industrial_funding_of_research"
const BONUS_CATEGORIES: Array[String] = ["military", "naval"]
const BONUS_PERCENT: int = 20


## Mutates `state` and `economy` (treasury) and reports what moved. `boost` maps
## tech id -> spy-network percent; it only lifts a slot funded at Low or better.
## A slot that cannot pay its full gold earns no points that turn — the wiki
## rules define no partial funding, so the ledger reports the slot as unpaid.
static func resolve(
	state: ResearchState, economy: PlayerEconomy, boost: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = {
		"slots": [] as Array[Dictionary],
		"researched": [] as Array[String],
		"unpaid": [] as Array[String],
		"boosted": [] as Array[Dictionary],
		"spent": 0,
		"treasury": 0,
	}
	if state == null or economy == null:
		return report
	state.ensure_slots()
	var floor: int = state.treasury_floor()
	for index in state.slots.size():
		var row: Dictionary = _run_slot(state, economy, index, floor, boost)
		var rows: Array[Dictionary] = report["slots"]
		rows.append(row)
		report["spent"] = int(report["spent"]) + int(row["gold"])
		if int(row["boost"]) > 0:
			var lifted: Array[Dictionary] = report["boosted"]
			lifted.append({"tech": String(row["tech"]), "percent": int(row["boost"])})
		if bool(row["completed"]):
			var done: Array[String] = report["researched"]
			done.append(String(row["tech"]))
		if not bool(row["paid"]):
			var unpaid: Array[String] = report["unpaid"]
			unpaid.append(String(row["tech"]))
	report["treasury"] = economy.treasury
	report["unlocked"] = state.unlocked_ids()
	return report


## Research points a slot would earn at its preset, bonuses included.
static func points_for(
	state: ResearchState, tech_id: String, funding: String, spy_percent: int = 0
) -> int:
	return _bonus(state, tech_id, ResearchFunding.rp(funding), spy_percent)


## True when the preset earns points at all; the wiki gates spy gains at Low.
static func funds_research(funding: String) -> bool:
	var low: int = ResearchFunding.ORDER.find("low")
	return low >= 0 and ResearchFunding.ORDER.find(funding) >= low


static func _run_slot(
	state: ResearchState,
	economy: PlayerEconomy,
	index: int,
	floor: int,
	boost: Dictionary
) -> Dictionary:
	var tech_id: String = state.tech_at(index)
	var funding: String = state.funding_at(index)
	var row: Dictionary = {
		"slot": index,
		"tech": tech_id,
		"funding": funding,
		"gold": 0,
		"rp": 0,
		"boost": 0,
		"progress": state.progress_of(tech_id),
		"cost": 0,
		"paid": true,
		"completed": false,
	}
	if tech_id.is_empty():
		return row
	row["cost"] = TechCatalog.cost(tech_id)
	var gold: int = ResearchFunding.gold(funding)
	if gold > 0 and economy.treasury - floor < gold:
		row["paid"] = false
		return row
	if gold > 0:
		economy.treasury -= gold
		row["gold"] = gold
	var spy_percent: int = 0
	if funds_research(funding):
		spy_percent = SpyNetworks.boost_for(boost, tech_id)
	row["boost"] = spy_percent
	var earned: int = points_for(state, tech_id, funding, spy_percent)
	row["rp"] = earned
	var total: int = state.add_progress(tech_id, earned)
	if total >= int(row["cost"]):
		state.unlock(tech_id)
		row["completed"] = true
		row["progress"] = int(row["cost"])
	else:
		row["progress"] = total
	return row


## Industrial Funding of Research: +20% (floored) on military and naval techs.
## A spy network's share adds to that percent before the single flooring.
static func _bonus(
	state: ResearchState, tech_id: String, rp: int, spy_percent: int = 0
) -> int:
	if rp <= 0:
		return rp
	var percent: int = maxi(spy_percent, 0)
	if (
		state.is_unlocked(INDUSTRIAL_FUNDING)
		and BONUS_CATEGORIES.has(TechCatalog.category(tech_id))
	):
		percent += BONUS_PERCENT
	if percent <= 0:
		return rp
	# Whole-point shares first, so 15% of 100 is 15 and never 14 on a float edge.
	return rp + int(floor(float(rp) * float(percent) / 100.0))
