class_name MapPlayEconomyAi
extends RefCounted
## Rival economy/civilian/research turn (docs/ai.md). Seeds the opening roster,
## runs EconomyTurn + planners, applies legal orders, reports the trace
## (REQ-P2-03, REQ-P3-03).

## Rivals open with a spy, so espionage is live from turn one.
const RIVAL_STARTING_CIVILIANS: Array[String] = [
	"explorer", "builder", "engineer", "spy",
]

## Resolves every rival economy once, then plans the next turn. Call after the
## Build/Work pass and before the player's own economy so both read the works
## that just completed.
static func run(play: PlaySession) -> Dictionary:
	var report: Dictionary = {"factions": {}, "orders": []}
	if play == null or play.world == null or play.civilian_layer == null:
		return report
	play.ensure_ai()
	var by_faction: Dictionary = report["factions"]
	var order_log: Array = report["orders"]
	var market: WorldMarket = _market(play)
	var factions: Array[int] = FactionCatalog.great_power_ids()
	var last: int = factions[factions.size() - 1] if not factions.is_empty() else -1
	# Every rival ledger exists before any court resolves, so a spy observing a
	# court later in the order still reads its known techs this turn.
	MapPlaySpyAi.prepare_ledgers(play)
	for faction: int in factions:
		if faction == play.player_faction and not play.observer_mode:
			continue
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		_seed_civilians(play, faction)
		var overseas: Dictionary = _overseas(play, faction, economy)
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var revealed: Dictionary = MapPlayCourtFog.research_revealed(play, faction)
		var production: Dictionary = AiEconomyPlanner.production_orders(config, economy)
		var trade: Dictionary = _trade(play, faction, economy, config, market, overseas, production)
		# Plan before the phase resolves, so the study starts this turn.
		var research: Dictionary = AiResearchPlanner.plan(
			config, economy, {"at_war": _at_war(play, faction), "revealed": revealed}
		)
		# Shared market: prices advance once, on the last observer ledger.
		var resolved: Dictionary = EconomyTurn.resolve(
			economy, market, overseas["extraction"] as Dictionary, _ships(play, faction),
			_army_food(play, faction), play.observer_mode and faction == last,
			MapPlaySpyAi.research_bonus(play, faction, economy)
		)
		economy.clear_assignments()
		for assignment: Dictionary in production["assignments"]:
			economy.set_assignment(String(assignment["recipe"]), int(assignment["units"]))
		var recruits: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(config, economy)
		for order: Dictionary in recruits:
			economy.recruit(int(order["tier"]))
		var civilians: Dictionary = _run_civilians(play, faction, economy, config, overseas)
		order_log.append_array(civilians["orders"])
		by_faction[faction] = {
			"extraction": overseas["extraction"],
			"resolved": resolved,
			"production": production,
			"trade": trade,
			"recruits": recruits,
			"civilians": civilians,
			"research": research,
		}
	return report


## Every region the player has bootstrapped gets the rival's opening civilians
## once. A rival with no capital there (a colony or the New World) gets none.
static func _seed_civilians(play: PlaySession, faction: int) -> void:
	for region: int in play.civilian_layer.works_regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array = _roster(play, region)
		if _has_owner(roster, faction):
			continue
		var capital: Dictionary = _capital(model, faction)
		if int(capital["province"]) < 0:
			continue
		for type_id: String in RIVAL_STARTING_CIVILIANS:
			var tile: Vector2i = _mustering_tile(model, int(capital["province"]), roster)
			if tile.x < 0:
				break
			_append_unit(play, region, roster, faction, type_id, tile)
		play.civilian_layer.regions.set_region(region, roster)


