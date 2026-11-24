class_name AiColonisationVoyage
extends RefCounted
## One colonisation voyage step for a rival court: dock, embark, sail, cross,
## land, or sail a stranded squadron home (wiki: civilian-units § Overseas
## deployment; map-topology § Warp zones; DR-20261109-17, DR-20261110-21).
##
## Ground ranking lives on [AiColonisationGround]; [AiColonisationPlanner] keeps
## the public door and picks which crew sails. Pure rules: state in, one order
## out (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## Boards at the crown's own harbour. The squadron is sent to that port — not to
## whatever province the colonist happens to stand in, which the port and dock
## rules would refuse — and the colonist musters there (AiExplorerWork holds it
## at the muster port while a voyage is pending).
static func board_step(
	model: MapModel, fleet: FleetState, unit: CivilianState, charts: CourtCharts = null
) -> Dictionary:
	# Same reading as AiColonisationPlanner.harbour — kept here so this home
	# never reaches back into the planner door (REQ-P3-01).
	var port: int = MapModel.NO_ID
	if unit.owner >= 0:
		port = NavalMovement.home_harbour(model, unit.owner)
	if port < 0:
		return {}
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if fleet.is_in_port():
		if fleet.province != port:
			var berth: int = sail(
				model, fleet, NavalMovement.province_sea_zones(model, port), charts,
				unit.owner
			)
			if berth < 0:
				return {}
			return {"kind": "sail", "fleet": fleet.id, "zone": berth}
		if province != port:
			return {}
		return {"kind": "embark", "fleet": fleet.id, "unit": unit.id}
	if zone_borders_province(model, fleet.sea_zone, port):
		return {"kind": "dock", "fleet": fleet.id, "province": port}
	var zone: int = sail(
		model, fleet, NavalMovement.province_sea_zones(model, port), charts, unit.owner
	)
	if zone < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": zone}


## One voyage step: cross at a Passage, otherwise sail toward the next waypoint,
## and land as soon as the coast is in reach. `wants_income` is the court's own
## purse footing: an earn court's Explorer aims at the ground worth surveying
## (issue #1382), while every other landing keeps the workshop's appetite.
static func voyage(
	world: WorldMap,
	region: int,
	model: MapModel,
	fleet: FleetState,
	unit: CivilianState,
	target: int,
	charts: CourtCharts,
	appetite: Dictionary = {},
	wants_income: bool = false
) -> Dictionary:
	var riches: int = 0
	if wants_income and unit.type_id == AiColonisationGround.EXPLORER:
		riches = AiColonisationGround.RICHES_GROUND
	if region != target:
		if fleet.is_at_sea() and world.is_warp_zone(region, fleet.sea_zone):
			return {"kind": "cross", "fleet": fleet.id}
		var warp: int = sail(
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
			var left: int = AiColonisationGround.ground_weight(model, a, appetite, riches)
			var right: int = AiColonisationGround.ground_weight(model, b, appetite, riches)
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
	var coast: int = sail(
		model, fleet,
		AiColonisationGround.landing_zones(
			model, unit.type_id, unit.owner, charts, appetite, riches
		),
		charts, unit.owner
	)
	if coast < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": coast}


## A squadron the court left across the water with nothing aboard: afloat,
## un-moved, no colonists and no army. It is free to sail home.
static func stranded_fleet(fleets: Array, owner: int) -> FleetState:
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
static func homeward(
	world: WorldMap, region: int, model: MapModel, fleet: FleetState,
	charts: CourtCharts
) -> Dictionary:
	if world.is_warp_zone(region, fleet.sea_zone):
		return {"kind": "cross", "fleet": fleet.id}
	var warp: int = sail(model, fleet, world.warp_zones(region), charts, fleet.owner)
	if warp < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": warp}


## Next zone toward `goals` on water this court charts (see
## [method AiSeaRoute.sail_charted]); the shared voyage rule keeps the invasion
## and colonisation planners walking the same route (DR-20261110-21).
static func sail(
	model: MapModel, fleet: FleetState, goals: Array[int], charts: CourtCharts, owner: int
) -> int:
	return AiSeaRoute.sail_charted(model, fleet, goals, charts, owner)


static func zone_borders_province(model: MapModel, zone: int, province: int) -> bool:
	return NavalMovement.province_sea_zones(model, province).has(zone)


static func carried_id(fleet: FleetState) -> int:
	if fleet.embarked_civilians.is_empty():
		return -1
	var ids: Array[int] = []
	for raw: Variant in fleet.embarked_civilians:
		ids.append(int(raw))
	ids.sort()
	return ids[0]


static func by_id(civilians: Array, unit_id: int) -> CivilianState:
	for raw: Variant in civilians:
		var unit: CivilianState = raw
		if unit != null and unit.id == unit_id:
			return unit
	return null
