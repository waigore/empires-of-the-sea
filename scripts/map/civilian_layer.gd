class_name CivilianLayer
extends Node2D
## Owns civilian markers and applies land orders. Rules outcomes come from
## CivilianMovement; this layer only animates them and draws the development
## civilians leave behind (wiki: civilian-units, extraction-and-improvements).

signal unit_selected(unit: CivilianState)
signal unit_moved(unit: CivilianState, result: Dictionary)

const TILE_SIZE: float = 22.0
const MARKER_RADIUS: float = 26.0

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var markers: Array[CivilianMarker] = []
var selected_unit: CivilianState = null

var _next_id: int = 1
var _zoom: float = 1.0


func spawn(
	p_model: MapModel, p_works: LandWorks, province_id: int, owner: int,
	types: Array[String]
) -> void:
	clear_all()
	model = p_model
	works = p_works
	if model == null or types.is_empty():
		return
	var anchor: Vector2i = _capital_tile(province_id)
	# Keep the capital tile clear so the seat's own marker stays readable.
	var taken: Dictionary = {anchor: true}
	for type_id: String in types:
		var tile: Vector2i = _free_tile(province_id, anchor, taken)
		if tile.x < 0:
			taken.erase(anchor)
			tile = _free_tile(province_id, anchor, taken)
		if tile.x < 0:
			continue
		taken[tile] = true
		add_unit(owner, type_id, tile)
	queue_redraw()


func clear_all() -> void:
	for marker: CivilianMarker in markers:
		marker.queue_free()
	markers.clear()
	units.clear()
	selected_unit = null


func add_unit(owner: int, type_id: String, tile: Vector2i) -> CivilianState:
	var unit := CivilianState.create(_next_id, owner, type_id, tile)
	_next_id += 1
	units.append(unit)
	var marker := CivilianMarker.new()
	marker.unit_id = unit.id
	marker.type_id = unit.type_id
	marker.faction = unit.owner
	marker.position = _tile_position(tile)
	marker.scale = Vector2.ONE * _marker_scale()
	add_child(marker)
	markers.append(marker)
	return unit


func unit_at(world_position: Vector2) -> CivilianState:
	var best: CivilianState = null
	var best_distance: float = minf(MARKER_RADIUS / maxf(_zoom, 0.001), TILE_SIZE * 0.9)
	for unit: CivilianState in units:
		var distance: float = _tile_position(unit.tile).distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


func marker_for(unit: CivilianState) -> CivilianMarker:
	if unit == null:
		return null
	for marker: CivilianMarker in markers:
		if marker.unit_id == unit.id:
			return marker
	return null


func select(unit: CivilianState) -> void:
	selected_unit = unit
	sync()
	unit_selected.emit(unit)


func deselect() -> void:
	if selected_unit == null:
		return
	selected_unit = null
	sync()
	unit_selected.emit(null)


## Applies a land order through the rules, then animates the medallion.
func apply_move(unit: CivilianState, tile: Vector2i) -> Dictionary:
	var result: Dictionary = CivilianMovement.apply_move(model, unit, tile)
	if not bool(result.get("ok", false)):
		return result
	var marker: CivilianMarker = marker_for(unit)
	if marker != null:
		var tween: Tween = create_tween()
		tween.tween_property(marker, "position", _tile_position(tile), 0.32).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
	unit_moved.emit(unit, result)
	return result


func begin_turn() -> void:
	CivilianMovement.begin_turn(units)
	sync()


## Mirrors rules state onto the medallions (selection, work ring, progress).
func sync() -> void:
	for unit: CivilianState in units:
		var marker: CivilianMarker = marker_for(unit)
		if marker == null:
			continue
		var progress: float = 0.0
		if unit.is_working() and unit.total_turns() > 0:
			progress = 1.0 - float(unit.remaining_turns()) / float(unit.total_turns())
		marker.set_state(unit == selected_unit, unit.is_working(), progress)


func refresh_works() -> void:
	queue_redraw()


func set_zoom(value: float) -> void:
	_zoom = maxf(value, 0.001)
	for marker: CivilianMarker in markers:
		marker.scale = Vector2.ONE * _marker_scale()


func unit_count(owner: int) -> int:
	var total: int = 0
	for unit: CivilianState in units:
		if unit.owner == owner:
			total += 1
	return total


func civilian_tiles(owner: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for unit: CivilianState in units:
		if unit.owner == owner:
			tiles.append(unit.tile)
	return tiles


## Free land tile near the capital for a freshly trained civilian (-1 when full).
func mustering_tile(province_id: int) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var seat: Vector2i = _capital_tile(province_id)
	var taken: Dictionary = {seat: true}
	for unit: CivilianState in units:
		taken[unit.tile] = true
	var tile: Vector2i = _free_tile(province_id, seat, taken)
	if tile.x >= 0:
		return tile
	taken.erase(seat)
	return _free_tile(province_id, seat, taken)


func _draw() -> void:
	if model == null or works == null:
		return
	for tile: Vector2i in works.developed_tiles(model):
		var point: Vector2 = _tile_position(tile)
		if works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD:
			_draw_road(point)
		var level: int = works.improvement_at(model, tile)
		if level > 0:
			_draw_improvement(point, level)
		if works.has_port(model, tile):
			_draw_port(point)


func _draw_road(point: Vector2) -> void:
	var ink := Color(0.36, 0.26, 0.16, 0.65)
	draw_line(point + Vector2(-9, 0), point + Vector2(-3, 0), ink, 2.4, true)
	draw_line(point + Vector2(3, 0), point + Vector2(9, 0), ink, 2.4, true)


func _draw_improvement(point: Vector2, level: int) -> void:
	for i in level:
		var origin: Vector2 = point + Vector2(-7.5 + float(i) * 5.0, 7.0)
		draw_rect(Rect2(origin, Vector2(3.4, 3.4)), Palette.GOLD)
		draw_rect(Rect2(origin, Vector2(3.4, 3.4)), Palette.INK, false, 0.8)


func _draw_port(point: Vector2) -> void:
	var ink := Color(0.18, 0.24, 0.32, 0.85)
	draw_arc(point + Vector2(0, 5.0), 4.6, PI, TAU, 12, ink, 1.6, true)
	draw_line(point + Vector2(0, 0.6), point + Vector2(0, 5.0), ink, 1.4, true)


func _tile_position(tile: Vector2i) -> Vector2:
	return MapGeo.tile_center(tile.x, tile.y, TILE_SIZE)


func _marker_scale() -> float:
	return clampf(1.0 / _zoom, 0.62, 1.0)


func _capital_tile(province_id: int) -> Vector2i:
	var data: Dictionary = model.province_data(province_id)
	if data.is_empty():
		return Vector2i(-1, -1)
	var seat: Vector2i = Vector2i(data.get("capital_tile", CapitalChoice.NO_TILE))
	if seat.x >= 0 and model.is_land(seat.x, seat.y):
		return seat
	var tiles: Array = model.province_tiles(province_id)
	if tiles.is_empty():
		return Vector2i(-1, -1)
	return tiles[0]


## First free land tile of the province, nearest the capital seat.
func _free_tile(province_id: int, anchor: Vector2i, taken: Dictionary) -> Vector2i:
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
