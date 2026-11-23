class_name AiColonisationPlanner
extends RefCounted
## Rival colonisation voyages (wiki: civilian-units § Overseas deployment;
## map-topology § Warp zones; DR-20261109-17).
##
## A Great Power reaches the New World the same way the player does: an idle
## civilian boards a crown squadron, the squadron crosses a Passage, and the
## civilian lands on the far coast. This planner chooses one legal step per turn
## for one court — dock, embark, sail, cross or land — and leaves every gate to
## CivilianVoyage, NavalMovement and WarpTravel (REQ-P2-03, REQ-P3-03).
##
## Rivals with overseas provinces send a Builder to work them; a crown with no
## New World land sends an Explorer to chart it. The existing civilian planner
## takes over once the colonist is ashore.
##
## **The ground is read, not picked by the compass** (DR-20261119-05): a landing
## is the one tile a court takes overseas, and the published walk landed on the
## north-easternmost charted coast whatever it grew — so no rival court ever held
## sugar cane, tobacco or furs, and the catalogue's luxury rows waited on a raw no
## crown brought home. `appetite` (commodity → weight) names the raws this court's
## own workshop can turn and does not hold in number: the best such ground wins,
## the compass order breaks ties, and a caller that reads no appetite keeps the
## published order tile for tile.
##
## **The treasury is read beside the workshop** (issue #1382): the appetite may
## also carry a `riches` weight (`economy.riches_route_weight`, set by
## `AiEconomyPlanner.ground_appetite` once the court charts the New World), which
## `_ground_weight` puts on mineral-bearing terrain — the ground an Explorer can
## survey — without ever naming a mineral.
const RICHES_KEY: String = "riches"


## One order for this court in this region, or an empty dictionary.
## `abroad` counts this court's civilians already in the target region, by type,
## so a court sends one Explorer to chart it and, once it holds land there, one
## Builder to work it. `charts` is the court's own fog: it lands only on coast it
## has seen and walks only water it charts, with one blind step into the unknown
## to extend the chart (DR-20261110-21). A null chart is the fixture reading —
## every tile charted — and production always hands the court's charts in
## (MapPlayColonisationAi). `posture` is the court's war footing: a court
## fighting a Great Power opens no new voyage, while an expedition already afloat
## keeps sailing (wiki: phase-planner-architecture § Playable slice;
## DR-20261113-15) — unless it is on **earn**, whose gold is across the water
## (DR-20261113-19).
static func plan(
	config: AiConfig,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	civilians: Array,
	abroad: Dictionary = {},
	charts: CourtCharts = null,
	posture: String = AiPhasePlanner.PHASE_UNKNOWN,
	wants_income: bool = false,
	appetite: Dictionary = {}
) -> Dictionary:
	if config == null or world == null or model == null:
		return {}
	var owner: int = config.faction
	var home: int = FactionCatalog.region_of(owner)
	if home < 0:
		return {}
	var target: int = _target_region(world, home, owner)
	if target < 0:
		return {}
	var fleet: FleetState = VoyageRead.carrying(fleets, owner, true)
	if fleet != null:
		var carried: CivilianState = _by_id(civilians, _carried_id(fleet))
		if carried == null:
			return {}
		return _voyage(world, region, model, fleet, carried, target, charts, appetite)
	if region != home:
		# No colonist aboard: a squadron left across the water sails home, so the
		# court's hulls are not stranded there for the rest of the campaign (they
		# carry the next voyage and an overseas invasion).
		var stranded: FleetState = _stranded_fleet(fleets, owner)
		if stranded != null:
			return _homeward(world, region, model, stranded, charts)
		return {}
	if not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_VOYAGE) and not wants_income:
		return {}
	var unit: CivilianState = _voyage_unit(civilians, owner, world, target, abroad)
	if unit == null:
		return {}
	fleet = VoyageRead.free_squadron(fleets, owner)
	if fleet == null:
		return {}
	return _board_step(model, fleet, unit, charts)


## The harbour a rival's expedition musters at: its seat when the seat has a
## port, else its lowest-id port province. -1 when the crown owns no harbour,
## which is the one case a voyage cannot start (wiki: ships-and-naval § Home
## Fleet; civilian-units § Overseas deployment). One reading serves every
## planner (`NavalMovement.home_harbour`).
static func harbour(model: MapModel, owner: int) -> int:
	if owner < 0:
		return MapModel.NO_ID
	return NavalMovement.home_harbour(model, owner)


