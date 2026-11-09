class_name ResearchTurn
extends RefCounted
## The Research phase (wiki: tech-tree § Research Model; research-state). It
## runs after Production: every occupied slot pays its gold, earns research
## points and unlocks its tech the turn the cost is met.

const INDUSTRIAL_FUNDING: String = "industrial_funding_of_research"
const BONUS_CATEGORIES: Array[String] = ["military", "naval"]
const BONUS_PERCENT: int = 20


## Mutates `state` and `economy` (treasury) and reports what moved. A slot that
## cannot pay its full gold earns no points that turn — the wiki rules define no
## partial funding, so the ledger reports the slot as unpaid. `bonus_pct` maps a
## tech id to the additive spy-network percentage for that tech
## (wiki: research-state § Spy RP boost).
static func resolve(
	state: ResearchState, economy: PlayerEconomy, bonus_pct: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = {
		"slots": [] as Array[Dictionary],
		"researched": [] as Array[String],
		"unpaid": [] as Array[String],
		"spent": 0,
		"treasury": 0,
	}
	if state == null or economy == null:
		return report
	state.ensure_slots()
	var floor: int = state.treasury_floor()
	for index in state.slots.size():
		var row: Dictionary = _run_slot(state, economy, index, floor, bonus_pct)
		var rows: Array[Dictionary] = report["slots"]
		rows.append(row)
		report["spent"] = int(report["spent"]) + int(row["gold"])
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
	state: ResearchState, tech_id: String, funding: String, bonus_pct: int = 0
) -> int:
	return _spy_bonus(_bonus(state, tech_id, ResearchFunding.rp(funding)), bonus_pct)


static func _run_slot(
	state: ResearchState, economy: PlayerEconomy, index: int, floor: int,
	bonus_pct: Dictionary = {}
) -> Dictionary:
	var tech_id: String = state.tech_at(index)
	var funding: String = state.funding_at(index)
	var row: Dictionary = {
		"slot": index,
		"tech": tech_id,
		"funding": funding,
		"gold": 0,
		"rp": 0,
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
	var earned: int = points_for(
		state, tech_id, funding, int(bonus_pct.get(tech_id, 0))
	)
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
static func _bonus(state: ResearchState, tech_id: String, rp: int) -> int:
	if rp <= 0 or not state.is_unlocked(INDUSTRIAL_FUNDING):
		return rp
	if not BONUS_CATEGORIES.has(TechCatalog.category(tech_id)):
		return rp
	return int(floor(float(rp) * (1.0 + float(BONUS_PERCENT) / 100.0)))


## Spy network: additive percentage per observing rival Great Power, applied to
## the points the slot earned (wiki: research-state § Spy RP boost).
static func _spy_bonus(rp: int, bonus_pct: int) -> int:
	if rp <= 0 or bonus_pct <= 0:
		return rp
	return rp + int(floor(float(rp) * float(bonus_pct) / 100.0))
