class_name MapOverlay
extends Node2D
## Animated layer above the map: fog of war, hover highlight, selection glow,
## move hints and painted country borders.
##
## Fog lives on a child `FogLayer` (tile-resolution texture scaled up, so
## revealing a zone costs one image rebuild instead of thousands of draw calls,
## REQ-P4-01). This node keeps the artwork that must sit *above* fog and owns
## the narrow fog API the rest of the play code talks to.

## Fog ids re-exported for callers/tests that speak in overlay terms.
const FOG_VISIBLE: int = FogLayer.FOG_VISIBLE
const FOG_FOGGED: int = FogLayer.FOG_FOGGED
const FOG_UNKNOWN: int = FogLayer.FOG_UNKNOWN

const TILE_SIZE: float = 22.0

var model: MapModel = null
## Fog of war grid + fade; child node so the fog texture draws behind the ink.
var fog_layer: FogLayer = null
var hover_province: int = -1
var selected_province: int = -1
var move_zones: Array[int] = []
var move_provinces: Array[int] = []
var move_tiles: Array[Vector2i] = []

var _pulse: float = 0.0
var _outlines: Dictionary = {}
var _zone_outlines: Dictionary = {}
## Owner id -> smoothed country-border polylines (drawn above fog so political
## geography stays readable in charted but unexplored lands).
var _country_borders: Dictionary = {}
var _ripples: Array[Dictionary] = []


func build(p_model: MapModel) -> void:
	model = p_model
	_build_fog_layer()
	_build_country_borders()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func _build_fog_layer() -> void:
	if fog_layer == null:
		fog_layer = FogLayer.new()
		fog_layer.name = "Fog"
		add_child(fog_layer)
	fog_layer.build(model)


func _process(delta: float) -> void:
	_pulse += delta
	var fog_moved: bool = fog_layer.advance(delta)
	var had_ripples: bool = not _ripples.is_empty()
	_age_ripples(delta)
	# Fog texture changes and selection pulse / ripples / move hints need a
	# repaint; settled fog does not.
	if (
		fog_moved
		or selected_province >= 0
		or hover_province >= 0
		or had_ripples
		or not _ripples.is_empty()
		or not move_zones.is_empty()
		or not move_provinces.is_empty()
		or not move_tiles.is_empty()
		or fog_layer.is_fading()
	):
		queue_redraw()


func _age_ripples(delta: float) -> void:
	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i]["age"] = float(_ripples[i]["age"]) + delta
		if float(_ripples[i]["age"]) > 1.1:
			_ripples.remove_at(i)


# --- fog API (delegates to FogLayer) -----------------------------------------


func set_fog_state(tile_index: int, state: int) -> void:
	fog_layer.set_fog_state(tile_index, state)


func set_fog_rect(rect: Rect2i, state: int) -> void:
	fog_layer.set_fog_rect(rect, state)


func sync_visibility(visibility: VisibilityModel, indices: Array = []) -> void:
	fog_layer.sync_visibility(visibility, indices)


func snap_fog() -> void:
	fog_layer.snap_fog()


func fog_state_at(x: int, y: int) -> int:
	return fog_layer.fog_state_at(x, y)


# --- highlights --------------------------------------------------------------


func show_move_options(zones: Array[int], provinces: Array[int]) -> void:
	move_zones = zones.duplicate()
	move_provinces = provinces.duplicate()
	queue_redraw()


func clear_move_options() -> void:
	move_tiles.clear()
	if move_zones.is_empty() and move_provinces.is_empty():
		return
	move_zones.clear()
	move_provinces.clear()
	queue_redraw()


## Tile-level march targets for the selected civilian (one land tile per turn).
func show_tile_options(tiles: Array[Vector2i]) -> void:
	move_tiles = tiles.duplicate()
	queue_redraw()


func clear_tile_options() -> void:
	if move_tiles.is_empty():
		return
	move_tiles.clear()
	queue_redraw()


