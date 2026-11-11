class_name CivilianPlacement
extends RefCounted
## Capital-seat and free-tile placement for civilian musters. Pure geometry over
## a `MapModel`, so the layer and the capital training rail share one answer
## (REQ-P3-01; wiki: civilian-units).


## Capital seat of a province, or its first land tile when the seat is missing.
static func capital_tile(model: MapModel, province_id: int) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return Vector2i(-1, -1)
	var seat: Vector2i = data.capital_tile
	if seat.x >= 0 and model.is_land(seat.x, seat.y):
		return seat
	var tiles: Array = model.province_tiles(province_id)
	if tiles.is_empty():
		return Vector2i(-1, -1)
	return tiles[0]


## First free land tile of the province, nearest the capital seat.
static func free_tile(
	model: MapModel, province_id: int, anchor: Vector2i, taken: Dictionary
) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var center: Vector2 = Vector2(anchor)
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		if taken.has(tile):
			continue
		candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center)
	)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[0]


## Free land tile near the capital for a freshly trained civilian (-1 when full).
## Spies never block mustering: their tile is invisible to other crowns.
static func mustering_tile(
	model: MapModel, units: Array[CivilianState], province_id: int
) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var seat: Vector2i = capital_tile(model, province_id)
	var taken: Dictionary = {seat: true}
	for unit: CivilianState in units:
		if unit == null or unit.type_id == SpyRules.TYPE:
			continue
		taken[unit.tile] = true
	var tile: Vector2i = free_tile(model, province_id, seat, taken)
	if tile.x >= 0:
		return tile
	taken.erase(seat)
	return free_tile(model, province_id, seat, taken)