## The other region when the crown has land there, else the New World from the
## Old World. A court already abroad with land at home never sails back here.
static func _target_region(world: WorldMap, home: int, owner: int) -> int:
	if home == WorldMap.OLD_WORLD:
		return WorldMap.NEW_WORLD
	if VoyageRead.owns_land_in(world, WorldMap.OLD_WORLD, owner):
		return WorldMap.OLD_WORLD
	return -1


## First idle civilian the court should send, or null. A crown that holds ground
## overseas sends its Builder to work it; a crown whose Explorer is already
## ashore sends the Merchant, whose deeds found the colony; otherwise it charts
## with an Explorer (wiki: civilian-units § Overseas deployment; #497, #602,
## #1127). One colonist of each kind at a time, so the expedition is not
## duplicated, and the kind is `VoyageRead.voyage_kind` — the same reading the
## muster holds the crew behind at the harbour.
static func _voyage_unit(
	civilians: Array, owner: int, world: WorldMap, target: int, abroad: Dictionary
) -> CivilianState:
	var kind: String = VoyageRead.voyage_kind(
		VoyageRead.holds_ground_in(world, target, owner), abroad
	)
	var unit: CivilianState = _idle_of(civilians, owner, kind, abroad)
	if unit != null or kind != "builder":
		return unit
	# No Builder free to work the crown's ground: the Explorer charts instead,
	# as published.
	return _idle_of(civilians, owner, VoyageRead.voyage_kind(false, abroad), abroad)


## One idle colonist of `kind`, or null when one of that kind is already abroad:
## one crew of each kind sails at a time, so the claim is never doubled.
static func _idle_of(
	civilians: Array, owner: int, kind: String, abroad: Dictionary
) -> CivilianState:
	if int(abroad.get(kind, 0)) > 0:
		return null
	return VoyageRead.idle_colonist(civilians, owner, kind)


## Boards at the crown's own harbour. The squadron is sent to that port — not to
## whatever province the colonist happens to stand in, which the port and dock
## rules would refuse — and the colonist musters there (AiExplorerWork holds it
## at the muster port while a voyage is pending).
static func _board_step(
	model: MapModel, fleet: FleetState, unit: CivilianState, charts: CourtCharts = null
) -> Dictionary:
	var port: int = harbour(model, unit.owner)
	if port < 0:
		return {}
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if fleet.is_in_port():
		if fleet.province != port:
			var berth: int = _sail(
				model, fleet, NavalMovement.province_sea_zones(model, port), charts,
				unit.owner
			)
			if berth < 0:
				return {}
			return {"kind": "sail", "fleet": fleet.id, "zone": berth}
		if province != port:
			return {}
		return {"kind": "embark", "fleet": fleet.id, "unit": unit.id}
	if _zone_borders_province(model, fleet.sea_zone, port):
		return {"kind": "dock", "fleet": fleet.id, "province": port}
	var zone: int = _sail(
		model, fleet, NavalMovement.province_sea_zones(model, port), charts, unit.owner
	)
	if zone < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": zone}


## One voyage step: cross at a Passage, otherwise sail toward the next waypoint,
## and land as soon as the coast is in reach.
static func _voyage(
	world: WorldMap,
	region: int,
	model: MapModel,
	fleet: FleetState,
	unit: CivilianState,
	target: int,
	charts: CourtCharts,
	appetite: Dictionary = {}
) -> Dictionary:
	if region != target:
		if fleet.is_at_sea() and world.is_warp_zone(region, fleet.sea_zone):
			return {"kind": "cross", "fleet": fleet.id}
		var warp: int = _sail(
			model, fleet, world.warp_zones(region), charts, unit.owner
		)
		if warp < 0:
			return {}
		return {"kind": "sail", "fleet": fleet.id, "zone": warp}
	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(model, unit, fleet)
	if charts != null:
		tiles = charts.charted_tiles(unit.owner, model.region_id, tiles)
	if not tiles.is_empty():
		tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var left: int = _ground_weight(model, a, appetite)
			var right: int = _ground_weight(model, b, appetite)
			if left != right:
				return left > right
			# The published compass order breaks every tie, so a court that reads
			# no appetite lands exactly where it did before (DR-20261119-05).
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		return {
			"kind": "land", "fleet": fleet.id, "unit": unit.id, "tile": tiles[0],
		}
	var coast: int = _sail(
		model, fleet, _landing_zones(model, unit.type_id, unit.owner, charts, appetite),
		charts, unit.owner
	)
	if coast < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": coast}


