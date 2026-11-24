class_name AiArmyReinforceLine
extends RefCounted
## The line patterns a rival court may raise (wiki: ai-architecture § Land
## reinforcement, growth-stage-planner § Recruitment modulation).
##
## Owns the infantry catalog reading: which categories field a line, which
## patterns the court's techs and fields open, which one it is saving for, and
## the cheapest price it must bank. `AiArmyReinforce` owns the turn plan and the
## food gates; host size and the war chest live on [AiArmyReinforceHost] and
## [AiArmyReinforceChest]. This owner answers every line question, so the muster
## and the war chest never drift from one catalog (REQ-P2-03, REQ-P3-01,
## REQ-P3-03).

## Categories that field a line: a mustered regiment is infantry, never the
## army's whole battery or horse (the opening roster keeps its own mix).
const LINE_CATEGORIES: Array[int] = [
	RegimentCatalog.Category.LIGHT_INFANTRY,
	RegimentCatalog.Category.REGULAR_INFANTRY,
	RegimentCatalog.Category.HEAVY_INFANTRY,
]

## The hands one build-input recipe run spends (every row is labour 2): the pair
## the workshop needs before the levy may draft the fields bare (issue #1375).
const RECIPE_HANDS: int = 2


## True while the pool holds the hands the levy and the workshop both need:
## the `army.min_peasants` floor the levy draws from, the fields keep the rest
## (wiki: ai-architecture § Land reinforcement; the parameter's own meaning in
## `ai_parameter_army.gd`; issue #1355). The pool already nets the hands a build
## reserved, so the levy's own hand is never subtracted again here — that read
## the real floor as `min_peasants + 1` and held the muster all campaign.
## The muster, the pattern it saves for and the war chest it holds all gate on
## one labour reading.
##
## While the court is still under its worker target and its stores carry the
## raw a build-input recipe spends, the floor holds the pair of hands one
## labour-2 run spends above the levy's own: a pool the muster drafts to zero
## can run no recipe, so the court it starves can neither weave the cloth the
## muster and the yard both wait for nor hire the hands back — every build
## input in the world is a labour-2 run (issue #1375). A court at its worker
## target, or holding no recipe's raw, drafts as published.
static func labour_floor_ok(config: AiConfig, economy: PlayerEconomy) -> bool:
	if config == null or economy == null:
		return false
	return economy.available_peasants() >= labour_floor(config, economy)


## The free hands the muster leaves: the levy's own floor, plus the recipe pair
## while the pool still has room to grow and the workshop has raw to work
## (issue #1375). The conquest bank's hire ladder reads this same figure — the
## muster's own floor — as the pool it hires toward, so a court arming for its
## storm is never one hand short of the muster it banks for (issue #1432).
static func labour_floor(config: AiConfig, economy: PlayerEconomy) -> int:
	var levy: int = maxi(int(config.parameter("army.min_peasants")), 0)
	if economy.workers.total() >= maxi(
		int(config.parameter("economy.worker_target")), levy
	):
		return levy
	if economy.quantity("wool") < 2 and economy.quantity("timber") < 2:
		return levy
	return levy + RECIPE_HANDS


## The line regiment this court would raise if its stores could pay for it:
## strongest `FPN + FPM`, then the newer era, then the lowest id. Materials are
## deliberately not read — this is the pattern the court is provisioning for, and
## the muster itself checks what it can already pay (wiki: growth-stage-planner
## § Recruitment modulation).
static func next_type(config: AiConfig, economy: PlayerEconomy) -> String:
	var legal: Array[Dictionary] = candidates(config, economy)
	if legal.is_empty():
		return ""
	return String(legal[0]["type_id"])


## The line this court is saving for: the pattern it could raise today if its
## stores allowed, else the cheapest line its techs and fields open — the one a
## war chest it cannot yet spend will actually buy. Never empty unless its techs
## open no line at all or its fields cannot spare a hand (wiki:
## growth-stage-planner § Recruitment modulation; issue #474).
static func saving_type(config: AiConfig, economy: PlayerEconomy) -> String:
	if config == null or economy == null:
		return ""
	if not labour_floor_ok(config, economy):
		return ""
	var type_id: String = next_type(config, economy)
	if not type_id.is_empty():
		return type_id
	return cheapest_line_type(economy)


