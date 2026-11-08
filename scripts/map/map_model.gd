# gdlint: disable=max-public-methods
class_name MapModel
extends RefCounted
## Tile data for one region (wiki: tile-map-and-generation).
## Pure data: no nodes, no rendering, so rules and tests can run headless (REQ-P3-03).

enum Terrain { OCEAN, SHALLOW, PLAINS, FOREST, HILLS, MOUNTAINS, DESERT, SWAMP }

const NO_ID: int = -1

const TERRAIN_LABELS: Dictionary = {
	Terrain.OCEAN: "Open sea",
	Terrain.SHALLOW: "Coastal waters",
	Terrain.PLAINS: "Plains",
	Terrain.FOREST: "Forest",
	Terrain.HILLS: "Hills",
	Terrain.MOUNTAINS: "Mountains",
	Terrain.DESERT: "Desert",
	Terrain.SWAMP: "Marsh",
}

var width: int = 0
var height: int = 0
## Region this grid belongs to (wiki: map-topology — one tile map per region).
var region_id: int = FactionCatalog.OLD_WORLD
var region_key: String = "old_world"
## Faction ids configured in this region (GPs + Minors, or Tribes).
var faction_ids: Array[int] = []
## Setup errors raised while populating this region (empty on success).
var setup_errors: Array[String] = []
var terrain: PackedByteArray = PackedByteArray()
var province: PackedInt32Array = PackedInt32Array()
var sea_zone: PackedInt32Array = PackedInt32Array()
var resource: PackedInt32Array = PackedInt32Array()
var provinces: Array[Dictionary] = []
var sea_zones: Array[Dictionary] = []


func setup(p_width: int, p_height: int) -> void:
	width = maxi(p_width, 1)
	height = maxi(p_height, 1)
	var count: int = width * height
	terrain.resize(count)
	terrain.fill(Terrain.OCEAN)
	province.resize(count)
	province.fill(NO_ID)
	sea_zone.resize(count)
	sea_zone.fill(NO_ID)
	resource.resize(count)
	resource.fill(NO_ID)
	provinces.clear()
	sea_zones.clear()


func index_of(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func terrain_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Terrain.OCEAN
	return terrain[index_of(x, y)]


func is_land(x: int, y: int) -> bool:
	var value: int = terrain_at(x, y)
	return value != Terrain.OCEAN and value != Terrain.SHALLOW


func is_sea(x: int, y: int) -> bool:
	return not is_land(x, y)


func province_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_ID
	return province[index_of(x, y)]


func sea_zone_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_ID
	return sea_zone[index_of(x, y)]


func resource_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_ID
	return resource[index_of(x, y)]


func province_count() -> int:
	return provinces.size()


func sea_zone_count() -> int:
	return sea_zones.size()


func province_data(id: int) -> Dictionary:
	if id < 0 or id >= provinces.size():
		return {}
	return provinces[id]


func sea_zone_data(id: int) -> Dictionary:
	if id < 0 or id >= sea_zones.size():
		return {}
	return sea_zones[id]


func province_tiles(id: int) -> Array:
	var data: Dictionary = province_data(id)
	if data.is_empty():
		return []
	return data.get("tiles", [])


func province_center(id: int) -> Vector2:
	var data: Dictionary = province_data(id)
	if data.is_empty():
		return Vector2.ZERO
	return data.get("center", Vector2.ZERO)


func sea_zone_center(id: int) -> Vector2:
	var data: Dictionary = sea_zone_data(id)
	if data.is_empty():
		return Vector2.ZERO
	return data.get("center", Vector2.ZERO)


func province_owner(id: int) -> int:
	var data: Dictionary = province_data(id)
	if data.is_empty():
		return NO_ID
	return data.get("owner", NO_ID)


## Owner of the province covering a tile, or NO_ID for sea and unclaimed land.
func owner_at(x: int, y: int) -> int:
	var id: int = province_at(x, y)
	if id == NO_ID:
		return NO_ID
	return province_owner(id)


func province_name(id: int) -> String:
	var data: Dictionary = province_data(id)
	if data.is_empty():
		return ""
	return data.get("name", "")


func sea_zone_name(id: int) -> String:
	var data: Dictionary = sea_zone_data(id)
	if data.is_empty():
		return ""
	return data.get("name", "")


func is_coastal_tile(x: int, y: int) -> bool:
	if not is_land(x, y):
		return false
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if in_bounds(nx, ny) and is_sea(nx, ny):
			return true
	return false


func coastal_tiles(id: int) -> Array:
	var result: Array = []
	for tile: Vector2i in province_tiles(id):
		if is_coastal_tile(tile.x, tile.y):
			result.append(tile)
	return result


func province_neighbors(id: int) -> Array:
	var data: Dictionary = province_data(id)
	if data.is_empty():
		return []
	if data.has("neighbors"):
		return data["neighbors"]
	var found: Array = []
	for tile: Vector2i in province_tiles(id):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var other: int = province_at(tile.x + offset.x, tile.y + offset.y)
			if other != NO_ID and other != id and not found.has(other):
				found.append(other)
	found.sort()
	data["neighbors"] = found
	return found


func sea_zone_neighbors(id: int) -> Array:
	var data: Dictionary = sea_zone_data(id)
	if data.is_empty():
		return []
	if data.has("neighbors"):
		return data["neighbors"]
	var found: Array = []
	for tile: Vector2i in data.get("tiles", []):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var other: int = sea_zone_at(tile.x + offset.x, tile.y + offset.y)
			if other != NO_ID and other != id and not found.has(other):
				found.append(other)
	found.sort()
	data["neighbors"] = found
	return found


func land_tile_count() -> int:
	var total: int = 0
	for y in height:
		for x in width:
			if is_land(x, y):
				total += 1
	return total


func tile_center(x: int, y: int, tile_size: float) -> Vector2:
	return Vector2((float(x) + 0.5) * tile_size, (float(y) + 0.5) * tile_size)


func world_size(tile_size: float) -> Vector2:
	return Vector2(float(width) * tile_size, float(height) * tile_size)


func tile_at_world(world_position: Vector2, tile_size: float) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / tile_size)),
		int(floor(world_position.y / tile_size))
	)
