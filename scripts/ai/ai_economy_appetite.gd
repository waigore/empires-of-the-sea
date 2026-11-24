class_name AiEconomyAppetite
extends RefCounted
## The raws a rival workshop still lacks, weighed for colonisation ground
## (wiki: production-recipes; DR-20261119-05; issue #1382).
##
## A row's input is worth the voyage only while the store stands short of
## `reserve_target`; a mineral is never read, because a chart shows no
## unprospected ground (DR-20261111-26). Once the court charts the New World,
## the appetite also carries a treasury `riches` weight for mineral-bearing
## coasts an Explorer can survey. Pure rules: config and ledger in, weights out
## (REQ-P2-03, REQ-P3-03). [AiEconomyPlanner] keeps the public door; the
## workshop plan and hire ladder live on [AiEconomyProduction] and
## [AiEconomyRecruitment].


## Commodity → weight the colonisation planner reads when a colonist lands.
## `charts` is the court's own fog: a null chart is the fixture reading — the
## crown has charted nothing, so no riches coast is named.
static func ground_appetite(
	config: AiConfig, economy: PlayerEconomy, town_level: int = 0,
	charts: CourtCharts = null
) -> Dictionary:
	var appetite: Dictionary = {}
	if config == null or economy == null:
		return appetite
	var target: int = maxi(config.parameter("economy.reserve_target"), 0)
	for recipe_id: String in ProductionRecipes.available_ids_for(
		economy.tech_unlocked, economy.workers, town_level
	):
		for raw: Variant in ProductionRecipes.inputs(recipe_id).keys():
			var id: String = String(raw)
			if ImprovementCatalog.MINERAL_COMMODITIES.has(id):
				continue
			var deficit: int = maxi(target - economy.quantity(id), 0)
			if deficit <= 0:
				continue
			appetite[id] = int(appetite.get(id, 0)) + deficit
	var weight: int = maxi(config.parameter("economy.riches_route_weight"), 0)
	if weight > 0 and _charts_new_world(charts, config.faction):
		appetite["riches"] = weight
	return appetite


## True when the court's own chart has reached the New World: its region-1 grid
## holds at least one charted sea zone. A null chart is the fixture reading —
## the crown has charted nothing, so no riches coast is named.
static func _charts_new_world(charts: CourtCharts, owner: int) -> bool:
	if charts == null:
		return false
	var view: VisibilityModel = charts.model_for(owner, WorldMap.NEW_WORLD)
	if view == null:
		return false
	return not charts.known_zones(owner, WorldMap.NEW_WORLD).is_empty()
