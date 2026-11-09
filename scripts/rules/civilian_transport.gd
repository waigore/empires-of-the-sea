class_name CivilianTransport
extends RefCounted
## Engineer roads/ports and Rail Builder railroads (wiki: civilian-units
## § Work Order Summary; extraction-and-improvements § Road / Railroad Costs).
## Pure rules: costs are paid at assign and never refunded, and the tile only
## changes when the order completes during the Build/Work pass (REQ-P3-03).

const ROAD_COST: Dictionary = {"lumber": 1, "castIron": 1}
const PORT_COST: Dictionary = {"lumber": 5, "castIron": 5}
## Wiki: 2 lumber + 2 steel per railroad.
const RAIL_COST: Dictionary = {"lumber": 2, "steel": 2}
const ROAD_TURNS: int = 1
const PORT_TURNS: int = 2
## The wiki gives railroads a "config" duration; interim until ruleset config.
const RAIL_TURNS: int = 2
const ROAD_CONSTRUCTION: String = "road_construction"
const EARLY_STEAM_ENGINE: String = "early_steam_engine"
const LATER_STEAM_ENGINE: String = "later_steam_engine"
const DYNAMITE: String = "dynamite"
## Railroads need the tech for the tile's terrain (wiki: tech-tree-transport
## § Acceptance Criteria): flat ground with Early Steam Engine, hills and swamps
## with Later Steam Engine, mountains only with Dynamite.
const RAIL_TERRAIN_TECHS: Dictionary = {
	MapModel.Terrain.PLAINS: EARLY_STEAM_ENGINE,
	MapModel.Terrain.HARDWOOD_FOREST: EARLY_STEAM_ENGINE,
	MapModel.Terrain.SCRUB_FOREST: EARLY_STEAM_ENGINE,
	MapModel.Terrain.DESERT: EARLY_STEAM_ENGINE,
	MapModel.Terrain.HILLS: LATER_STEAM_ENGINE,
	MapModel.Terrain.SWAMP: LATER_STEAM_ENGINE,
	MapModel.Terrain.MOUNTAINS: DYNAMITE,
}
const ACTIONS: Array[String] = ["build_road", "build_port", "build_rail"]


static func knows(action: String) -> bool:
	return ACTIONS.has(action)


static func cost(action: String) -> Dictionary:
	match action:
		"build_road":
			return ROAD_COST.duplicate()
		"build_port":
			return PORT_COST.duplicate()
		"build_rail":
			return RAIL_COST.duplicate()
	return {}


static func turns(action: String) -> int:
	match action:
		"build_road":
			return ROAD_TURNS
		"build_port":
			return PORT_TURNS
		"build_rail":
			return RAIL_TURNS
	return 1


## Terrain-specific rail techs are not modelled yet: Early Steam Engine is the
## one gate the catalog ships (wiki: tech-tree § transport).
static func check(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	units: Array[CivilianState],
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var province: int = model.province_at(tile.x, tile.y)
	if model.owner_at(tile.x, tile.y) != unit.owner:
		return _no("This land is not held by your crown.")
	match action:
		"build_road":
			return _check_road(model, unit, tile, works, units, tech_unlocked)
		"build_port":
			return _check_port(model, unit, province, tile, works, units)
		"build_rail":
			return _check_rail(model, tile, works, tech_unlocked)
	return _no("The %s has no such work order." % unit.display_name())


## Applies the completed order to the tile and returns the changed tile indices.
static func apply(model: MapModel, action: String, tile: Vector2i, works: LandWorks) -> Array:
	match action:
		"build_road":
			var level: int = works.transport_at(model, tile)
			works.set_transport(model, tile, mini(level + 1, LandWorks.TRANSPORT_IMPROVED_ROAD))
		"build_port":
			works.add_port(model, tile)
		"build_rail":
			works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return [model.index_of(tile.x, tile.y)]


# --- action checks ----------------------------------------------------------


static func _check_road(
	model: MapModel,
	unit: CivilianState,
	tile: Vector2i,
	works: LandWorks,
	units: Array[CivilianState],
	tech_unlocked: Dictionary
) -> Dictionary:
	var level: int = works.transport_at(model, tile)
	if level >= LandWorks.TRANSPORT_IMPROVED_ROAD:
		return _no("This tile already has an improved road.")
	if works.has_port(model, tile):
		return _no("This tile already carries a port.")
	if level >= LandWorks.TRANSPORT_ROAD and not _has(tech_unlocked, ROAD_CONSTRUCTION):
		return _no("This tile already has a road; research Road Construction to raise it.")
	return exclusive(units, unit, tile)


static func _check_port(
	model: MapModel,
	unit: CivilianState,
	province: int,
	tile: Vector2i,
	works: LandWorks,
	units: Array[CivilianState]
) -> Dictionary:
	if not MapGeo.is_coastal_tile(model, tile.x, tile.y):
		return _no("Ports need a coastal tile.")
	if works.province_has_port(model, province):
		return _no("%s already has a port." % model.province_name(province))
	return exclusive(units, unit, tile)


static func _check_rail(
	model: MapModel, tile: Vector2i, works: LandWorks, tech_unlocked: Dictionary
) -> Dictionary:
	var level: int = works.transport_at(model, tile)
	if level >= LandWorks.TRANSPORT_RAIL:
		return _no("This tile already carries a railroad.")
	if level < LandWorks.TRANSPORT_ROAD:
		return _no("Railroads upgrade an existing road.")
	var needed: String = rail_tech_for(model.terrain_at(tile.x, tile.y))
	if not _has(tech_unlocked, needed):
		return _no("Requires %s to lay a railroad here." % TechCatalog.display_name(needed))
	return {"ok": true}


## Tech a railroad needs on this terrain; flat ground falls back to Early Steam
## Engine, the Rail Builder's own unlock (wiki: tech-tree-transport).
static func rail_tech_for(terrain: int) -> String:
	return String(RAIL_TERRAIN_TECHS.get(terrain, EARLY_STEAM_ENGINE))


## One Builder/Engineer work order per player and tile; Rail Builders are exempt
## (wiki: civilian-units § Per-player tile exclusivity).
static func exclusive(
	units: Array[CivilianState], unit: CivilianState, tile: Vector2i
) -> Dictionary:
	for other: CivilianState in units:
		if other == null or other == unit or other.owner != unit.owner:
			continue
		if other.is_working() and other.work_tile() == tile:
			return _no("Another crew is already working this tile.")
	return {"ok": true}


static func _has(tech_unlocked: Dictionary, tech_id: String) -> bool:
	return bool(tech_unlocked.get(tech_id, false))


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}