## A squadron the court left across the water with nothing aboard: afloat,
## un-moved, no colonists and no army. It is free to sail home.
static func _stranded_fleet(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved:
			continue
		if not fleet.is_at_sea() or not VoyageRead.is_free(fleet):
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


## One step home: cross at the Passage, otherwise sail toward the next waypoint.
## The squadron docks at its own harbour once it is back in the home region.
static func _homeward(
	world: WorldMap, region: int, model: MapModel, fleet: FleetState,
	charts: CourtCharts
) -> Dictionary:
	if world.is_warp_zone(region, fleet.sea_zone):
		return {"kind": "cross", "fleet": fleet.id}
	var warp: int = _sail(model, fleet, world.warp_zones(region), charts, fleet.owner)
	if warp < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": warp}


## Next zone toward `goals` on water this court charts (see
## [method AiSeaRoute.sail_charted]); the shared voyage rule keeps the invasion
## and colonisation planners walking the same route (DR-20261110-21).
static func _sail(
	model: MapModel, fleet: FleetState, goals: Array[int], charts: CourtCharts, owner: int
) -> int:
	return AiSeaRoute.sail_charted(model, fleet, goals, charts, owner)


## Sea zones with at least one land tile this type may land on, and whose water
## the court has charted. A zone that fronts a ground the court's workshop turns
## comes first, so the expedition sails for the coast that grows what it needs
## (DR-20261119-05); the zone id breaks every tie, so a caller with no appetite
## keeps the published order.
static func _landing_zones(
	model: MapModel, type_id: String, owner: int, charts: CourtCharts = null,
	appetite: Dictionary = {}
) -> Array[int]:
	var weights: Dictionary = {}
	for zone: SeaZoneState in model.sea_zones:
		if charts != null and not charts.knows_zone(owner, model.region_id, zone.id):
			continue
		for water: Vector2i in zone.tiles:
			for tile: Vector2i in CivilianMovement.NEIGHBORS:
				var land: Vector2i = water + tile
				if not model.in_bounds(land.x, land.y) or not model.is_land(land.x, land.y):
					continue
				if not CivilianMovement.may_enter(model, type_id, owner, land):
					continue
				if charts != null:
					var view: VisibilityModel = charts.model_for(owner, model.region_id)
					if view != null and view.level_at(land.x, land.y) < VisibilityModel.Level.FOGGED:
						continue
				var weight: int = _ground_weight(model, land, appetite)
				if not weights.has(zone.id) or weight > int(weights[zone.id]):
					weights[zone.id] = weight
	var zones: Array[int] = []
	for id: Variant in weights.keys():
		zones.append(int(id))
	zones.sort_custom(func(a: int, b: int) -> bool:
		if int(weights[a]) != int(weights[b]):
			return int(weights[a]) > int(weights[b])
		return a < b
	)
	return zones


static func _zone_borders_province(model: MapModel, zone: int, province: int) -> bool:
	return NavalMovement.province_sea_zones(model, province).has(zone)


## How much this ground is worth to the court's workshop: the appetite weight of
## the commodity the tile carries, else zero. A ground nobody can read (no raw,
## or a mineral the chart never shows unprospected) weighs nothing, so the
## compass order decides it (DR-20261119-05).
##
## The treasury is read beside the workshop (issue #1382): on prospectable
## ground (swamp, hills, mountain, desert) the tile also takes the appetite's
## `riches` weight — `economy.riches_route_weight`, set once the court charts
## the New World — the bigger read winning. No mineral is named, priced or
## planned on: the weight rides the terrain, not a deposit, so the fog rule
## holds (DR-20261111-26) and the appetite's own mineral exclusion stands. A
## tile that also grows a wanted crop wins by the bigger read, so a riches
## tie-break never starves a recipe the workshop feeds.
static func _ground_weight(model: MapModel, tile: Vector2i, appetite: Dictionary) -> int:
	if appetite.is_empty():
		return 0
	var weight: int = 0
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource >= 0:
		var commodity: String = ImprovementCatalog.commodity(resource)
		if not commodity.is_empty():
			weight = maxi(int(appetite.get(commodity, 0)), 0)
	if MineralSurvey.prospectable(model, tile):
		weight = maxi(weight, int(appetite.get(RICHES_KEY, 0)))
	return weight


static func _carried_id(fleet: FleetState) -> int:
	if fleet.embarked_civilians.is_empty():
		return -1
	var ids: Array[int] = []
	for raw: Variant in fleet.embarked_civilians:
		ids.append(int(raw))
	ids.sort()
	return ids[0]


static func _by_id(civilians: Array, unit_id: int) -> CivilianState:
	for raw: Variant in civilians:
		var unit: CivilianState = raw
		if unit != null and unit.id == unit_id:
			return unit
	return null
