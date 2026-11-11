class_name CapitalChoice
extends RefCounted
## Capital-choice phase (wiki: capital-choice-phase, capital-and-connectivity).
## Auto-choice during setup: sea-bound province -> coastal Class A/B/C tile ->
## convert to plains -> capital ports and roads. A Great Power may also seat its
## court by hand on any owned sea-bound province and any of its land tiles
## (`seat_capital`), which is the interactive phase the setup screen drives.
## Pure logic, no nodes, so the rules run headless and are unit-tested
## (REQ-P3-03, REQ-P2-04).

const KIND_GREAT_POWER: int = 0
const KIND_MINOR: int = 1

const CLASS_A: int = 0
const CLASS_B: int = 1
const CLASS_C: int = 2

const NO_TILE: Vector2i = Vector2i(-1, -1)
const CAPITAL_TOWN_DEVELOPMENT: int = 4
## A province that loses the court keeps its town (wiki: capital-and-connectivity
## § Town per province).
const TOWN_DEVELOPMENT_WITH_TOWN: int = 1

const ERROR_NO_OWNED_PROVINCE: String = "no_owned_capital_province"
const ERROR_NO_SEA_BOUND_PROVINCE: String = "no_sea_bound_capital_province"
const ERROR_NO_CAPITAL_TILE: String = "no_capital_tile_in_province"
const ERROR_NO_COASTAL_TILE: String = "no_coastal_capital_tile_for_gp"
## Interactive seating refusals (wiki: capital-choice-phase § Player choice).
const ERROR_NOT_OWNED: String = "capital_province_not_owned"
const ERROR_NOT_SEA_BOUND: String = "capital_province_not_sea_bound"
const ERROR_TILE_OUTSIDE: String = "capital_tile_outside_province"

