class_name AiBindCampaign
extends RefCounted
## Routes the court's field, fleet, voyage, and hospital binds to the
## submission AI surface or to `scripts/ai_mainline/` for BENCH baseline rivals.
## `AiBind` owns config / phase / mainline load; this owner answers every
## campaign planner question so the soft method bar on the bind facade stays
## clear (REQ-P3-01, REQ-P3-02).


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
	if AiBind._baseline(kind):
		return AiBind._ml(
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
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_military_planner.gd", "split_orders", [config, diplomacy, model, roster]
		)
	return AiMilitaryPlanner.split_orders(config, diplomacy, model, roster)


static func military_march(
	kind: String, config: Variant, diplomacy: DiplomacyState, model: MapModel, roster: Array
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml(
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
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_naval_planner.gd", "orders", [config, diplomacy, model, roster, charts]
		)
	return AiNavalPlanner.orders(
		config, diplomacy, model, roster, charts,
		AiPhasePlanner.phase_for(config, diplomacy)
	)


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
	if AiBind._baseline(kind):
		return AiBind._ml(
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
	if AiBind._baseline(kind):
		return AiBind._ml(
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
	earning: bool,
	appetite: Dictionary = {}
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_colonisation_planner.gd",
			"plan",
			[config, world, region, model, fleets, civilians, abroad, charts, posture, earning]
		)
	return AiColonisationPlanner.plan(
		config, world, region, model, fleets, civilians, abroad, charts, posture,
		earning, appetite
	)


static func harbour(kind: String, model: MapModel, faction: int) -> int:
	if AiBind._baseline(kind):
		return int(AiBind._ml("ai_colonisation_planner.gd", "harbour", [model, faction]))
	return AiColonisationPlanner.harbour(model, faction)


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
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_cargo_planner.gd",
			"plan",
			[config, economy, model, roster, seat, want, blocked]
		)
	return AiCargoPlanner.plan(config, economy, model, roster, seat, want, blocked)


static func cargo_apply_route(
	kind: String, model: MapModel, fleet: FleetState, route: Dictionary
) -> Dictionary:
	if AiBind._baseline(kind):
		return AiBind._ml("ai_cargo_planner.gd", "apply_route", [model, fleet, route])
	return AiCargoPlanner.apply_route(model, fleet, route)


static func hospital_best_army(
	kind: String,
	model: MapModel,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	at_war: bool
) -> Variant:
	if AiBind._baseline(kind):
		return AiBind._ml(
			"ai_hospital_train_work.gd",
			"best_army",
			[model, roster, faction, economy, at_war]
		)
	return AiHospitalTrainWork.best_army(model, roster, faction, economy, at_war)
