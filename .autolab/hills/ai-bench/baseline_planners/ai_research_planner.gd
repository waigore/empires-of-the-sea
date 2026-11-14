class_name MainlineAiResearchPlanner
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


## Assignments for the court's empty slots plus every scored candidate, for the
## turn trace (wiki: turn-trace-interpretation).
##
## `context["treasury_floor"]` is the purse the court must leave behind — its own
## cash floor, raised to the muster it is saving for (`MainlineAiArmyReinforce.
## muster_floor`). Funding steps down to what the purse can carry after that
## floor, so a court short of its regiment target saves for the muster instead of
## paying its last coins into a study (wiki: growth-stage-planner
## § Recruitment modulation; treasury-planner § Cash discipline).
static func plan(
	config: MainlineAiConfig, economy: PlayerEconomy, context: Dictionary = {}
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
	var preset: String = funding_for(
		config, economy, maxi(int(context.get("treasury_floor", 0)), 0)
	)
	# A study already underway follows the same purse: a court that cannot fund
	# its slots at the published preset pays a cheaper one rather than draining
	# the war chest or stalling with unpaid rows.
	for slot in state.slots.size():
		if state.tech_at(slot).is_empty():
			continue
		if state.funding_at(slot) != preset:
			state.set_funding(slot, preset)
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
			var result: Dictionary = state.assign(tech, preset, slot)
			if not bool(result.get("ok", false)):
				entry["taken"] = true
				continue
			pick = {
				"tech": tech,
				"slot": slot,
				"funding": preset,
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
## cash floor and its muster). A court that cannot pay the cheapest preset funds
## nothing that turn and keeps saving (wiki: treasury-planner § Cash discipline).
static func funding_for(
	config: MainlineAiConfig, economy: PlayerEconomy = null, floor: int = 0
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


# --- candidate scoring -------------------------------------------------------


static func _scored_candidates(
	config: MainlineAiConfig, economy: PlayerEconomy, at_war: bool
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
	config: MainlineAiConfig, economy: PlayerEconomy, tech_id: String, at_war: bool
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
	config: MainlineAiConfig, economy: PlayerEconomy, tech_id: String
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