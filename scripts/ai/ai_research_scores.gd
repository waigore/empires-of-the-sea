class_name AiResearchScores
extends RefCounted
## How a rival court ranks the studies its college can open (wiki:
## ai-architecture § Research planner, research-state, tech-tree). The planner
## (`AiResearchPlanner`) asks this home to rank the college's studies and to
## score one tech; the scoring needs no slots and no purse (REQ-P3-01,
## REQ-P3-03).
##
## Candidates score by the personality's domain weights mapped onto tech
## categories, by how short the court's stores are of the commodities that tech
## caps, and by a war bonus on the military and naval branches. Earlier eras win
## ties because they are cheaper; ids break the rest, so the same seeds always
## produce the same plan (wiki: ai-architecture § Seeding).
## Pure rules: state in, rows out.

## Tech category -> personality weight domain (wiki: ai-personalities § Domain
## weight vectors). The research weight shifts funding instead
## (`AiResearchPurse.funding_for`).
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


## Every study the court could open, best first, with the trace's row shape
## (tech, category, era, score). The door's study is lifted to the head when the
## context names it: a chain with a charted Tribe is only as open as its next
## stage, so the study that stage needs is taken first — a court that opened an
## envoy chain and never studies its next door has paid for a stake it cannot
## reach (DR-20261114-05).
##
## `harvest` is the court's harvest slack (issue #1516): a land that cannot
## carry another mouth scores its ration caps as if the store were short, so a
## court buying its dinner every turn still studies the farms that would grow
## it. `-2` is the no-reading sentinel and changes nothing.
static func candidates(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, door: String = "",
	harvest: int = 0
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tech_id: String in _open(economy, {}):
		rows.append(row(config, economy, tech_id, at_war, harvest))
	rows.sort_custom(_better)
	if door.is_empty():
		return rows
	var head: int = _index_of(rows, door)
	if head > 0:
		var entry: Dictionary = rows[head]
		rows.remove_at(head)
		rows.insert(0, entry)
	return rows


## The best candidate the court can still take, or an empty row when every
## study is under way. `taken` is the planner's own book of rows it has walked
## past this turn, and the door's study is the planner's first ask: a door the
## court can still take is the gate and outranks every score (issue #484), so
## the pick loop never ranks the whole college for it.
static func pick(
	config: AiConfig,
	economy: PlayerEconomy,
	at_war: bool,
	door: String = "",
	taken: Dictionary = {},
	harvest: int = 0
) -> Dictionary:
	if not door.is_empty() and not taken.has(door):
		if can_teach(door, economy.tech_unlocked):
			return row(config, economy, door, at_war, harvest)
	var best: Dictionary = {}
	var best_rank: Array = []
	for tech_id: String in _open(economy, taken):
		var entry: Dictionary = row(config, economy, tech_id, at_war, harvest)
		if not best_rank.is_empty() and _rank(entry) >= best_rank:
			continue
		best = entry
		best_rank = _rank(entry)
	return best


## One candidate in the trace's row shape: the tech, its category and era, and
## its score (`score_for`).
static func row(
	config: AiConfig, economy: PlayerEconomy, tech_id: String, at_war: bool,
	harvest: int = 0
) -> Dictionary:
	return {
		"tech": tech_id,
		"category": TechCatalog.category(tech_id),
		"era": TechCatalog.era(tech_id),
		"score": score_for(config, economy, tech_id, at_war, harvest),
	}


## One candidate's score: domain weight, then what the court is short of.
static func score_for(
	config: AiConfig, economy: PlayerEconomy, tech_id: String, at_war: bool,
	harvest: int = 0
) -> int:
	var weights: Dictionary = config.weights()
	var category: String = TechCatalog.category(tech_id)
	var domain: String = String(CATEGORY_DOMAIN.get(category, "research"))
	var score: int = int(weights.get(domain, 1)) * SCORE_PER_WEIGHT
	score += int(weights.get("research", 1))
	score += _shortfall(config, economy, tech_id, harvest) \
		* config.parameter("research.need_weight")
	if at_war and WAR_BRANCHES.has(category):
		score += config.parameter("research.war_bonus")
	return score


## True when at least one commodity the tech caps is still below that ceiling
## for this court; techs with no caps (gates, slots, unlocks) always teach.
static func can_teach(tech_id: String, unlocked: Dictionary) -> bool:
	var caps: Dictionary = TechCatalog.caps_of(tech_id)
	if caps.is_empty():
		return true
	for raw: Variant in caps.keys():
		var commodity: String = String(raw)
		if TechCatalog.cap_for(commodity, unlocked) < int(caps[raw]):
			return true
	return false


## The college's open studies the court has not started yet.
static func _open(economy: PlayerEconomy, taken: Dictionary) -> Array[String]:
	var open: Array[String] = []
	for tech_id: String in economy.research.researchable():
		if taken.has(tech_id):
			continue
		if can_teach(tech_id, economy.tech_unlocked):
			open.append(tech_id)
	return open


## The row of `tech` in a ranked list, or -1.
static func _index_of(rows: Array[Dictionary], tech: String) -> int:
	for index in rows.size():
		if String(rows[index]["tech"]) == tech:
			return index
	return -1


## Total store shortfall across the commodities this tech lifts the cap on,
## capped so one deep deficit does not drown every other signal.
##
## A ration commodity carries the land's own deficit too (issue #1516): a court
## whose granary is full of market grain, and whose land still lands too little
## to feed its mouths, is short of the cap that would let the farms grow — so
## the reading is the larger of the store's and the harvest's (`harvest` is the
## slack, `-2` the no-reading sentinel).
static func _shortfall(
	config: AiConfig, economy: PlayerEconomy, tech_id: String, harvest: int = 0
) -> int:
	var target: int = config.parameter("economy.reserve_target")
	var total: int = 0
	var land: int = maxi(-harvest, 0) if harvest != -2 else 0
	var caps: Dictionary = TechCatalog.caps_of(tech_id)
	for raw: Variant in caps.keys():
		var commodity: String = String(raw)
		var short: int = maxi(target - economy.quantity(commodity), 0)
		if AiResearchRation.RATION_COMMODITIES.has(commodity):
			short = maxi(short, land)
		total += short
	return mini(total, 10)


## Sort key order: best score first; on a tie the earlier era (cheaper) wins,
## then the id — so the same seeds always plan the same studies.
static func _rank(entry: Dictionary) -> Array:
	return [-int(entry["score"]), int(entry["era"]), String(entry["tech"])]


## Best score first; on a tie the earlier era (cheaper) wins, then the id.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	return _rank(a) < _rank(b)
