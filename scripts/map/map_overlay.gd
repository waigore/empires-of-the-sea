class_name MapOverlay
extends Node2D
## Animated layer above the map: fog of war, hover highlight, selection glow.
## Fog is a low-resolution texture scaled up, so revealing a zone costs one
## image rebuild instead of thousands of draw calls (REQ-P4-01).

const TILE_SIZE: float = 22.0

const FOG_VISIBLE: int = 0
const FOG_FOGGED: int = 1
const FOG_UNKNOWN: int = 2

const FOG_FADE_SPEED: float = 2.6

var model: MapModel = null
var fog: PackedByteArray = PackedByteArray()
var hover_province: int = -1
var selected_province: int = -1
var move_zones: Array[int] = []
var move_provinces: Array[int] = []
var move_tiles: Array[Vector2i] = []

var _fade: PackedFloat32Array = PackedFloat32Array()
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _fog_sprite: Sprite2D = null
var _fog_dirty: bool = true
var _pulse: float = 0.0
var _outlines: Dictionary = {}
var _zone_outlines: Dictionary = {}
var _ripples: Array[Dictionary] = []


func build(p_model: MapModel) -> void:
	model = p_model
	var count: int = model.width * model.height
	fog.resize(count)
	fog.fill(FOG_VISIBLE)
	_fade.resize(count)
	_fade.fill(0.0)
	_fog_image = Image.create(model.width, model.height, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0, 0, 0, 0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_fog_sprite = Sprite2D.new()
	_fog_sprite.texture = _fog_texture
	_fog_sprite.centered = false
	_fog_sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	_fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_sprite.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/fog.gdshader")
	var texel := Vector2(1.0 / float(model.width), 1.0 / float(model.height))
	material.set_shader_parameter("texel", texel)
	material.set_shader_parameter("map_tiles", Vector2(float(model.width), float(model.height)))
	material.set_shader_parameter("tile_size", TILE_SIZE)
	_fog_sprite.material = material
	add_child(_fog_sprite)

	_fog_dirty = true
	queue_redraw()


func set_fog_state(tile_index: int, state: int) -> void:
	if tile_index < 0 or tile_index >= fog.size():
		return
	if fog[tile_index] == state:
		return
	fog[tile_index] = state
	_fog_dirty = true


func set_fog_rect(rect: Rect2i, state: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if model.in_bounds(x, y):
				set_fog_state(model.index_of(x, y), state)


## Projects rules-engine visibility onto the fog texture (view reads state).
## `indices` are the tiles that changed; empty means resync the whole map.
func sync_visibility(visibility: VisibilityModel, indices: Array = []) -> void:
	if visibility == null or model == null:
		return
	if indices.is_empty():
		for index in fog.size():
			set_fog_state(index, fog_state_for(visibility.level_at_index(index)))
		return
	for raw: Variant in indices:
		var index: int = int(raw)
		set_fog_state(index, fog_state_for(visibility.level_at_index(index)))


static func fog_state_for(level: int) -> int:
	match level:
		VisibilityModel.Level.FULLY_VISIBLE:
			return FOG_VISIBLE
		VisibilityModel.Level.UNKNOWN:
			return FOG_UNKNOWN
		_:
			return FOG_FOGGED


## Jumps the fade animation to the current fog targets (used on first build so
## the map does not start fully revealed).
func snap_fog() -> void:
	for i in _fade.size():
		match fog[i]:
			FOG_FOGGED:
				_fade[i] = 0.55
			FOG_UNKNOWN:
				_fade[i] = 1.0
			_:
				_fade[i] = 0.0
	_fog_dirty = true


func fog_state_at(x: int, y: int) -> int:
	if model == null or not model.in_bounds(x, y):
		return FOG_UNKNOWN
	return fog[model.index_of(x, y)]


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


func _process(delta: float) -> void:
	_pulse += delta
	var animating: bool = false
	for i in _fade.size():
		var target: float = 0.0
		match fog[i]:
			FOG_FOGGED:
				target = 0.55
			FOG_UNKNOWN:
				target = 1.0
		var current: float = _fade[i]
		if absf(current - target) > 0.002:
			_fade[i] = move_toward(current, target, delta * FOG_FADE_SPEED)
			animating = true
	if animating:
		_fog_dirty = true
	if _fog_dirty:
		_rebuild_fog()
	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i]["age"] = float(_ripples[i]["age"]) + delta
		if float(_ripples[i]["age"]) > 1.1:
			_ripples.remove_at(i)
	queue_redraw()


func _rebuild_fog() -> void:
	_fog_dirty = false
	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			var amount: float = _fade[index]
			if amount <= 0.004:
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var state: int = fog[index]
			if state == FOG_UNKNOWN:
				var paper: Color = Palette.PAPER
				_fog_image.set_pixel(x, y, Color(paper.r, paper.g, paper.b, amount))
			else:
				_fog_image.set_pixel(x, y, Color(0.80, 0.82, 0.79, amount * 0.48))
	_fog_texture.update(_fog_image)


func _draw() -> void:
	if model == null:
		return

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
		var point: Vector2 = model.tile_center(tile.x, tile.y, TILE_SIZE)
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


func _draw_province_outline(id: int, color: Color, width: float) -> void:
	for path: PackedVector2Array in _province_outline(id):
		draw_polyline(path, color, width, true)


func _draw_sea_zone_outline(id: int, color: Color, width: float) -> void:
	for path: PackedVector2Array in _sea_zone_outline(id):
		draw_polyline(path, color, width, true)


func _draw_port_marker(province_id: int, pulse: float) -> void:
	var data: Dictionary = model.province_data(province_id)
	var port: Vector2i = data.get("port_tile", Vector2i(-1, -1))
	if port.x < 0 or port.y < 0:
		return
	var point: Vector2 = model.tile_center(port.x, port.y, TILE_SIZE)
	draw_arc(
		point, 13.0 + pulse * 2.0, 0.0, TAU, 28,
		Color(0.99, 0.93, 0.72, 0.90), 2.0, true
	)
	draw_circle(point, 3.0, Color(0.99, 0.93, 0.72, 0.90))


func _sea_zone_outline(id: int) -> Array:
	if _zone_outlines.has(id):
		return _zone_outlines[id]
	var segments: Array[PackedVector2Array] = []
	var data: Dictionary = model.sea_zone_data(id)
	for tile: Vector2i in data.get("tiles", []):
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
