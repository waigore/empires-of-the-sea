class_name ProspectRules
extends RefCounted
## Explorer prospecting: uncover a hidden mineral (or nothing) on prospectable
## terrain (wiki: fog-and-exploration § Prospecting; DR-20261111-26). Pure rules
## shared by work validation, survey, UI and AI (REQ-P3-03).


const PROSPECTABLE_TERRAIN: Array[int] = [
	MapModel.Terrain.SWAMP,
	MapModel.Terrain.HILLS,
	MapModel.Terrain.MOUNTAINS,
	MapModel.Terrain.DESERT,
]


## True when the terrain may host a hidden mineral survey.
static func is_prospectable_terrain(terrain: int) -> bool:
	return PROSPECTABLE_TERRAIN.has(terrain)


## Resource id the court may see on this tile: minerals stay hidden until that
## court has prospected; terrain-known resources show when the tile is charted.
static func known_resource(
	owner: int, model: MapModel, tile: Vector2i, works: LandWorks
) -> int:
	if model == null or not model.in_bounds(tile.x, tile.y):
		return MapModel.NO_ID
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource == MapModel.NO_ID:
		return MapModel.NO_ID
	if not ImprovementCatalog.needs_prospecting(resource):
		return resource
	if works != null and works.is_prospected(owner, model, tile):
		return resource
	return MapModel.NO_ID


## Empty string when Prospect may start; otherwise the first refusal reason.
## Chart/consulate gates stay on CivilianExplorerGates; this covers terrain and
## surface-resource eligibility (DR-20261111-26).
static func tile_refusal(
	model: MapModel, owner: int, tile: Vector2i, works: LandWorks
) -> String:
	if works != null and works.is_prospected(owner, model, tile):
		return "This tile has already been prospected."
	var terrain: int = model.terrain_at(tile.x, tile.y)
	if not is_prospectable_terrain(terrain):
		return "Only swamp, hills, mountain and desert can be prospected."
	var known: int = known_resource(owner, model, tile, works)
	if known != MapModel.NO_ID and not ImprovementCatalog.needs_prospecting(known):
		return "This tile already shows a surface resource."
	return ""


## Short find line after Prospect completes for toasts (REQ-P5-05).
static func find_label(model: MapModel, tile: Vector2i) -> String:
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource == MapModel.NO_ID or not ImprovementCatalog.needs_prospecting(resource):
		return "no mineral"
	var name: String = String(MapGenerator.resource_info(resource).get("name", "mineral"))
	return name.to_lower()
