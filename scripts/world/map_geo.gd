class_name MapGeo
extends RefCounted
## Coastal, neighbor, and world-space queries over a MapModel.
## Split from the tile record so MapModel stays a data holder (REQ-P3-03).


static func is_coastal_tile(model: MapModel, x: int, y: int) -> bool:
	if not model.is_land(x, y):
		return false
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if model.in_bounds(nx, ny) and model.is_sea(nx, ny):
			return true
	return false


static func coastal_tiles(model: MapModel, id: int) -> Array:
	var result: Array = []
	for tile: Vector2i in model.province_tiles(id):
		if is_coastal_tile(model, tile.x, tile.y):
			result.append(tile)
	return result


static func province_neighbors(model: MapModel, id: int) -> Array:
	var data: Dictionary = model.province_data(id)
	if data.is_empty():
		return []
	if data.has("neighbors"):
		return data["neighbors"]
	var found: Array = []
	for tile: Vector2i in model.province_tiles(id):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var other: int = model.province_at(tile.x + offset.x, tile.y + offset.y)
			if other != MapModel.NO_ID and other != id and not found.has(other):
				found.append(other)
	found.sort()
	data["neighbors"] = found
	return found


static func sea_zone_neighbors(model: MapModel, id: int) -> Array:
	var data: Dictionary = model.sea_zone_data(id)
	if data.is_empty():
		return []
	if data.has("neighbors"):
		return data["neighbors"]
	var found: Array = []
	for tile: Vector2i in data.get("tiles", []):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var other: int = model.sea_zone_at(tile.x + offset.x, tile.y + offset.y)
			if other != MapModel.NO_ID and other != id and not found.has(other):
				found.append(other)
	found.sort()
	data["neighbors"] = found
	return found


static func land_tile_count(model: MapModel) -> int:
	var total: int = 0
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y):
				total += 1
	return total


static func tile_center(x: int, y: int, tile_size: float) -> Vector2:
	return Vector2((float(x) + 0.5) * tile_size, (float(y) + 0.5) * tile_size)


static func world_size(model: MapModel, tile_size: float) -> Vector2:
	return Vector2(float(model.width) * tile_size, float(model.height) * tile_size)


static func tile_at_world(world_position: Vector2, tile_size: float) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / tile_size)),
		int(floor(world_position.y / tile_size))
	)
