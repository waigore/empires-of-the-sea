class_name ProvinceState
extends RefCounted
## One province record on the world map (wiki: tile-map-and-generation).
## Typed so rules mutate fields instead of Dictionary string keys (REQ-P3-01).


var id: int = MapModel.NO_ID
var name: String = ""
var tiles: Array[Vector2i] = []
var center: Vector2 = Vector2.ZERO
var area: int = 0
var coastal: bool = false
var port_tile: Vector2i = Vector2i(-1, -1)
var owner: int = MapModel.NO_ID
var capital: bool = false
var capital_tile: Vector2i = Vector2i(-1, -1)
var ports: Dictionary = {}
var road_paths: Array = []
var town_development: int = 0
## Province town tile (wiki: capital-and-connectivity § Town per province).
## The capital tile in a capital province; otherwise the port or a deterministic
## centre tile. -1 on hand-built maps that predate town assignment.
var town_tile: Vector2i = Vector2i(-1, -1)
## Fort level 0–3 (wiki: siege-mechanics). Walls and guns derive from it.
var fort_level: int = 0
## Hospital level 0–2 (wiki: combat § Regiment condition; DR-20261111-12).
## Rest share and battle wear derive from it.
var hospital_level: int = 0
var resource: int = MapModel.NO_ID
var resource_tile: Vector2i = Vector2i(-1, -1)
var population: int = 0
## Cached by MapGeo.province_neighbors; empty until first query.
var neighbors: Array = []
var neighbors_cached: bool = false


static func create(
	p_id: int,
	p_name: String,
	p_tiles: Array[Vector2i],
	p_center: Vector2,
	p_area: int,
	p_owner: int = MapModel.NO_ID,
	p_capital: bool = false
) -> ProvinceState:
	var province := ProvinceState.new()
	province.id = p_id
	province.name = p_name
	province.tiles = p_tiles
	province.center = p_center
	province.area = p_area
	province.owner = p_owner
	province.capital = p_capital
	return province


func has_resource_tile() -> bool:
	return resource_tile.x >= 0


## Every province town has at least level 1 once town development is modelled;
## 0 on old hand-built maps reads as the level-1 baseline.
func town_level() -> int:
	return clampi(maxi(town_development, 1), 1, 4)


func is_town_tile(tile: Vector2i) -> bool:
	if town_tile.x >= 0:
		return town_tile == tile
	if capital and capital_tile.x >= 0:
		return capital_tile == tile
	return false


## A province with a town tile, or a capital with a seat, has a town to raise
## (hand-built maps predate town assignment and fall back to the seat).
func has_town() -> bool:
	return town_tile.x >= 0 or (capital and capital_tile.x >= 0)


func clear_resource_tile_if(tile: Vector2i) -> void:
	if resource_tile == tile:
		resource_tile = Vector2i(-1, -1)
		resource = MapModel.NO_ID
