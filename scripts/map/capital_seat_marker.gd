class_name CapitalSeatMarker
extends Node2D
## Chart annotation for the capital-choice page: the chosen province glows and
## is inked at its border, and the seat tile carries a slow pulsing ring so a
## touch player sees exactly where the court will sit (wiki: capital-choice-phase
## § Player choice; REQ-P1-04, REQ-P5-05).

const TILE_SIZE: float = PlaySession.TILE_SIZE
const FILL: Color = Color(0.96, 0.78, 0.30, 0.22)
const EDGE: Color = Color(0.52, 0.34, 0.06, 0.92)
const HALO: Color = Color(0.12, 0.09, 0.04, 0.55)
const SEAT_GOLD: Color = Color(1.0, 0.88, 0.48, 1.0)
const PULSE_SPEED: float = 2.2
const RING_RADIUS: float = 9.0

var model: MapModel = null
var province_id: int = -1
var seat: Vector2i = Vector2i(-1, -1)

var _pulse: float = 0.0


func set_seat(p_model: MapModel, p_province: int, p_tile: Vector2i) -> void:
	model = p_model
	province_id = p_province
	seat = p_tile
	queue_redraw()


func clear() -> void:
	province_id = -1
	seat = Vector2i(-1, -1)
	queue_redraw()


func _process(delta: float) -> void:
	if province_id < 0:
		return
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()


func _draw() -> void:
	if model == null or province_id < 0:
		return
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		if model.is_land(tile.x, tile.y):
			tiles.append(tile)
	for tile: Vector2i in tiles:
		draw_rect(
			Rect2(Vector2(tile) * TILE_SIZE, Vector2.ONE * TILE_SIZE), FILL, true
		)
	for tile: Vector2i in tiles:
		_draw_open_edges(tile)
	if seat.x >= 0:
		_draw_seat(MapGeo.tile_center(seat.x, seat.y, TILE_SIZE))


## Inks only the sides that face another province or the sea, so the glow reads
## as one territory instead of a tile grid.
func _draw_open_edges(tile: Vector2i) -> void:
	var origin: Vector2 = Vector2(tile) * TILE_SIZE
	var corners: Array[Vector2] = [
		origin,
		origin + Vector2(TILE_SIZE, 0.0),
		origin + Vector2(TILE_SIZE, TILE_SIZE),
		origin + Vector2(0.0, TILE_SIZE),
	]
	var sides: Array[Vector2i] = [
		Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
	]
	for side in 4:
		var offset: Vector2i = sides[side]
		if model.province_at(tile.x + offset.x, tile.y + offset.y) == province_id:
			continue
		draw_line(corners[side], corners[(side + 1) % 4], EDGE, 2.2, true)


func _draw_seat(center: Vector2) -> void:
	var swell: float = sin(_pulse) * 1.6
	draw_circle(center, RING_RADIUS + 5.0 + swell, Color(HALO, 0.35))
	draw_arc(center, RING_RADIUS + swell, 0.0, TAU, 36, SEAT_GOLD, 2.4, true)
	draw_arc(center, RING_RADIUS + 3.5 + swell, 0.0, TAU, 36, HALO, 1.2, true)
	draw_circle(center, 2.6, SEAT_GOLD)
	for direction: Vector2 in [
		Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT
	]:
		draw_line(
			center + direction * (RING_RADIUS + 2.0),
			center + direction * (RING_RADIUS + 6.0),
			SEAT_GOLD,
			2.0,
			true
		)
