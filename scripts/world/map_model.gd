class_name MapModel
extends RefCounted
## Tile data for one region (wiki: tile-map-and-generation).
## Pure data: no nodes, no rendering, so rules and tests can run headless (REQ-P3-03).
## Coastal, neighbor, and world-space queries live on MapGeo.

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
## Tile-level deeds (purchased land); plain provinces inherit their owner.
var ownership := TileOwnership.new()
var provinces: Array[ProvinceState] = []
var sea_zones: Array[SeaZoneState] = []


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
	ownership.clear()
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


func get_province(id: int) -> ProvinceState:
	if id < 0 or id >= provinces.size():
		return null
	return provinces[id]


func get_sea_zone(id: int) -> SeaZoneState:
	if id < 0 or id >= sea_zones.size():
		return null
	return sea_zones[id]


## Compatibility alias used by call sites during the typed-record migration.
func province_data(id: int) -> ProvinceState:
	return get_province(id)


func sea_zone_data(id: int) -> SeaZoneState:
	return get_sea_zone(id)


## Capital tile picked for the province, or NO_TILE when the map has none.
func capital_tile_of(province_id: int) -> Vector2i:
	var data: ProvinceState = get_province(province_id)
	if data == null:
		return CapitalChoice.NO_TILE
	return data.capital_tile


func province_tiles(id: int) -> Array:
	var data: ProvinceState = get_province(id)
	if data == null:
		return []
	return data.tiles


func province_center(id: int) -> Vector2:
	var data: ProvinceState = get_province(id)
	if data == null:
		return Vector2.ZERO
	return data.center


func sea_zone_center(id: int) -> Vector2:
	var data: SeaZoneState = get_sea_zone(id)
	if data == null:
		return Vector2.ZERO
	return data.center


func province_owner(id: int) -> int:
	var data: ProvinceState = get_province(id)
	if data == null:
		return NO_ID
	return data.owner


## Owner of the land tile, deed first, province second. Sea and unclaimed land
## report NO_ID.
func owner_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_ID
	var index: int = index_of(x, y)
	var province_id: int = province[index]
	if province_id == NO_ID:
		return NO_ID
	return ownership.owner_of(index, province_owner(province_id))


## Records a purchased tile. The province owner is unchanged; the deed is what
## moves. A tile can be bought once, by one Great Power.
func purchase_tile(tile: Vector2i, buyer: int) -> bool:
	if not is_land(tile.x, tile.y):
		return false
	if province_at(tile.x, tile.y) == NO_ID:
		return false
	return ownership.purchase(index_of(tile.x, tile.y), buyer)


func is_purchased_tile(tile: Vector2i) -> bool:
	if not in_bounds(tile.x, tile.y):
		return false
	return ownership.is_purchased(index_of(tile.x, tile.y))


func province_name(id: int) -> String:
	var data: ProvinceState = get_province(id)
	if data == null:
		return ""
	return data.name


func sea_zone_name(id: int) -> String:
	var data: SeaZoneState = get_sea_zone(id)
	if data == null:
		return ""
	return data.name