func select_province(id: int, ripple_at: Vector2 = Vector2.INF) -> void:
	selected_province = id
	if ripple_at != Vector2.INF:
		_ripples.append({"position": ripple_at, "age": 0.0})
	queue_redraw()


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if model == null:
		return

	_draw_country_borders()

	var pulse: float = 0.5 + 0.5 * sin(_pulse * 3.2)
	if hover_province >= 0 and hover_province != selected_province:
		_draw_province_outline(hover_province, Color(0.20, 0.16, 0.10, 0.45), 1.8)

	if selected_province >= 0:
		_draw_province_outline(
			selected_province, Color(0.83, 0.69, 0.22, 0.16 + 0.12 * pulse), 9.0
		)
		_draw_province_outline(
			selected_province, Color(0.99, 0.93, 0.72, 0.70 + 0.25 * pulse), 2.4
		)

	for zone_id: int in move_zones:
		_draw_sea_zone_outline(
			zone_id, Color(0.83, 0.69, 0.22, 0.12 + 0.08 * pulse), 10.0
		)
		_draw_sea_zone_outline(
			zone_id, Color(0.99, 0.93, 0.72, 0.50 + 0.25 * pulse), 2.2
		)

	for province_id: int in move_provinces:
		_draw_province_outline(
			province_id, Color(0.83, 0.69, 0.22, 0.12 + 0.08 * pulse), 10.0
		)
		_draw_province_outline(
			province_id, Color(0.99, 0.93, 0.72, 0.55 + 0.25 * pulse), 2.2
		)
		_draw_port_marker(province_id, pulse)

	for tile: Vector2i in move_tiles:
		var point: Vector2 = MapGeo.tile_center(tile.x, tile.y, TILE_SIZE)
		draw_arc(
			point, 8.0 + pulse * 1.6, 0, TAU, 24,
			Color(0.99, 0.93, 0.72, 0.55 + 0.25 * pulse), 1.8, true
		)
		draw_circle(point, 2.0, Color(0.99, 0.93, 0.72, 0.85))

	for ripple: Dictionary in _ripples:
		var age: float = ripple["age"]
		var progress: float = clampf(age / 1.1, 0.0, 1.0)
		var radius: float = 12.0 + progress * 90.0
		var alpha: float = (1.0 - progress) * 0.55
		draw_arc(
			ripple["position"], radius, 0, TAU, 48,
			Color(0.99, 0.93, 0.72, alpha), 2.0, true
		)


## Country borders sit on top of the fog texture: one engraved shadow plus the
## owner's colour, so they read on any terrain without striping.
func _draw_country_borders() -> void:
	var owners: Array = _country_borders.keys()
	owners.sort()
	for owner: int in owners:
		var color: Color = FactionCatalog.color_of(owner)
		var shadow := Color(0.12, 0.09, 0.06, 0.55)
		var core := Color(
			clampf(color.r * 1.05, 0.0, 1.0),
			clampf(color.g * 1.05, 0.0, 1.0),
			clampf(color.b * 1.05, 0.0, 1.0),
			1.0
		)
		for path: PackedVector2Array in _country_borders[owner]:
			draw_polyline(path, shadow, 5.0, true)
			draw_polyline(path, core, 2.8, true)


func _build_country_borders() -> void:
	_country_borders.clear()
	var raw: Dictionary = CountryBorders.build(model, TILE_SIZE)
	var owners: Array = raw.keys()
	owners.sort()
	for owner: int in owners:
		_country_borders[owner] = InkPaths.smooth_segments(raw[owner], 3)


func refresh_borders() -> void:
	if model != null:
		_build_country_borders()
		queue_redraw()


func _draw_province_outline(id: int, color: Color, width: float) -> void:
	for path: PackedVector2Array in _province_outline(id):
		draw_polyline(path, color, width, true)


func _draw_sea_zone_outline(id: int, color: Color, width: float) -> void:
	for path: PackedVector2Array in _sea_zone_outline(id):
		draw_polyline(path, color, width, true)


func _draw_port_marker(province_id: int, pulse: float) -> void:
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return
	var port: Vector2i = data.port_tile
	if port.x < 0 or port.y < 0:
		return
	var point: Vector2 = MapGeo.tile_center(port.x, port.y, TILE_SIZE)
	draw_arc(
		point, 13.0 + pulse * 2.0, 0.0, TAU, 28,
		Color(0.99, 0.93, 0.72, 0.90), 2.0, true
	)
	draw_circle(point, 3.0, Color(0.99, 0.93, 0.72, 0.90))


func _sea_zone_outline(id: int) -> Array:
	if _zone_outlines.has(id):
		return _zone_outlines[id]
	var segments: Array[PackedVector2Array] = []
	var data: SeaZoneState = model.sea_zone_data(id)
	for tile: Vector2i in data.tiles:
		var x: int = tile.x
		var y: int = tile.y
		if model.sea_zone_at(x, y - 1) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y)) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
			]))
		if model.sea_zone_at(x, y + 1) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
			]))
		if model.sea_zone_at(x - 1, y) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y)) * TILE_SIZE,
				Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
			]))
		if model.sea_zone_at(x + 1, y) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
			]))
	var paths: Array[PackedVector2Array] = InkPaths.smooth_segments(segments, 2)
	_zone_outlines[id] = paths
	return paths


func _province_outline(id: int) -> Array:
	if _outlines.has(id):
		return _outlines[id]
	var segments: Array[PackedVector2Array] = []
	for tile: Vector2i in model.province_tiles(id):
		var x: int = tile.x
		var y: int = tile.y
		if model.province_at(x, y - 1) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y)) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
			]))
		if model.province_at(x, y + 1) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
			]))
		if model.province_at(x - 1, y) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x), float(y)) * TILE_SIZE,
				Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
			]))
		if model.province_at(x + 1, y) != id:
			segments.append(PackedVector2Array([
				Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
				Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
			]))
	var paths: Array[PackedVector2Array] = InkPaths.smooth_segments(segments, 2)
	_outlines[id] = paths
	return paths
