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
	wants_income: bool = false
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
	var fleet: FleetState = _carrying_fleet(fleets, owner)
	if fleet == null and AiPhasePlanner.is_war_footing(posture) and not wants_income:
		return {}
	if fleet != null:
		var carried: CivilianState = _by_id(civilians, _carried_id(fleet))
		if carried == null:
			return {}
		return _voyage(world, region, model, fleet, carried, target, charts)
	if region != home:
		return {}
	var unit: CivilianState = _voyage_unit(civilians, owner, world, target, abroad)
	if unit == null:
		return {}
	fleet = _idle_fleet(fleets, owner)
	if fleet == null:
		return {}
	return _board_step(model, fleet, unit, charts)


## The harbour a rival's expedition musters at: its seat when the seat has a
## port, else its lowest-id port province. -1 when the crown owns no harbour,
## which is the one case a voyage cannot start (wiki: ships-and-naval § Home
## Fleet; civilian-units § Overseas deployment).
static func harbour(model: MapModel, owner: int) -> int:
	if model == null or owner < 0:
		return MapModel.NO_ID
	var best: int = MapModel.NO_ID
	for province: ProvinceState in model.provinces:
		if province.owner != owner or not NavalMovement.has_harbour(model, province.id):
			continue
		if province.capital:
			return province.id
		if best == MapModel.NO_ID or province.id < best:
			best = province.id
	return best


## The other region when the crown has land there, else the New World from the
## Old World. A court already abroad with land at home never sails back here.
static func _target_region(world: WorldMap, home: int, owner: int) -> int:
	if home == WorldMap.OLD_WORLD:
		return WorldMap.NEW_WORLD
	if _owns_land_in(world, WorldMap.OLD_WORLD, owner):
		return WorldMap.OLD_WORLD
	return -1


static func _owns_land_in(world: WorldMap, region: int, owner: int) -> bool:
	var model: MapModel = world.region(region)
	if model == null:
		return false
	for province: ProvinceState in model.provinces:
		if province.owner == owner:
			return true
	return false


## First idle civilian the court should send, or null. A crown that owns land
## overseas sends its Builder to work it; otherwise it charts with an Explorer
## (wiki: civilian-units § Overseas deployment). One colonist of each kind at a
## time, so the expedition is not duplicated.
static func _voyage_unit(
	civilians: Array, owner: int, world: WorldMap, target: int, abroad: Dictionary
) -> CivilianState:
	if _owns_land_in(world, target, owner):
		var builder: CivilianState = _idle_colonist(civilians, owner, "builder")
		if builder != null:
			return builder
	if int(abroad.get("explorer", 0)) > 0:
		return null
	return _idle_colonist(civilians, owner, "explorer")


## First free civilian of one type: not working, not already abroad, not spent
## this turn. Lowest id, so the same state always sends the same colonist.
static func _idle_colonist(
	civilians: Array, owner: int, type_id: String
) -> CivilianState:
	for raw: Variant in civilians:
		var unit: CivilianState = raw
		if unit == null or unit.owner != owner or unit.type_id != type_id:
			continue
		if unit.is_working() or unit.moved or unit.is_embarked():
			continue
		return unit
	return null


## Lowest-id squadron that can still move; an expedition keeps the same hulls
## for the whole crossing.
static func _idle_fleet(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved:
			continue
		if not fleet.is_afloat() or fleet.embarked_army >= 0:
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


static func _carrying_fleet(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved:
			continue
		if not fleet.carries_civilians():
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


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
	charts: CourtCharts
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
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		return {
			"kind": "land", "fleet": fleet.id, "unit": unit.id, "tile": tiles[0],
		}
	var coast: int = _sail(
		model, fleet, _landing_zones(model, unit.type_id, unit.owner, charts),
		charts, unit.owner
	)
	if coast < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": coast}


## The next zone toward `goals`, walking only water this court charts. With no
## charted route it takes the lowest-id adjacent zone it has not seen: that blind
## step is how a passage or a far coast is found (DR-20261110-21).
static func _sail(
	model: MapModel, fleet: FleetState, goals: Array[int], charts: CourtCharts, owner: int
) -> int:
	if charts == null:
		return AiSeaRoute.sail_toward(model, fleet, goals)
	var known: Array[int] = charts.known_zones(owner, model.region_id)
	var charted: Array[int] = []
	for zone: int in goals:
		if known.has(zone):
			charted.append(zone)
	if not charted.is_empty():
		var step: int = AiSeaRoute.sail_toward(model, fleet, charted)
		if step >= 0:
			return step
	for zone: int in NavalMovement.destination_zones(model, fleet):
		if not known.has(zone):
			return zone
	return -1


## Sea zones with at least one land tile this type may land on, and whose water
## the court has charted.
static func _landing_zones(
	model: MapModel, type_id: String, owner: int, charts: CourtCharts = null
) -> Array[int]:
	var zones: Array[int] = []
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
				if not zones.has(zone.id):
					zones.append(zone.id)
				break
			if zones.has(zone.id):
				break
	zones.sort()
	return zones


static func _zone_borders_province(model: MapModel, zone: int, province: int) -> bool:
	return NavalMovement.province_sea_zones(model, province).has(zone)


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
