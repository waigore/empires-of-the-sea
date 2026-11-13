class_name MapPlayCivilianAi
extends RefCounted
## Rival civilian pass for the economy turn (docs/ai.md): seeds the opening
## roster, then runs `AiCivilianPlanner` in every region the court holds and
## applies the legal moves, works and training through the same rules the
## human's orders use (REQ-P2-03, REQ-P3-03).
##
## Split out of `MapPlayEconomyAi` so the civilian domain (units, mustering,
## training) does not share a file with extraction, market and food.

## Rivals open with a spy, so espionage is live from turn one.
const RIVAL_STARTING_CIVILIANS: Array[String] = [
	"explorer", "builder", "engineer", "spy",
]


## Every region the player has bootstrapped gets the rival's opening civilians
## once. A rival with no capital there (a colony or the New World) gets none.
static func seed(play: PlaySession, faction: int) -> void:
	for region: int in play.civilian_layer.works_regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array = _roster(play, region)
		if _has_owner(roster, faction):
			continue
		var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
		if int(capital["province"]) < 0:
			continue
		for type_id: String in RIVAL_STARTING_CIVILIANS:
			var tile: Vector2i = _mustering_tile(model, int(capital["province"]), roster)
			if tile.x < 0:
				break
			_append_unit(play, region, roster, faction, type_id, tile)
		play.civilian_layer.regions.set_region(region, roster)


## One planning pass over every region this court holds, priced on `stockpile`
## and applying nothing. The economy turn plans the works before the market
## stages its sale, so the feedstock a crew will spend is known in advance and
## can be kept back (wiki: economy-planner § Reservations — one stockpile serves
## build, work and trade); the same plans are applied once the ledger closes. An
## overseas region is priced on the raw its holds actually landed.
static func plan_all(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: AiConfig,
	overseas: Dictionary = {}, stockpile: Dictionary = {}, floor: int = 0
) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	# The cash a crew may spend is what the purse carries after the court's own
	# floor and, at war and short of its target, the muster it is saving for:
	# training and deeds are discretionary, the war chest is not (wiki:
	# growth-stage-planner § Recruitment modulation; treasury-planner
	# § Cash discipline; issue #474).
	var spendable: int = maxi(economy.treasury - maxi(floor, 0), 0)
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = _roster(play, region)
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if model == null or roster.is_empty() or works == null:
			continue
		var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
		var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
		var context: Dictionary = {
			"treasury": spendable,
			"paper": economy.quantity("paper"),
			"capital_province": int(capital["province"]),
			"capital_tile": capital["tile"],
			"tech_unlocked": economy.tech_unlocked,
			"at_war": _at_war(play, faction), "diplomacy": play.diplomacy,
			"visibility": MapPlayCourtFog.view_for(play, faction, region),
		}
		var muster: Vector2i = _muster_port(play, faction, region, model)
		if muster.x >= 0:
			context["muster_port"] = muster
		if region != int(overseas.get("home_region", region)):
			context["delivered_raw"] = (overseas.get("by_province", {}) as Dictionary).get(region, {})
		var plan: Dictionary = AiCivilianPlanner.plan(
			config, model, roster, works, stockpile, tech_caps,
			economy.tech_unlocked, context
		)
		_price(plan["orders"], model, works)
		plans.append({
			"region": region,
			"model": model,
			"roster": roster,
			"works": works,
			"tech_caps": tech_caps,
			"context": context,
			"plan": plan,
		})
	return plans


## The material row a planned work will be charged when it is assigned, read from
## the same two rules the assignment itself reads, so the row the market keeps
## back is the row the crew pays (wiki: civilian-units § Work Order Summary).
static func _price(orders: Array, model: MapModel, works: LandWorks) -> void:
	for raw: Variant in orders:
		var order: Dictionary = raw
		var action: String = String(order.get("action", ""))
		var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
		order["cost"] = CivilianWork.cost_for(
			action, CivilianWork.cost_level(action, model, tile, works)
		)


## The material rows the planned works will be charged, read ahead of the sale
## they must survive (wiki: economy-planner § Reservations). Training's paper is
## a separate claim and stays with the ledger.
static func work_rows(plans: Array[Dictionary]) -> Dictionary:
	var rows: Dictionary = {}
	for entry: Dictionary in plans:
		var plan: Dictionary = entry.get("plan", {})
		for raw: Variant in plan.get("orders", []):
			var order: Dictionary = raw
			var cost: Dictionary = order.get("cost", {})
			for commodity: Variant in cost.keys():
				var id: String = String(commodity)
				var amount: int = int(cost[commodity])
				if amount > 0:
					rows[id] = int(rows.get(id, 0)) + amount
	return rows


## Applies what `plan_all` decided: the moves, the work orders (paid through the
## same rules a crown's own orders use) and the next civilian to train.
static func apply(
	play: PlaySession, faction: int, economy: PlayerEconomy, plans: Array[Dictionary]
) -> Dictionary:
	var report: Dictionary = {"orders": [], "moves": [], "training": []}
	for entry: Dictionary in plans:
		var region: int = int(entry["region"])
		var model: MapModel = entry["model"]
		var roster: Array = entry["roster"]
		var works: LandWorks = entry["works"]
		var tech_caps: Dictionary = entry["tech_caps"]
		var context: Dictionary = entry["context"]
		var plan: Dictionary = entry["plan"]
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


## True when any rival holds a declared war on this court: the planner's spy
## preference reads it (wiki: civilian-units § Spies at war). No court, peace.
static func _at_war(play: PlaySession, faction: int) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			return true
	return false


## Where this court musters a colonist: its own harbour, while it has no
## civilian in the other region and a squadron free to carry one. The Explorer
## policy holds an idle Explorer there instead of marching it off to survey
## (AiExplorerWork), so the expedition the colonisation pass plans can board it
## (wiki: civilian-units § Overseas deployment; DR-20261111-05). (-1, -1) when
## nothing is mustering.
static func _muster_port(
	play: PlaySession, faction: int, region: int, model: MapModel
) -> Vector2i:
	if play.world == null or model == null:
		return CivilianState.NO_TILE
	if region != FactionCatalog.region_of(faction):
		return CivilianState.NO_TILE
	var other: int = WorldMap.NEW_WORLD if region == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD
	if _has_owner(_roster(play, other), faction):
		return CivilianState.NO_TILE
	if not _has_free_squadron(play, region, faction):
		return CivilianState.NO_TILE
	var port: int = AiColonisationPlanner.harbour(model, faction)
	if port < 0:
		return CivilianState.NO_TILE
	var data: ProvinceState = model.province_data(port)
	if data == null or data.port_tile.x < 0:
		return CivilianState.NO_TILE
	return data.port_tile


## A squadron of this court that could take a colonist: hulls aloft, no troops
## aboard, and not already carrying one.
static func _has_free_squadron(play: PlaySession, region: int, owner: int) -> bool:
	if play.ship_layer == null:
		return false
	var roster: Array = play.ship_layer.regions.value(region, [])
	for raw: Variant in roster:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner:
			continue
		if not fleet.is_afloat() or fleet.embarked_army >= 0:
			continue
		if fleet.carries_civilians():
			continue
		return true
	return false


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
