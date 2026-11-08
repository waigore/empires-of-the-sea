class_name LandWorks
extends RefCounted
## Per-tile development created by civilians (wiki: extraction-and-improvements).
## Pure state keyed by tile index so rules, view and tests share one record
## (REQ-P3-03). Improvements, transport, ports and prospection are per player
## where the wiki says so.

const MAX_IMPROVEMENT: int = 4
const TRANSPORT_ROAD: int = 1
const TRANSPORT_RAIL: int = 4

var improvement: Dictionary = {}
var transport: Dictionary = {}
var ports: Dictionary = {}
var prospected: Dictionary = {}


func improvement_at(model: MapModel, tile: Vector2i) -> int:
	return int(improvement.get(_index(model, tile), 0))


func set_improvement(model: MapModel, tile: Vector2i, level: int) -> void:
	_put(improvement, _index(model, tile), clampi(level, 0, MAX_IMPROVEMENT))


func transport_at(model: MapModel, tile: Vector2i) -> int:
	return int(transport.get(_index(model, tile), 0))


func set_transport(model: MapModel, tile: Vector2i, level: int) -> void:
	_put(transport, _index(model, tile), clampi(level, 0, TRANSPORT_RAIL))


func has_port(model: MapModel, tile: Vector2i) -> bool:
	return ports.has(_index(model, tile))


func add_port(model: MapModel, tile: Vector2i) -> void:
	var index: int = _index(model, tile)
	if index >= 0:
		ports[index] = true


func province_has_port(model: MapModel, province_id: int) -> bool:
	for tile: Vector2i in model.province_tiles(province_id):
		if has_port(model, tile):
			return true
	return false


func is_prospected(owner: int, model: MapModel, tile: Vector2i) -> bool:
	return prospected.has(_key(owner, _index(model, tile)))


func set_prospected(owner: int, model: MapModel, tile: Vector2i) -> void:
	var index: int = _index(model, tile)
	if index >= 0:
		prospected[_key(owner, index)] = true


## Tiles carrying any visible development, for the map decoration pass.
func developed_tiles(model: MapModel) -> Array[Vector2i]:
	var seen: Dictionary = {}
	for table: Dictionary in [improvement, transport, ports]:
		for raw: Variant in table.keys():
			seen[int(raw)] = true
	var result: Array[Vector2i] = []
	for raw: Variant in seen.keys():
		var index: int = int(raw)
		var y: int = int(float(index) / float(model.width))
		result.append(Vector2i(index - y * model.width, y))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * model.width + a.x < b.y * model.width + b.x
	)
	return result


func _index(model: MapModel, tile: Vector2i) -> int:
	if model == null or not model.in_bounds(tile.x, tile.y):
		return -1
	return model.index_of(tile.x, tile.y)


static func _key(owner: int, index: int) -> String:
	return "%d:%d" % [owner, index]


func _put(table: Dictionary, index: int, value: int) -> void:
	if index < 0:
		return
	if value <= 0:
		table.erase(index)
		return
	table[index] = value