## Runs the civilian planner in every region this court owns units in; an overseas
## region is priced on the raw its holds actually landed.
static func _run_civilians(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: AiConfig,
	overseas: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = {"orders": [], "moves": [], "training": []}
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = _roster(play, region)
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if model == null or roster.is_empty() or works == null:
			continue
		var capital: Dictionary = _capital(model, faction)
		var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
		var context: Dictionary = {
			"treasury": economy.treasury,
			"paper": economy.quantity("paper"),
			"capital_province": int(capital["province"]),
			"capital_tile": capital["tile"],
			"tech_unlocked": economy.tech_unlocked,
			"at_war": _at_war(play, faction), "diplomacy": play.diplomacy,
			"visibility": MapPlayCourtFog.view_for(play, faction, region),
		}
		if region != int(overseas.get("home_region", region)):
			context["delivered_raw"] = (overseas.get("by_province", {}) as Dictionary).get(region, {})
		var plan: Dictionary = AiCivilianPlanner.plan(
			config, model, roster, works, economy.stockpile, tech_caps,
			economy.tech_unlocked, context
		)
		for move: Dictionary in plan["moves"]:
			var unit: CivilianState = _unit_by_id(roster, int(move["unit_id"]))
			if unit != null:
				var view: VisibilityModel = context["visibility"]
				CivilianMovement.apply_move(model, unit, move["tile"], view)
				report["moves"].append(move)
		for order: Dictionary in plan["orders"]:
			var unit: CivilianState = _unit_by_id(roster, int(order["unit_id"]))
			if unit == null:
				continue
			var result: Dictionary = CivilianWork.assign(
				model, unit, String(order["action"]), works, roster,
				economy.stockpile, context["visibility"], order["tile"], tech_caps,
				economy.tech_unlocked, context
			)
			if bool(result.get("ok", false)):
				report["orders"].append(order)
		var training: Dictionary = plan["training"]
		if bool(training.get("ok", false)):
			var hired: Dictionary = _train(
				play, region, roster, faction, economy, training, context
			)
			if not hired.is_empty():
				report["training"].append(hired)
		play.civilian_layer.regions.set_region(region, roster)
		if (
			play.model != null and region == play.model.region_id
			and play.civilian_layer.is_inside_tree()
		):
			play.civilian_layer.sync()
			play.civilian_layer.refresh_works()
	return report


## Pays for and musters a civilian at the faction's capital, through the same
## catalog costs the training panel uses.
static func _train(
	play: PlaySession,
	region: int,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	training: Dictionary,
	context: Dictionary
) -> Dictionary:
	var type_id: String = String(training.get("type_id", ""))
	var province: int = int(context.get("capital_province", -1))
	if type_id.is_empty() or province < 0:
		return {}
	var treasury_cost: int = CivilianCatalog.treasury_cost(type_id)
	var paper_cost: int = CivilianCatalog.paper_cost(type_id)
	if economy.treasury < treasury_cost or economy.quantity("paper") < paper_cost:
		return {}
	var model: MapModel = play.world.region(region)
	var tile: Vector2i = _mustering_tile(model, province, roster)
	if tile.x < 0 or not economy.spend_treasury(treasury_cost):
		return {}
	if not economy.take("paper", paper_cost):
		economy.add_treasury(treasury_cost)
		return {}
	var unit: CivilianState = _append_unit(
		play, region, roster, faction, type_id, tile
	)
	return {"type_id": type_id, "unit": unit.id, "tile": tile}


# --- economy -----------------------------------------------------------------


## Home yield plus colonial tonnage on home holds, with hold accounting for the
## market pass (wiki: extraction-and-improvements).
static func _overseas(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> Dictionary:
	var works_by_region: MapRegionTable = play.civilian_layer.works_regions
	var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
	var home_region: int = FactionCatalog.region_of(faction)
	if home_region < 0:
		home_region = WorldMap.OLD_WORLD
	var home: Dictionary = {}
	var home_model: MapModel = play.world.region(home_region)
	if home_model != null and works_by_region.value(home_region, null) != null:
		var works: LandWorks = works_by_region.value(home_region, null)
		var capital: Dictionary = _capital(home_model, faction)
		home = Extraction.yields(
			home_model, faction, int(capital["province"]), tech_caps, works,
			capital["tile"], economy.tech_unlocked
		)
	var holds: int = 0
	if play.ship_layer != null:
		holds = TradeCargo.capacity(
			play.world, play.ship_layer.regions.snapshot(), faction
		)
	var plan: Dictionary = EconomyOverseas.delivered(
		home, play.world, home_region, faction, tech_caps, works_by_region, holds,
		economy.tech_unlocked
	)
	plan["home_region"] = home_region
	return plan


static func _market(play: PlaySession) -> WorldMarket:
	if play.economy != null and play.economy.market != null:
		return play.economy.market
	return WorldMarket.with_default_prices()


## Sells above the reserve and this turn's inputs, then bids short build inputs
## with the holds the colonies left (wiki: world-market § Cargo).
static func _trade(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	config: AiConfig,
	market: WorldMarket,
	overseas: Dictionary,
	production: Dictionary
) -> Dictionary:
	var holds: int = 0
	if play.ship_layer != null:
		holds = TradeCargo.capacity(
			play.world, play.ship_layer.regions.snapshot(), faction
		)
	var free_holds: int = maxi(
		holds - EconomyOverseas.shipped_total(overseas)
		- TradeCargo.used(market, faction),
		0
	)
	var reserved: Dictionary = _reserved_inputs(
		production, _food_demand(play, faction, economy)
	)
	# The running Production phase spends the assignments set last turn, before
	# this run replaces them; reserve both sets so a sale never starves either.
	var current: Dictionary = _reserved_inputs({"assignments": economy.assignments()})
	for commodity: Variant in current.keys():
		var id: String = String(commodity)
		reserved[id] = int(reserved.get(id, 0)) + int(current[commodity])
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, free_holds, economy.tech_unlocked, reserved
	)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, faction)
	result["plan"] = plan
	result["free_holds"] = free_holds
	return result


