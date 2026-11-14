class_name AiBind
extends RefCounted
## Routes planner static calls to the submission AI surface or to
## `scripts/ai_mainline/` (origin/main copy) for BENCH baseline rivals.
## Mainline scripts load by path so the project parses before sync.

const MAINLINE_ROOT: String = "res://scripts/ai_mainline/"


static func _baseline(kind: String) -> bool:
	return (
		kind == AiControl.KIND_BASELINE
		and ResourceLoader.exists(MAINLINE_ROOT + "ai_config.gd")
	)


static func config(kind: String, faction: int, game_seed: int) -> Variant:
	if _baseline(kind):
		return _ml("ai_config.gd", "build", [faction, game_seed])
	return AiConfig.build(faction, game_seed)


static func production_orders(kind: String, config: Variant, economy: PlayerEconomy) -> Dictionary:
	if _baseline(kind):
		return _ml("ai_economy_planner.gd", "production_orders", [config, economy])
	return AiEconomyPlanner.production_orders(config, economy)


static func recruitment_orders(
	kind: String, config: Variant, economy: PlayerEconomy, floor: int = 0, fed_slack: int = -1
) -> Array[Dictionary]:
	var raw: Variant = (
		_ml("ai_economy_planner.gd", "recruitment_orders", [config, economy, floor, fed_slack])
		if _baseline(kind)
		else AiEconomyPlanner.recruitment_orders(config, economy, floor, fed_slack)
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
	hull_chest: int = 0
) -> Dictionary:
	if _baseline(kind):
		# Mainline income has no hull_chest arg yet.
		return _ml("ai_income.gd", "plan", [config, economy, at_war, regiments])
	return AiIncome.plan(config, economy, at_war, regiments, hull_chest)


static func research_plan(
	kind: String, config: Variant, economy: PlayerEconomy, context: Dictionary
) -> Dictionary:
	if _baseline(kind):
		return _ml("ai_research_planner.gd", "plan", [config, economy, context])
	return AiResearchPlanner.plan(config, economy, context)


static func research_floor(kind: String, config: Variant) -> int:
	if _baseline(kind):
		return int(_ml("ai_research_planner.gd", "research_floor", [config]))
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
	saving: bool = false
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_market_planner.gd",
			"plan",
			[config, economy, market, free_holds, tech_unlocked, reserved, need, floor, food_shortfall]
		)
	return AiMarketPlanner.plan(
		config, economy, market, free_holds, tech_unlocked, reserved, need, floor,
		food_shortfall, saving
	)


