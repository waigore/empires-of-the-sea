class_name MapPlayEconomyAi
extends RefCounted
## Rival economy and civilian turn (docs/ai.md, wiki: economy-planner,
## civilian-work-planner). Each court runs its own ledger through the shared
## EconomyTurn, then AiEconomyPlanner assigns next turn's production and
## AiCivilianPlanner issues work through CivilianWork. Rules stay pure; this
## adapter only seeds the opening roster, applies legal orders and reports the
## trace (REQ-P2-03, REQ-P3-03).

const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]


## Resolves every rival economy once, then plans the next turn. Call after the
## Build/Work pass and before the player's own economy so both read the works
## that just completed.
static func run(play: PlaySession) -> Dictionary:
	var report: Dictionary = {"factions": {}, "orders": []}
	if play == null or play.world == null or play.civilian_layer == null:
		return report
	if play.ai == null:
		play.ai = AiState.new()
	var by_faction: Dictionary = report["factions"]
	var order_log: Array = report["orders"]
	var market: WorldMarket = _market(play)
	var factions: Array[int] = FactionCatalog.great_power_ids()
	var last: int = factions[factions.size() - 1] if not factions.is_empty() else -1
	for faction: int in factions:
		if faction == play.player_faction and not play.observer_mode:
			continue
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		_seed_civilians(play, faction)
		var extraction: Dictionary = _extraction(play, faction, economy)
		# All crowns share one world market: prices advance once per turn, on the
		# last ledger of the observer pass (wiki: stockpiles-and-production).
		var resolved: Dictionary = EconomyTurn.resolve(
			economy, market, extraction, _ships(play, faction),
			_army_food(play, faction), play.observer_mode and faction == last
		)
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var production: Dictionary = AiEconomyPlanner.production_orders(config, economy)
		economy.clear_assignments()
		for assignment: Dictionary in production["assignments"]:
			economy.set_assignment(String(assignment["recipe"]), int(assignment["units"]))
		var recruits: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(config, economy)
		for order: Dictionary in recruits:
			economy.recruit(int(order["tier"]))
		var civilians: Dictionary = _run_civilians(play, faction, economy, config)
		order_log.append_array(civilians["orders"])
		by_faction[faction] = {
			"extraction": extraction,
			"resolved": resolved,
			"production": production,
			"recruits": recruits,
			"civilians": civilians,
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
		for type_id: String in STARTING_CIVILIANS:
			var tile: Vector2i = _mustering_tile(
				model, int(capital["province"]), roster
			)
			if tile.x < 0:
				break
			_append_unit(play, region, roster, faction, type_id, tile)
		play.civilian_layer.regions.set_region(region, roster)


## Runs the civilian planner in every region this court owns units in.
static func _run_civilians(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: AiConfig
) -> Dictionary:
	var report: Dictionary = {"orders": [], "moves": [], "training": []}
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = _roster(play, region)
		if model == null or roster.is_empty():
			continue
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if works == null:
			continue
		var capital: Dictionary = _capital(model, faction)
		var province: int = int(capital["province"])
		var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
		var context: Dictionary = {
			"treasury": economy.treasury,
			"paper": economy.quantity("paper"),
			"capital_province": province,
			"capital_tile": capital["tile"],
			"tech_unlocked": economy.tech_unlocked,
			"at_war": _at_war(play, faction),
		}
		var plan: Dictionary = AiCivilianPlanner.plan(
			config, model, roster, works, economy.stockpile, tech_caps,
			economy.tech_unlocked, context
		)
		for move: Dictionary in plan["moves"]:
			var unit: CivilianState = _unit_by_id(roster, int(move["unit_id"]))
			if unit != null:
				CivilianMovement.apply_move(model, unit, move["tile"])
				report["moves"].append(move)
		for order: Dictionary in plan["orders"]:
			var unit: CivilianState = _unit_by_id(roster, int(order["unit_id"]))
			if unit == null:
				continue
			var result: Dictionary = CivilianWork.assign(
				model, unit, String(order["action"]), works, roster,
				economy.stockpile, null, order["tile"], tech_caps,
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


## One extraction total for this crown: its home region's yield lands directly,
## every other region's tonnage crosses on the crown's home holds (wiki:
## extraction-and-improvements § Flow to Stockpile; DR-20261109-17). A rival
## ships like the player — no colonial ton arrives without a hold.
static func _extraction(
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
	return EconomyOverseas.delivered(
		home, play.world, home_region, faction, tech_caps, works_by_region, holds
	)["extraction"] as Dictionary


static func _market(play: PlaySession) -> WorldMarket:
	if play.economy != null and play.economy.market != null:
		return play.economy.market
	return WorldMarket.with_default_prices()


static func _ships(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	return play.ship_layer.hull_count_all(faction)


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
