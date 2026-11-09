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
## `civilians_in_target` lets the adapter avoid a second expedition when the
## destination roster already holds one of its units.
static func plan(
	config: AiConfig,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	civilians: Array,
	civilians_in_target: int = 0
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
	if fleet != null:
		var unit: CivilianState = _by_id(civilians, _carried_id(fleet))
		if unit == null:
			return {}
		return _voyage(world, region, model, fleet, unit, target)
	if region != home or civilians_in_target > 0:
		return {}
	var unit: CivilianState = _next_colonist(civilians, owner, target, world)
	if unit == null:
		return {}
	fleet = _idle_fleet(fleets, owner)
	if fleet == null:
		return {}
	return _board_step(model, fleet, unit)


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


## First idle civilian that can land in the target: a Builder for owned
## colonies, an Explorer for a coast without crown land.
static func _next_colonist(
	civilians: Array, owner: int, target: int, world: WorldMap
) -> CivilianState:
	var wanted: String = "builder" if _owns_land_in(world, target, owner) else "explorer"
	var fallback: CivilianState = null
	for raw: Variant in civilians:
		var unit: CivilianState = raw
		if unit == null or unit.owner != owner:
			continue
		if unit.is_working() or unit.moved or unit.is_embarked():
			continue
		if unit.type_id == wanted:
			return unit
		if fallback == null and unit.type_id == "explorer":
			fallback = unit
	return fallback


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


## Dock at the colonist's port, or take it aboard when already there.
static func _board_step(
	model: MapModel, fleet: FleetState, unit: CivilianState
) -> Dictionary:
	if fleet.is_in_port():
		if fleet.province == model.province_at(unit.tile.x, unit.tile.y):
			return {"kind": "embark", "fleet": fleet.id, "unit": unit.id}
		return {}
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if province == MapModel.NO_ID:
		return {}
	if _zone_borders_province(model, fleet.sea_zone, province):
		return {"kind": "dock", "fleet": fleet.id, "province": province}
	var zone: int = AiSeaRoute.step_toward(
		model, fleet.sea_zone, NavalMovement.province_sea_zones(model, province)
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
	target: int
) -> Dictionary:
	if region != target:
		if fleet.is_at_sea() and world.is_warp_zone(region, fleet.sea_zone):
			return {"kind": "cross", "fleet": fleet.id}
		var warp: int = AiSeaRoute.sail_toward(model, fleet, world.warp_zones(region))
		if warp < 0:
			return {}
		return {"kind": "sail", "fleet": fleet.id, "zone": warp}
	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(model, unit, fleet)
	if not tiles.is_empty():
		tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		return {
			"kind": "land", "fleet": fleet.id, "unit": unit.id, "tile": tiles[0],
		}
	var coast: int = AiSeaRoute.sail_toward(
		model, fleet, _landing_zones(model, unit.type_id, unit.owner)
	)
	if coast < 0:
		return {}
	return {"kind": "sail", "fleet": fleet.id, "zone": coast}


## Sea zones with at least one land tile this type may land on.
static func _landing_zones(model: MapModel, type_id: String, owner: int) -> Array[int]:
	var zones: Array[int] = []
	for zone: SeaZoneState in model.sea_zones:
		for water: Vector2i in zone.tiles:
			for tile: Vector2i in CivilianMovement.NEIGHBORS:
				var land: Vector2i = water + tile
				if not model.in_bounds(land.x, land.y) or not model.is_land(land.x, land.y):
					continue
				if not CivilianMovement.may_enter(model, type_id, owner, land):
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