static func market_stage(
	kind: String,
	economy: PlayerEconomy,
	market: WorldMarket,
	plan: Dictionary,
	faction: int,
	tech_unlocked: Dictionary
) -> Dictionary:
	if _baseline(kind):
		return _ml(
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
	if _baseline(kind):
		return _ml(
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
	reserve: int = 0
) -> Dictionary:
	if _baseline(kind):
		# Mainline reinforce has no hull reserve arg yet.
		return _ml(
			"ai_army_reinforce.gd",
			"plan",
			[config, economy, regiments, at_war, pressure_extra, fed_slack]
		)
	return AiArmyReinforce.plan(
		config, economy, regiments, at_war, pressure_extra, fed_slack, reserve
	)


static func fed_slack(
	kind: String, economy: PlayerEconomy, army_food: int, ships: int
) -> int:
	if _baseline(kind):
		return int(_ml("ai_army_reinforce.gd", "fed_slack", [economy, army_food, ships]))
	return AiArmyReinforce.fed_slack(economy, army_food, ships)


static func civilian_plan(
	kind: String,
	config: Variant,
	model: MapModel,
	roster: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_civilian_planner.gd",
			"plan",
			[config, model, roster, works, stockpile, tech_caps, tech_unlocked, context]
		)
	return AiCivilianPlanner.plan(
		config, model, roster, works, stockpile, tech_caps, tech_unlocked, context
	)


static func military_split(
	kind: String, config: Variant, diplomacy: DiplomacyState, model: MapModel, roster: Array
) -> Array:
	if _baseline(kind):
		return _ml(
			"ai_military_planner.gd", "split_orders", [config, diplomacy, model, roster]
		)
	return AiMilitaryPlanner.split_orders(config, diplomacy, model, roster)


static func military_march(
	kind: String, config: Variant, diplomacy: DiplomacyState, model: MapModel, roster: Array
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_military_planner.gd", "march_orders", [config, diplomacy, model, roster]
		)
	return AiMilitaryPlanner.march_orders(config, diplomacy, model, roster)


static func naval_orders(
	kind: String,
	config: Variant,
	diplomacy: DiplomacyState,
	model: MapModel,
	roster: Array,
	charts: Variant
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_naval_planner.gd", "orders", [config, diplomacy, model, roster, charts]
		)
	return AiNavalPlanner.orders(config, diplomacy, model, roster, charts)


static func invasion_plan(
	kind: String,
	config: Variant,
	diplomacy: DiplomacyState,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	armies: Array,
	turn: int,
	charts: Variant,
	earning: bool
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_invasion_planner.gd",
			"plan",
			[config, diplomacy, world, region, model, fleets, armies, turn, charts, earning]
		)
	return AiInvasionPlanner.plan(
		config, diplomacy, world, region, model, fleets, armies, turn, charts, earning
	)


static func invasion_split(
	kind: String,
	config: Variant,
	diplomacy: DiplomacyState,
	world: WorldMap,
	model: MapModel,
	fleets: Array,
	armies: Array,
	charts: Variant,
	wants_income: bool
) -> Array:
	if _baseline(kind):
		return _ml(
			"ai_invasion_planner.gd",
			"split_orders",
			[config, diplomacy, world, model, fleets, armies, charts, wants_income]
		)
	return AiInvasionPlanner.split_orders(
		config, diplomacy, world, model, fleets, armies, charts, wants_income
	)


static func colonisation_plan(
	kind: String,
	config: Variant,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	civilians: Array,
	abroad: Dictionary,
	charts: Variant,
	posture: String,
	earning: bool
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_colonisation_planner.gd",
			"plan",
			[config, world, region, model, fleets, civilians, abroad, charts, posture, earning]
		)
	return AiColonisationPlanner.plan(
		config, world, region, model, fleets, civilians, abroad, charts, posture, earning
	)


static func harbour(kind: String, model: MapModel, faction: int) -> int:
	if _baseline(kind):
		return int(_ml("ai_colonisation_planner.gd", "harbour", [model, faction]))
	return AiColonisationPlanner.harbour(model, faction)


static func phase_for(kind: String, config: Variant, diplomacy: DiplomacyState) -> String:
	if _baseline(kind):
		return String(_ml("ai_phase_planner.gd", "phase_for", [config, diplomacy]))
	return AiPhasePlanner.phase_for(config, diplomacy)


static func cargo_plan(
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	model: MapModel,
	roster: Array,
	seat: int,
	want: int,
	blocked: Dictionary
) -> Dictionary:
	if _baseline(kind):
		return _ml(
			"ai_cargo_planner.gd",
			"plan",
			[config, economy, model, roster, seat, want, blocked]
		)
	return AiCargoPlanner.plan(config, economy, model, roster, seat, want, blocked)


static func cargo_apply_route(
	kind: String, model: MapModel, fleet: FleetState, route: Dictionary
) -> Dictionary:
	if _baseline(kind):
		return _ml("ai_cargo_planner.gd", "apply_route", [model, fleet, route])
	return AiCargoPlanner.apply_route(model, fleet, route)


static func hospital_best_army(
	kind: String,
	model: MapModel,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	at_war: bool
) -> Variant:
	if _baseline(kind):
		return _ml(
			"ai_hospital_train_work.gd",
			"best_army",
			[model, roster, faction, economy, at_war]
		)
	return AiHospitalTrainWork.best_army(model, roster, faction, economy, at_war)


static func _ml(file: String, method: String, args: Array) -> Variant:
	var path: String = MAINLINE_ROOT + file
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_error("AiBind: failed to load %s" % path)
		return null
	return script.callv(method, args)
