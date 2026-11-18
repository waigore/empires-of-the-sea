class_name AiBindEconomy
extends RefCounted
## Routes the court's purse, workshop, college, and muster binds to the
## submission AI surface or to `scripts/ai_mainline/` for BENCH baseline rivals.
## `AiBind` owns config / phase / mainline load; this owner answers every economy
## planner question so the soft method bar on the bind facade stays clear
## (REQ-P3-01, REQ-P3-02).


## `town_level` is the court's best town: the second-stage rows' works gate. The
## origin/main planners have no town reading, so the baseline call stays as it
## was and its rivals keep the old behaviour (wiki: production-recipes
## § Town-works gates; DR-20261116-04). `held` is the raw the muster's and the
## hull's own rows claim — the submission surface plans manufacture around it
## (issue #484, #878); the baseline has no reading.
static func production_orders(
	kind: String, config: Variant, economy: PlayerEconomy, town_level: int = 0,
	held: Dictionary = {}
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml("ai_economy_planner.gd", "production_orders", [config, economy])
	return AiEconomyPlanner.production_orders(config, economy, town_level, held)


static func recruitment_orders(
	kind: String, config: Variant, economy: PlayerEconomy, floor: int = 0,
	fed_slack: int = -1, hands: int = 0, conquest_bank: bool = false
) -> Array[Dictionary]:
	var raw: Variant = (
		AiBind._ml(
			"ai_economy_planner.gd", "recruitment_orders",
			[config, economy, floor, fed_slack]
		)
		if AiBind._baseline(kind)
		else AiEconomyPlanner.recruitment_orders(
			config, economy, floor, fed_slack, hands, conquest_bank
		)
	)
	var out: Array[Dictionary] = []
	out.assign(raw)
	return out


static func income_plan(
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	at_war: bool,
	regiments: int,
	hull_chest: int = 0,
	own_warships: int = -1,
	muster_stall: int = 0,
	conquest_gap: bool = false
) -> Dictionary:
	if AiBind._baseline(kind):
		# Mainline income has no hull_chest or escalation arg yet.
		return AiBind._ml("ai_income.gd", "plan", [config, economy, at_war, regiments])
	return AiIncome.plan(
		config, economy, at_war, regiments, hull_chest, own_warships, muster_stall,
		conquest_gap
	)


static func research_plan(
	kind: String, config: Variant, economy: PlayerEconomy, context: Dictionary
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml("ai_research_planner.gd", "plan", [config, economy, context])
	return AiResearchPlanner.plan(config, economy, context)


static func research_floor(kind: String, config: Variant) -> int:
	if AiBind._baseline(kind):
		return int(AiBind._ml("ai_research_planner.gd", "research_floor", [config]))
	return AiResearchPlanner.research_floor(config)


static func market_plan(
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	market: WorldMarket,
	free_holds: int,
	tech_unlocked: Dictionary,
	reserved: Dictionary,
	need: Dictionary,
	floor: int = 0,
	food_shortfall: int = 0,
	saving: bool = false,
	speculate: bool = true,
	works_floor: int = -1,
	hire_margin: int = 0
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_market_planner.gd",
			"plan",
			[config, economy, market, free_holds, tech_unlocked, reserved, need, floor, food_shortfall]
		)
	return AiMarketPlanner.plan(
		config, economy, market, free_holds, tech_unlocked, reserved, need, floor,
		food_shortfall, saving, speculate, works_floor, hire_margin
	)


static func market_stage(
	kind: String,
	economy: PlayerEconomy,
	market: WorldMarket,
	plan: Dictionary,
	faction: int,
	tech_unlocked: Dictionary
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_market_planner.gd", "stage", [economy, market, plan, faction, tech_unlocked]
		)
	return AiMarketPlanner.stage(economy, market, plan, faction, tech_unlocked)


static func muster_reserve(
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	regiments: int,
	at_war: bool,
	pressure_extra: int = 0
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_army_reinforce.gd",
			"muster_reserve",
			[config, economy, regiments, at_war, pressure_extra]
		)
	return AiArmyReinforce.muster_reserve(config, economy, regiments, at_war, pressure_extra)


static func reinforce_plan(
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	regiments: int,
	at_war: bool,
	pressure_extra: int = 0,
	fed_slack: int = -1,
	reserve: int = 0,
	held_row: Dictionary = {},
	own_warships: int = -1,
	harvest_slack: int = -2,
	conquest_gap: bool = false
) -> Dictionary:
	if AiBind._baseline(kind):
		# Mainline reinforce has no hull reserve or harvest arg yet.
		return AiBind._ml(
			"ai_army_reinforce.gd",
			"plan",
			[config, economy, regiments, at_war, pressure_extra, fed_slack]
		)
	return AiArmyReinforce.plan(
		config, economy, regiments, at_war, pressure_extra, fed_slack, reserve,
		held_row, own_warships, harvest_slack, conquest_gap
	)


static func fed_slack(
	kind: String, economy: PlayerEconomy, army_food: int, ships: int
) -> int:
	if AiBind._baseline(kind):
		return int(AiBind._ml("ai_army_reinforce.gd", "fed_slack", [economy, army_food, ships]))
	return AiArmyReinforce.fed_slack(economy, army_food, ships)
