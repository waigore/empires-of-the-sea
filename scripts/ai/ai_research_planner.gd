class_name AiResearchPlanner
extends RefCounted
## Full-AI research policy (wiki: ai-architecture § Research planner,
## research-state, tech-tree). Each rival court fills its own ResearchState
## slots through the shared rules, so the player and every AI read the same
## catalog and the same funding presets (REQ-P2-03, REQ-P3-03).
##
## Candidates score by the personality's domain weights mapped onto tech
## categories, by how short the court's stores are of the commodities that tech
## caps, and by a war bonus on the military and naval branches. Earlier eras win
## ties because they are cheaper; ids break the rest, so the same seeds always
## produce the same plan (wiki: ai-architecture § Seeding).
## Pure rules: state in, assignments out; the map adapter applies them.

## Tech category -> personality weight domain (wiki: ai-personalities § Domain
## weight vectors). The research weight shifts funding instead (funding_for).
const CATEGORY_DOMAIN: Dictionary = {
	"gathering": "economy",
	"labour": "economy",
	"transport": "economy",
	"new-world": "economy",
	"diplomatic": "diplomacy",
	"military": "military",
	"naval": "military",
}
const WAR_BRANCHES: Array[String] = ["military", "naval"]
const SCORE_PER_WEIGHT: int = 10
## The cheapest preset a court can pay; a court parked at its cash floor keeps
## one study alive at this rate rather than standing still (issue #490).
const STANDING_FUNDING: String = "low"


## Assignments for the court's empty slots plus every scored candidate, for the
## turn trace (wiki: turn-trace-interpretation).
##
## `context["treasury_floor"]` is the money-goal reserve the surplus ladder must
## leave behind (muster at war, cash floor at peace). `context["cash_floor"]` is
## the court's own `economy.min_treasury` for the standing study: when the ladder
## would fund `none` against the reserve, one slot still pays the cheapest
## preset if the purse clears half that cash floor — otherwise war-time courts
## parked at 500 while saving 2,400 never learn (issue #490). Defaults:
## `cash_floor` falls back to `treasury_floor`, then to `research_floor(config)`.
static func plan(
	config: AiConfig, economy: PlayerEconomy, context: Dictionary = {}
) -> Dictionary:
	var assignments: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or economy == null or economy.research == null:
		return {"assignments": assignments, "candidates": candidates}
	var state: ResearchState = economy.research
	state.ensure_slots()
	# The caller's chart tells a court which commodities it has actually seen;
	# discovery techs stay shut until then (wiki: tech-tree § Discovery).
	var revealed: Variant = context.get("revealed", null)
	if typeof(revealed) == TYPE_DICTIONARY:
		state.set_revealed(revealed)
	var at_war: bool = bool(context.get("at_war", false))
	candidates = _scored_candidates(config, economy, at_war)
	var save_floor: int = maxi(int(context.get("treasury_floor", 0)), 0)
	# Standing study affordability is always the cash floor, never the muster.
	var cash_floor: int = maxi(int(context.get("cash_floor", research_floor(config))), 0)
	var preset: String = funding_for(config, economy, save_floor)
	# A court that cannot clear the money-goal reserve still keeps one study
	# alive at the cheapest preset when the purse clears half its cash floor:
	# the standing study is the first slot that already holds a tech, or the
	# first slot filled this turn (issue #490).
	var can_stand: bool = (
		preset == ResearchFunding.ORDER[0] and _can_pay_standing(economy, cash_floor)
	)
	var standing: int = _standing_slot(state) if can_stand else -1
	# A study already underway follows the same purse: a court that cannot fund
	# its slots at the published preset pays a cheaper one rather than draining
	# the war chest or stalling with unpaid rows.
	for slot in state.slots.size():
		if state.tech_at(slot).is_empty():
			continue
		var funding: String = STANDING_FUNDING if slot == standing else preset
		if state.funding_at(slot) != funding:
			state.set_funding(slot, funding)
	for slot in state.slots.size():
		if not state.tech_at(slot).is_empty():
			continue
		var pick: Dictionary = {}
		for entry: Dictionary in candidates:
			if bool(entry.get("taken", false)):
				continue
			var tech: String = String(entry["tech"])
			if state.is_active(tech):
				entry["taken"] = true
				continue
			var wants_standing: bool = standing < 0 and can_stand
			var slot_funding: String = (
				STANDING_FUNDING if slot == standing or wants_standing else preset
			)
			var result: Dictionary = state.assign(tech, slot_funding, slot)
			if not bool(result.get("ok", false)):
				entry["taken"] = true
				continue
			if wants_standing:
				standing = slot
			pick = {
				"tech": tech,
				"slot": slot,
				"funding": slot_funding,
				"score": int(entry["score"]),
			}
			entry["taken"] = true
			break
		if not pick.is_empty():
			assignments.append(pick)
	for entry: Dictionary in candidates:
		entry.erase("taken")
	return {"assignments": assignments, "candidates": candidates}


