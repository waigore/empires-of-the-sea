class_name CapitalSeatMarker
extends Node2D
## Chart annotation for the capital-choice page: every province that can hold the
## court is lit gold while the rest of the land falls into shadow, the chosen one
## is inked at its border, and the seat tile carries a slow pulsing ring so a
## touch player sees exactly where the court will sit (wiki: capital-choice-phase
## § Player choice; REQ-P1-04, REQ-P5-05).
##
## The wash is baked at one texel per tile, like `MapWash`, and drawn with linear
## filtering: the land darkens and the crown's seaboards light up in one soft
## pass, however many tiles the chart holds.

const TILE_SIZE: float = PlaySession.TILE_SIZE
## A province a tap can be answered in: its border separates it from its gold
## neighbours, so the lit set reads as provinces, not one smear.
const ELIGIBLE_EDGE: Color = Color(0.48, 0.30, 0.04, 0.72)
## The chosen province: dark ink under a bright gold rule, the strongest mark on
## the chart.
const EDGE_INK: Color = Color(0.20, 0.12, 0.02, 0.92)
const EDGE_GOLD: Color = Color(1.0, 0.86, 0.44, 0.95)
const HALO: Color = Color(0.12, 0.09, 0.04, 0.55)
const SEAT_GOLD: Color = Color(1.0, 0.88, 0.48, 1.0)
## Land the court cannot be seated in: shadowed, so the glowing provinces are the
## only bright ground on the chart.
const VEIL: Color = Color(0.12, 0.10, 0.08, 0.34)
## A province a tap can be answered in.
const ELIGIBLE_FILL: Color = Color(1.0, 0.89, 0.52, 0.27)
## The province the court is seated in right now.
const CHOSEN_FILL: Color = Color(1.0, 0.95, 0.72, 0.70)
const PULSE_SPEED: float = 2.2
const RING_RADIUS: float = 9.0

var model: MapModel = null
var province_id: int = -1
var seat: Vector2i = Vector2i(-1, -1)
## Provinces the court may sit in (owned and sea-bound), as listed by
## `CapitalChoice.seatable_provinces`.
var eligible: Array[int] = []

var _wash: ImageTexture = null
var _base: Image = null
var _pulse: float = 0.0


## The provinces a tap can be answered in: the player sees the rule on the
## chart instead of discovering it by refusal. Rebuilds the light and shadow.
func set_eligible(p_model: MapModel, provinces: Array[int]) -> void:
	model = p_model
	eligible = provinces.duplicate()
	_base = _bake_base()
	_apply_chosen()
	queue_redraw()


func set_seat(p_model: MapModel, p_province: int, p_tile: Vector2i) -> void:
	model = p_model
	province_id = p_province
	seat = p_tile
	_apply_chosen()
	queue_redraw()


func clear() -> void:
	province_id = -1
	seat = Vector2i(-1, -1)
	_apply_chosen()
	queue_redraw()


func _process(delta: float) -> void:
	if province_id < 0:
		return
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	if _wash != null:
		draw_texture_rect(
			_wash, Rect2(Vector2.ZERO, MapGeo.world_size(model, TILE_SIZE)), false
		)
	var px: float = _pixel_scale()
	for id: int in eligible:
		if id != province_id:
			_draw_border(id, ELIGIBLE_EDGE, 1.6 * px)
	if province_id >= 0:
		_draw_border(province_id, EDGE_INK, 4.4 * px)
		_draw_border(province_id, EDGE_GOLD, 2.0 * px)
	if province_id >= 0 and seat.x >= 0:
		_draw_seat(MapGeo.tile_center(seat.x, seat.y, TILE_SIZE), px)


## One screen pixel in world units at the chart's current zoom: the chosen
## province must read as strongly when the whole map is shown as when it is
## close up, and a fixed world-space rule is a single blurred pixel at fit zoom.
func _pixel_scale() -> float:
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x
	return 1.0 / maxf(zoom, 0.01)


## One texel per tile: shadow on land the court cannot sit in, gold on the
## crown's seaboards.
func _bake_base() -> Image:
	if model == null:
		return null
	var image := Image.create(model.width, model.height, false, Image.FORMAT_RGBA8)
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y) and not eligible.has(model.province_at(x, y)):
				image.set_pixel(x, y, VEIL)
	for id: int in eligible:
		for tile: Vector2i in model.province_tiles(id):
			if model.is_land(tile.x, tile.y):
				image.set_pixel(tile.x, tile.y, ELIGIBLE_FILL)
	return image


## The chosen province sits on top of the base wash, brightest of all.
func _apply_chosen() -> void:
	if _base == null:
		_base = _bake_base()
	if _base == null:
		_wash = null
		return
	var image: Image = _base.duplicate()
	if province_id >= 0:
		for tile: Vector2i in model.province_tiles(province_id):
			if model.is_land(tile.x, tile.y):
				image.set_pixel(tile.x, tile.y, CHOSEN_FILL)
	_wash = ImageTexture.create_from_image(image)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## Inks only the sides of a province that face other ground, so it reads as one
## territory instead of a tile grid.
func _draw_border(province: int, color: Color, width: float) -> void:
	for tile: Vector2i in model.province_tiles(province):
		if not model.is_land(tile.x, tile.y):
			continue
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
			if model.province_at(tile.x + offset.x, tile.y + offset.y) == province:
				continue
			draw_line(corners[side], corners[(side + 1) % 4], color, width, true)


func _draw_seat(center: Vector2, px: float) -> void:
	var swell: float = sin(_pulse) * 1.6 * px
	var radius: float = RING_RADIUS * px
	draw_circle(center, radius + 5.0 * px + swell, Color(HALO, 0.35))
	draw_arc(center, radius + swell, 0.0, TAU, 36, SEAT_GOLD, 2.4 * px, true)
	draw_arc(center, radius + 3.5 * px + swell, 0.0, TAU, 36, HALO, 1.2 * px, true)
	draw_circle(center, 2.6 * px, SEAT_GOLD)
	for direction: Vector2 in [
		Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT
	]:
		draw_line(
			center + direction * (radius + 2.0 * px),
			center + direction * (radius + 6.0 * px),
			SEAT_GOLD,
			2.0 * px,
			true
		)