## Inputs this turn's production promised, plus food the consumption phase eats,
## so a sale never starves the court or spends a commodity twice.
static func _reserved_inputs(production: Dictionary, food: int = 0) -> Dictionary:
	var reserved: Dictionary = {}
	if food > 0:
		reserved["grain"] = food
	for raw: Variant in production.get("assignments", []):
		var assignment: Dictionary = raw
		var units: int = int(assignment.get("units", 0))
		if units <= 0:
			continue
		var inputs: Dictionary = ProductionRecipes.inputs(String(assignment.get("recipe", "")))
		for commodity: Variant in inputs.keys():
			var id: String = String(commodity)
			reserved[id] = int(reserved.get(id, 0)) + int(inputs[commodity]) * units
	return reserved


static func _ships(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	return play.ship_layer.hull_count_all(faction)


## Food this court will eat before Production: army, navy and every worker
## ration (wiki: workers-and-population § Consumption).
static func _food_demand(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> int:
	var demand: int = _army_food(play, faction)
	demand += _ships(play, faction) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
	for tier in WorkerPool.TIER_COUNT:
		demand += economy.workers.count(tier) * WorkerPool.FOOD_PER_WORKER[tier]
	return demand


static func _army_food(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.food_upkeep_all(faction)


static func _at_war(play: PlaySession, faction: int) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			return true
	return false


# --- helpers -----------------------------------------------------------------


static func _capital(model: MapModel, faction: int) -> Dictionary:
	var province: int = WorldBootstrap.capital_province(model, faction)
	if province < 0:
		return {"province": -1, "tile": CivilianState.NO_TILE}
	return {"province": province, "tile": model.capital_tile_of(province)}


static func _roster(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.units
	var roster: Array[CivilianState] = []
	roster.assign(play.civilian_layer.regions.value(region, []))
	return roster


static func _has_owner(roster: Array, owner: int) -> bool:
	for unit: CivilianState in roster:
		if unit != null and unit.owner == owner:
			return true
	return false


## Appends to the visible roster through the layer's own id counter; an
## off-screen region only stores the unit in its table (no marker yet).
static func _append_unit(
	play: PlaySession,
	region: int,
	roster: Array,
	owner: int,
	type_id: String,
	tile: Vector2i
) -> CivilianState:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.add_unit(owner, type_id, tile)
	var unit: CivilianState = CivilianState.create(
		play.civilian_layer.next_id, owner, type_id, tile
	)
	play.civilian_layer.next_id += 1
	roster.append(unit)
	return unit


## Free land tile in the province nearest its seat, mirroring the player's
## mustering rule without needing the region on screen.
static func _mustering_tile(
	model: MapModel, province: int, roster: Array
) -> Vector2i:
	if model == null or province < 0:
		return CivilianState.NO_TILE
	var seat: Vector2i = model.capital_tile_of(province)
	var tiles: Array = model.province_tiles(province)
	if seat.x < 0:
		if tiles.is_empty():
			return CivilianState.NO_TILE
		seat = tiles[0]
	var taken: Dictionary = {seat: true}
	for unit: CivilianState in roster:
		if unit != null:
			taken[unit.tile] = true
	var free: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		if not taken.has(tile) and model.is_land(tile.x, tile.y):
			free.append(tile)
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var left: int = (a - seat).length_squared()
		var right: int = (b - seat).length_squared()
		if left != right:
			return left < right
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	if free.is_empty():
		return seat
	return free[0]


static func _unit_by_id(roster: Array, unit_id: int) -> CivilianState:
	for unit: CivilianState in roster:
		if unit != null and unit.id == unit_id:
			return unit
	return null
