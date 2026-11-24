class_name AiEconomyPlanner
extends RefCounted
## Full-AI economy policy door (wiki: economy-planner, growth-stage-planner).
##
## The workshop plan lives on [AiEconomyProduction]; hire and train orders on
## [AiEconomyRecruitment]; colonisation ground weights on [AiEconomyAppetite].
## This owner keeps the published API so map adapters and traces never chase a
## rename (REQ-P2-03, REQ-P3-01, REQ-P3-03). Pure rules: state in, orders out.

## Build-input outputs the workshop ranks first — owned by the production home.
const BUILD_INPUTS: Array[String] = AiEconomyProduction.BUILD_INPUTS


## Production assignments for the next Production phase plus the scored
## candidates that explain them. See [method AiEconomyProduction.production_orders].
static func production_orders(
	config: AiConfig, economy: PlayerEconomy, town_level: int = 0,
	held: Dictionary = {}
) -> Dictionary:
	return AiEconomyProduction.production_orders(config, economy, town_level, held)


## Recruit orders, highest affordable tier first. See
## [method AiEconomyRecruitment.recruitment_orders].
static func recruitment_orders(
	config: AiConfig, economy: PlayerEconomy, floor: int = 0, fed_slack: int = -1,
	hands: int = 0, conquest_bank: bool = false,
	harvest_slack: int = -2
) -> Array[Dictionary]:
	return AiEconomyRecruitment.recruitment_orders(
		config, economy, floor, fed_slack, hands, conquest_bank, harvest_slack
	)


## Raws the workshop still lacks, weighed for colonisation ground. See
## [method AiEconomyAppetite.ground_appetite].
static func ground_appetite(
	config: AiConfig, economy: PlayerEconomy, town_level: int = 0,
	charts: CourtCharts = null
) -> Dictionary:
	return AiEconomyAppetite.ground_appetite(config, economy, town_level, charts)


## True when the purse could already pay a trained-tier row today.
static func _next_training_affordable(economy: PlayerEconomy, reserve: int) -> bool:
	return AiEconomyRecruitment._next_training_affordable(economy, reserve)


## True when this court's own techs already open `tier`.
static func _techs_open(economy: PlayerEconomy, tier: int) -> bool:
	return AiEconomyRecruitment._techs_open(economy, tier)


## Treasury a training of `tier` would cost this court, or -1 for a bad tier.
static func _trains(economy: PlayerEconomy, tier: int) -> int:
	return AiEconomyRecruitment._trains(economy, tier)
