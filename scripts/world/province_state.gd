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


func clear_resource_tile_if(tile: Vector2i) -> void:
	if resource_tile == tile:
		resource_tile = Vector2i(-1, -1)
		resource = MapModel.NO_ID
