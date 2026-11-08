class_name SeaZoneState
extends RefCounted
## One sea-zone record on the world map (wiki: tile-map-and-generation).
## Typed so naval rules read fields instead of Dictionary string keys (REQ-P3-01).


var id: int = MapModel.NO_ID
var name: String = ""
var tiles: Array[Vector2i] = []
var center: Vector2 = Vector2.ZERO
var area: int = 0
## Cached by MapGeo.sea_zone_neighbors; empty until first query.
var neighbors: Array = []
var neighbors_cached: bool = false


static func create(
	p_id: int,
	p_name: String,
	p_tiles: Array[Vector2i],
	p_center: Vector2,
	p_area: int
) -> SeaZoneState:
	var zone := SeaZoneState.new()
	zone.id = p_id
	zone.name = p_name
	zone.tiles = p_tiles
	zone.center = p_center
	zone.area = p_area
	return zone