## The preset a court pays each slot: `research.funding_index` shifted by the
## personality's research weight (3 pays one step up, 1 one step down) and by the
## agenda's own catch-up step (wiki: research-state § Funding presets;
## ai-personalities § Domain weight vectors; hidden-agendas — tech_thief pays for
## its catch-up, DR-20261111-27), clamped to the catalogue and then to what the
## purse can carry after `floor` — the reserve the court must not spend (its own
## cash floor; the muster reserve is the army planner's, not research's). A court
## that cannot pay the cheapest preset funds nothing that turn and keeps saving;
## one that can still keeps its standing study alive at that preset (`plan`).
static func funding_for(
	config: AiConfig, economy: PlayerEconomy = null, floor: int = 0
) -> String:
	var shift: int = int(config.weights().get("research", 2)) - 2
	var index: int = clampi(
		config.parameter("research.funding_index") + shift + config.research_bias(),
		0, ResearchFunding.ORDER.size() - 1
	)
	if economy != null:
		var spare: int = economy.treasury - maxi(floor, 0)
		while index > 0 and ResearchFunding.gold(ResearchFunding.ORDER[index]) > spare:
			index -= 1
	return ResearchFunding.ORDER[index]


## The purse research must leave behind: the court's own cash floor, never the
## muster reserve. The reserve is a saving target the army planner enforces at
## muster time; gating studies on it froze every court at war for the whole
## campaign (issue #490).
static func research_floor(config: AiConfig) -> int:
	if config == null:
		return 0
	return maxi(int(config.parameter("economy.min_treasury")), 0)


## The standing study's preset this turn, or "" when the court pays its surplus
## preset instead. Public so the objective ledger prices the same study the
## planner funds (issue #491 T1 reads this planner, it does not spend).
static func standing_funding(
	config: AiConfig, economy: PlayerEconomy
) -> String:
	var floor: int = research_floor(config)
	if funding_for(config, economy, floor) != ResearchFunding.ORDER[0]:
		return ""
	return STANDING_FUNDING if _can_pay_standing(economy, floor) else ""


## The slot that keeps the standing study: the first slot already holding a
## tech, or -1 when every slot is free (the first assignment takes it).
static func _standing_slot(state: ResearchState) -> int:
	for slot in state.slots.size():
		if not state.tech_at(slot).is_empty():
			return slot
	return -1


## True when the purse can pay the cheapest preset while still keeping half the
## court's cash floor: the standing study may dip below that floor (the research
## phase's own floor is 0; the cash floor is a saving policy, not a legality
## gate) but never below half of it, so a broke court keeps a reserve.
static func _can_pay_standing(economy: PlayerEconomy, floor: int) -> bool:
	if economy == null:
		return false
	var keep: int = maxi(floor / 2, 0)
	return economy.treasury >= keep + ResearchFunding.gold(STANDING_FUNDING)


# --- candidate scoring -------------------------------------------------------


static func _scored_candidates(
	config: AiConfig, economy: PlayerEconomy, at_war: bool
) -> Array[Dictionary]:
	var research: ResearchState = economy.research
	var rows: Array[Dictionary] = []
	for tech_id: String in research.researchable():
		if not _can_teach(tech_id, economy.tech_unlocked):
			continue
		rows.append({
			"tech": tech_id,
			"category": TechCatalog.category(tech_id),
			"era": TechCatalog.era(tech_id),
			"score": score_for(config, economy, tech_id, at_war),
		})
	rows.sort_custom(_better)
	return rows


## One candidate's score: domain weight, then what the court is short of.
static func score_for(
	config: AiConfig, economy: PlayerEconomy, tech_id: String, at_war: bool
) -> int:
	var weights: Dictionary = config.weights()
	var category: String = TechCatalog.category(tech_id)
	var domain: String = String(CATEGORY_DOMAIN.get(category, "research"))
	var score: int = int(weights.get(domain, 1)) * SCORE_PER_WEIGHT
	score += int(weights.get("research", 1))
	score += _shortfall(config, economy, tech_id) * config.parameter("research.need_weight")
	if at_war and WAR_BRANCHES.has(category):
		score += config.parameter("research.war_bonus")
	return score


## Total store shortfall across the commodities this tech lifts the cap on,
## capped so one deep deficit does not drown every other signal.
static func _shortfall(
	config: AiConfig, economy: PlayerEconomy, tech_id: String
) -> int:
	var target: int = config.parameter("economy.reserve_target")
	var total: int = 0
	var caps: Dictionary = TechCatalog.caps_of(tech_id)
	for raw: Variant in caps.keys():
		var commodity: String = String(raw)
		total += maxi(target - economy.quantity(commodity), 0)
	return mini(total, 10)


## True when at least one commodity the tech caps is still below that ceiling
## for this court; techs with no caps (gates, slots, unlocks) always teach.
static func _can_teach(tech_id: String, unlocked: Dictionary) -> bool:
	var caps: Dictionary = TechCatalog.caps_of(tech_id)
	if caps.is_empty():
		return true
	for raw: Variant in caps.keys():
		var commodity: String = String(raw)
		if TechCatalog.cap_for(commodity, unlocked) < int(caps[raw]):
			return true
	return false


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	if int(a["era"]) != int(b["era"]):
		return int(a["era"]) < int(b["era"])
	return String(a["tech"]) < String(b["tech"])