const ORTHO: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Runs the phase for every faction, in the order given (GPs, then Minors).
static func place_all(
	model: MapModel, factions: Array[int], kind: int = KIND_GREAT_POWER
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for faction: int in factions:
		results.append(place_capital(model, faction, kind))
	return results


## Places one faction's capital and its ports/roads. On failure the model is
## left untouched and the result carries the setup error code.
static func place_capital(
	model: MapModel, faction_id: int, kind: int = KIND_GREAT_POWER
) -> Dictionary:
	var pick: Dictionary = pick_province(model, faction_id, kind)
	var province_id: int = int(pick["province_id"])
	if province_id < 0:
		return _failure(String(pick["error"]))
	var tile: Vector2i = choose_tile(model, province_id, kind)
	if tile == NO_TILE:
		var code: String = (
			ERROR_NO_COASTAL_TILE if kind == KIND_GREAT_POWER else ERROR_NO_CAPITAL_TILE
		)
		return _failure(code)
	return _apply_capital(model, faction_id, province_id, tile, kind)


# --- interactive seating ----------------------------------------------------


## Whether this province can hold the crown's court: owned and sea-bound.
static func can_seat(model: MapModel, faction_id: int, province_id: int) -> bool:
	var province: ProvinceState = model.get_province(province_id)
	if province == null or province.owner != faction_id:
		return false
	return is_sea_bound(model, province_id)


## Every province this faction may seat its court in: owned and sea-bound,
## ascending. The chart glows exactly these, so the player reads the rule
## instead of learning it from refusals.
static func seatable_provinces(model: MapModel, faction_id: int) -> Array[int]:
	var ids: Array[int] = []
	for id: int in owned_provinces(model, faction_id):
		if is_sea_bound(model, id):
			ids.append(id)
	return ids


## Why this province/tile cannot hold the crown's court, or "" when it can.
static func seat_error(
	model: MapModel, faction_id: int, province_id: int, tile: Vector2i
) -> String:
	var province: ProvinceState = model.get_province(province_id)
	if province == null or province.owner != faction_id:
		return ERROR_NOT_OWNED
	if not is_sea_bound(model, province_id):
		return ERROR_NOT_SEA_BOUND
	if model.province_at(tile.x, tile.y) != province_id:
		return ERROR_TILE_OUTSIDE
	return ""


## Seats a Great Power's court where the player chose it: the province must be
## owned and sea-bound, the tile must be one of its land tiles. The chosen tile
## becomes plains, ports and roads are laid out, and the old seat loses its
## capital works (wiki: capital-choice-phase § Player choice).
static func seat_capital(
	model: MapModel, faction_id: int, province_id: int, tile: Vector2i
) -> Dictionary:
	var error: String = seat_error(model, faction_id, province_id, tile)
	if error != "":
		return _failure(error)
	return _apply_capital(model, faction_id, province_id, tile, KIND_GREAT_POWER)


## The province a court sits in for this faction, or NO_ID when it has none.
static func seat_province(model: MapModel, faction_id: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner == faction_id and province.capital:
			return province.id
	return -1


# --- province choice --------------------------------------------------------


## Great Powers: lowest-id owned sea-bound province, or an error.
## Minors/Tribes: lowest-id owned sea-bound province, else lowest-id inland one.
static func pick_province(
	model: MapModel, faction_id: int, kind: int = KIND_GREAT_POWER
) -> Dictionary:
	var owned: Array[int] = owned_provinces(model, faction_id)
	if owned.is_empty():
		return {"province_id": -1, "error": ERROR_NO_OWNED_PROVINCE}
	var sea_bound: Array[int] = []
	var inland: Array[int] = []
	for id: int in owned:
		if is_sea_bound(model, id):
			sea_bound.append(id)
		else:
			inland.append(id)
	if not sea_bound.is_empty():
		return {"province_id": sea_bound[0], "error": ""}
	if kind == KIND_GREAT_POWER:
		return {"province_id": -1, "error": ERROR_NO_SEA_BOUND_PROVINCE}
	if not inland.is_empty():
		return {"province_id": inland[0], "error": ""}
	return {"province_id": -1, "error": ERROR_NO_SEA_BOUND_PROVINCE}


static func owned_provinces(model: MapModel, faction_id: int) -> Array[int]:
	var owned: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner == faction_id:
			owned.append(province.id)
	owned.sort()
	return owned


## A province is sea-bound when it has at least one P-S edge (wiki: map-topology).
static func is_sea_bound(model: MapModel, province_id: int) -> bool:
	return not sea_bound_sea_zones(model, province_id).is_empty()


## Sea zones adjacent to the province, ascending (one entry per seaboard).
static func sea_bound_sea_zones(model: MapModel, province_id: int) -> Array[int]:
	var zones: Array[int] = []
	for tile: Vector2i in model.province_tiles(province_id):
		for offset: Vector2i in ORTHO:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny) or not model.is_sea(nx, ny):
				continue
			var zone: int = model.sea_zone_at(nx, ny)
			if zone != MapModel.NO_ID and not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


# --- tile choice ------------------------------------------------------------


## Class A: coastal, not adjacent to another province.
## Class B: interior, not adjacent to another province.
## Class C: everything else.
static func tile_class(model: MapModel, province_id: int, tile: Vector2i) -> int:
	if _touches_other_province(model, province_id, tile):
		return CLASS_C
	if MapGeo.is_coastal_tile(model, tile.x, tile.y):
		return CLASS_A
	return CLASS_B


static func choose_tile(
	model: MapModel, province_id: int, kind: int = KIND_GREAT_POWER
) -> Vector2i:
	var groups: Array = _tiles_by_class(model, province_id)
	if kind == KIND_GREAT_POWER:
		var pick_a: Vector2i = _plains_first(model, groups[CLASS_A])
		if pick_a != NO_TILE:
			return pick_a
		var coastal_c: Array = []
		for tile: Vector2i in groups[CLASS_C]:
			if MapGeo.is_coastal_tile(model, tile.x, tile.y):
				coastal_c.append(tile)
		return _plains_first(model, coastal_c)
	for cls: int in [CLASS_A, CLASS_B, CLASS_C]:
		var pick: Vector2i = _plains_first(model, groups[cls])
		if pick != NO_TILE:
			return pick
	return NO_TILE


## Tile lists per class, each in row-major order (y, then x).
static func _tiles_by_class(model: MapModel, province_id: int) -> Array:
	var groups: Array = [[], [], []]
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		tiles.append(tile)
	tiles.sort_custom(_row_major)
	for tile: Vector2i in tiles:
		var cls: int = tile_class(model, province_id, tile)
		var group: Array = groups[cls]
		group.append(tile)
	return groups


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Prefers the first plains tile in the list, else its first tile.
static func _plains_first(model: MapModel, tiles: Array) -> Vector2i:
	for tile: Vector2i in tiles:
		if model.terrain_at(tile.x, tile.y) == MapModel.Terrain.PLAINS:
			return tile
	if tiles.is_empty():
		return NO_TILE
	return tiles[0]


static func _touches_other_province(
	model: MapModel, province_id: int, tile: Vector2i
) -> bool:
	for offset: Vector2i in ORTHO:
		var other: int = model.province_at(tile.x + offset.x, tile.y + offset.y)
		if other != MapModel.NO_ID and other != province_id:
			return true
	return false


## Select-then-convert: the capital tile becomes plains; its resource and
## extraction are cleared (wiki: capital-choice-phase step 3).
static func _convert_to_plains(
	model: MapModel, province_id: int, tile: Vector2i
) -> bool:
	var index: int = model.index_of(tile.x, tile.y)
	var converted: bool = model.terrain[index] != MapModel.Terrain.PLAINS
	model.terrain[index] = MapModel.Terrain.PLAINS
	model.resource[index] = MapModel.NO_ID
	var province: ProvinceState = model.get_province(province_id)
	if province != null:
		province.clear_resource_tile_if(tile)
	return converted


# --- apply ------------------------------------------------------------------


## Records the seat, converts its tile and lays the capital works. Shared by
## auto-choice and interactive seating so both obey the same setup rules.
static func _apply_capital(
	model: MapModel, faction_id: int, province_id: int, tile: Vector2i, kind: int
) -> Dictionary:
	_clear_faction_capitals(model, faction_id)
	var converted: bool = _convert_to_plains(model, province_id, tile)
	var layout: Dictionary = CapitalPorts.layout(
		model, province_id, tile, sea_bound_sea_zones(model, province_id)
	)
	var province: ProvinceState = model.get_province(province_id)
	province.capital = true
	province.capital_tile = tile
	province.town_tile = tile
	province.ports = layout["ports"]
	province.road_paths = layout["road_paths"]
	if kind == KIND_GREAT_POWER:
		province.town_development = CAPITAL_TOWN_DEVELOPMENT
	return {
		"ok": true,
		"error": "",
		"province_id": province_id,
		"tile": tile,
		"ports": province.ports,
		"road_paths": province.road_paths,
		"converted": converted,
	}


## Drops the old seat's capital works on every province this faction owns, so a
## moved court never leaves two capitals (or a harbour in the wrong province).
static func _clear_faction_capitals(model: MapModel, faction_id: int) -> void:
	for province: ProvinceState in model.provinces:
		if province.owner != faction_id:
			continue
		province.capital = false
		province.capital_tile = NO_TILE
		province.ports = {}
		province.road_paths = []
		province.town_development = (
			TOWN_DEVELOPMENT_WITH_TOWN if province.town_tile.x >= 0 else 0
		)


static func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"province_id": -1,
		"tile": NO_TILE,
		"ports": {},
		"road_paths": [],
		"converted": false,
	}
