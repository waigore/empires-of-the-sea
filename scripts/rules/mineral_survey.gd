class_name MineralSurvey
extends RefCounted
## What a court knows about the ground, and where its Explorer may dig (wiki:
## fog-and-exploration § Prospecting, § Prospect-Required Resources;
## DR-20261111-26). One pure predicate set shared by the work-order rules, the
## dossier, the survey lens and the AI planners (REQ-P3-03).
##
## A mineral is hidden until that court's own Explorer surveys the tile: no
## surface may name, icon, plan on or mine it before then. Terrain-known
## resources (grain, wool, timber, ...) read straight off the chart. Fog levels
## are never changed by a survey — only the deposit becomes known.

## Swamp, hills, mountain and desert are the ground an Explorer can survey.
const PROSPECTABLE_TERRAIN: Array[int] = [
	MapModel.Terrain.SWAMP,
	MapModel.Terrain.HILLS,
	MapModel.Terrain.MOUNTAINS,
	MapModel.Terrain.DESERT,
]


## True when the resource must be uncovered by an Explorer before any court uses
## it (wiki: fog-and-exploration § Prospect-Required Resources).
static func is_mineral(resource: int) -> bool:
	return ImprovementCatalog.needs_prospecting(resource)


## True when the resource shows as soon as the tile is charted.
static func terrain_known(resource: int) -> bool:
	return resource >= 0 and not is_mineral(resource)


## Swamp, hills, mountain or desert: the ground an Explorer can survey.
static func prospectable(model: MapModel, tile: Vector2i) -> bool:
	if model == null or not model.is_land(tile.x, tile.y):
		return false
	return PROSPECTABLE_TERRAIN.has(model.terrain_at(tile.x, tile.y))


## The resource this court may read on the tile, or -1 when the ground is empty
## or the mineral is still hidden. A null `visibility` means "ground this court
## has already charted" (fixtures and the crown's own estates ledger).
static func known_resource(
	model: MapModel,
	works: LandWorks,
	owner: int,
	tile: Vector2i,
	visibility: VisibilityModel = null
) -> int:
	if model == null:
		return -1
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource < 0 or not _charted(visibility, tile):
		return -1
	if is_mineral(resource):
		if works == null or not works.is_prospected(owner, model, tile):
			return -1
	return resource


static func is_known(
	model: MapModel,
	works: LandWorks,
	owner: int,
	tile: Vector2i,
	visibility: VisibilityModel = null
) -> bool:
	return known_resource(model, works, owner, tile, visibility) >= 0


## Why this court cannot survey the tile now, or "" when it may.
static func refusal(
	model: MapModel,
	works: LandWorks,
	owner: int,
	tile: Vector2i,
	visibility: VisibilityModel = null
) -> String:
	if model == null or not model.is_land(tile.x, tile.y):
		return "Explorers survey land, not open water."
	if not _charted(visibility, tile):
		return "Only charted land can be prospected."
	if works != null and works.is_prospected(owner, model, tile):
		return "This tile has already been prospected."
	if terrain_known(model.resource_at(tile.x, tile.y)):
		return "This tile's resource is already known — nothing left to survey."
	if not prospectable(model, tile):
		return "Only swamp, hills, mountain or desert ground can be prospected."
	return ""


static func can_prospect(
	model: MapModel,
	works: LandWorks,
	owner: int,
	tile: Vector2i,
	visibility: VisibilityModel = null
) -> bool:
	return refusal(model, works, owner, tile, visibility).is_empty()


## Every tile in one province this court may still survey, in reading order.
static func unsurveyed_in_province(
	model: MapModel,
	works: LandWorks,
	owner: int,
	province_id: int,
	visibility: VisibilityModel = null
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if model == null:
		return tiles
	for tile: Vector2i in model.province_tiles(province_id):
		if can_prospect(model, works, owner, tile, visibility):
			tiles.append(tile)
	return tiles


## Province id -> count of tiles still to survey, for the survey lens marker.
static func unsurveyed_by_province(
	model: MapModel,
	works: LandWorks,
	owner: int,
	visibility: VisibilityModel = null
) -> Dictionary:
	var counts: Dictionary = {}
	if model == null:
		return counts
	for province: ProvinceState in model.provinces:
		var count: int = unsurveyed_in_province(
			model, works, owner, province.id, visibility
		).size()
		if count > 0:
			counts[province.id] = count
	return counts


## What a finished survey found: the commodity id, or "" for empty ground.
static func find_of(model: MapModel, tile: Vector2i) -> String:
	if model == null:
		return ""
	var resource: int = model.resource_at(tile.x, tile.y)
	if not is_mineral(resource):
		return ""
	return ImprovementCatalog.commodity(resource)


static func _charted(visibility: VisibilityModel, tile: Vector2i) -> bool:
	if visibility == null:
		return true
	return visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.UNKNOWN