## Price of the cheapest line pattern this court's techs open today, ignoring the
## purse: what it has to save for, not what it can pay right now. 0 when its
## techs open no line at all. The reach test the money goal reads for a
## peace-time war chest (wiki: ai-architecture § Land reinforcement).
static func cheapest_line_price(economy: PlayerEconomy) -> int:
	return maxi(cheapest_line(economy), 0)


## Price of the cheapest line pattern this court's techs open today, ignoring the
## purse: what it has to save for, not what it can pay right now. -1 when its
## techs open no line at all.
static func cheapest_line(economy: PlayerEconomy) -> int:
	var type_id: String = cheapest_line_type(economy)
	if type_id.is_empty():
		return -1
	return RegimentCatalog.treasury_cost(type_id)


## The cheapest line pattern this court's techs open today, ignoring the purse.
## The lowest id breaks a tie, so the answer is stable across turns.
static func cheapest_line_type(economy: PlayerEconomy) -> String:
	var cheapest: String = ""
	var cost: int = -1
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		if not RegimentEconomy.buildable(type_id, economy.tech_unlocked):
			continue
		var price: int = RegimentCatalog.treasury_cost(type_id)
		if cost < 0 or price < cost or (price == cost and type_id < cheapest):
			cheapest = type_id
			cost = price
	return cheapest


## Line patterns this court's treasury, labour pool and techs open today,
## strongest first. Materials are not read here; the muster plan and
## [method next_type] each decide what to do with a pattern the stores cannot
## yet pay for. `reserve` is the purse a higher-ranked claim holds back (issue
## #484).
static func candidates(
	config: AiConfig, economy: PlayerEconomy, reserve: int = 0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if config == null or economy == null:
		return out
	if not labour_floor_ok(config, economy):
		return out
	var floor_treasury: int = maxi(config.parameter("army.min_treasury"), maxi(reserve, 0))
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		if not RegimentEconomy.buildable(type_id, economy.tech_unlocked):
			continue
		if economy.treasury - RegimentCatalog.treasury_cost(type_id) < floor_treasury:
			continue
		out.append({
			"type_id": type_id,
			"strength": RegimentCatalog.strength(type_id),
			"era": RegimentCatalog.era(type_id),
		})
	out.sort_custom(_better)
	return out


## The strongest line pattern this court's techs open, whatever its purse or
## labour — the strength a storm would march with once the men are raised
## (issue #1314). Empty when the tech set opens no line at all.
static func strongest_line(tech_unlocked: Dictionary) -> String:
	var best: String = ""
	var best_strength: int = -1
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		if not RegimentEconomy.buildable(type_id, tech_unlocked):
			continue
		var value: int = RegimentCatalog.strength(type_id)
		if value > best_strength or (value == best_strength and type_id < best):
			best = type_id
			best_strength = value
	return best


## The line the storm host is sized and raised with (issue #1381): the cheapest
## line its techs open, because the wall counts strength and the cheapest line
## carries the most strength per ducat (a levy's 3 for 2,000 against an
## arquebusier's 6 for 5,000). Sized on the strongest line instead, a court
## filled its target with twelve men carrying levies' strength and still stood
## under the wall (measured 48 against a Wood ceiling of 59). A court with no
## line open falls back to the strongest it can name, and to none at all when
## its techs open nothing.
static func storm_line(config: AiConfig, economy: PlayerEconomy) -> String:
	if economy == null:
		return ""
	var type_id: String = cheapest_line_type(economy)
	if not type_id.is_empty():
		return type_id
	return strongest_line(economy.tech_unlocked)


## Price of the line the storm host is sized and raised with (issue #1381):
## one man of [method storm_line], so the bank the court fills buys exactly the
## men the wall's host counts. 0 when its techs open no line at all.
static func storm_price(config: AiConfig, economy: PlayerEconomy) -> int:
	var type_id: String = storm_line(config, economy)
	if type_id.is_empty():
		return 0
	return RegimentCatalog.treasury_cost(type_id)


## Strongest first, then the newer pattern, then the lowest id — one stable
## answer for a given ledger and tech set.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["strength"]) != int(b["strength"]):
		return int(a["strength"]) > int(b["strength"])
	if int(a["era"]) != int(b["era"]):
		return int(a["era"]) > int(b["era"])
	return String(a["type_id"]) < String(b["type_id"])
