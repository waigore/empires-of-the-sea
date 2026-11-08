class_name Minimap
extends Control
## Parchment inset showing the whole region, the current viewport and faction
## capitals. Click or drag to jump the camera (desktop and touch).

signal jump_requested(world_position: Vector2)

var model: MapModel = null

var _texture: ImageTexture = null
var _view_rect: Rect2 = Rect2()
var _map_size: Vector2 = Vector2.ZERO
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func build(p_model: MapModel, map_size: Vector2) -> void:
	model = p_model
	_map_size = map_size
	var image := Image.create(model.width, model.height, false, Image.FORMAT_RGBA8)
	for y in model.height:
		for x in model.width:
			var terrain: int = model.terrain_at(x, y)
			var color: Color = Palette.SEA_MID
			if terrain != MapModel.Terrain.OCEAN and terrain != MapModel.Terrain.SHALLOW:
				color = Palette.terrain_color(terrain)
				var owner: int = model.owner_at(x, y)
				if owner != MapModel.NO_ID:
					color = color.lerp(FactionCatalog.color_of(owner), 0.4)
			elif terrain == MapModel.Terrain.SHALLOW:
				color = Palette.SEA_PALE
			image.set_pixel(x, y, color)
	_texture = ImageTexture.create_from_image(image)
	queue_redraw()


func set_view_rect(rect: Rect2) -> void:
	_view_rect = rect
	queue_redraw()


func _draw() -> void:
	if _texture == null:
		return
	var fit: Rect2 = _fit_rect()
	draw_texture_rect(_texture, fit, false)
	draw_rect(fit, Palette.INK_LINE, false, 1.0)
	if model != null:
		for province: Dictionary in model.provinces:
			if not bool(province["capital"]):
				continue
			var point: Vector2 = _to_local(Vector2(province["center"]) * 22.0)
			draw_circle(point, 2.6, Palette.faction_color(int(province["owner"])))
			draw_circle(point, 2.6, Palette.INK, false, 0.8, true)
	if _view_rect.size != Vector2.ZERO:
		var top_left: Vector2 = _to_local(_view_rect.position)
		var bottom_right: Vector2 = _to_local(_view_rect.end)
		var rect := Rect2(top_left, bottom_right - top_left)
		draw_rect(rect, Color(0.99, 0.93, 0.72, 0.9), false, 1.6)
		draw_rect(rect.grow(1.0), Color(0.10, 0.08, 0.05, 0.5), false, 1.0)


func _fit_rect() -> Rect2:
	if _map_size.x <= 0.0 or _map_size.y <= 0.0:
		return Rect2(Vector2.ZERO, size)
	var scale_factor: float = minf(size.x / _map_size.x, size.y / _map_size.y)
	var draw_size: Vector2 = _map_size * scale_factor
	return Rect2((size - draw_size) * 0.5, draw_size)


func _to_local(world_position: Vector2) -> Vector2:
	var fit: Rect2 = _fit_rect()
	if _map_size.x <= 0.0 or _map_size.y <= 0.0:
		return Vector2.ZERO
	return fit.position + (world_position / _map_size) * fit.size


func _to_world(local_position: Vector2) -> Vector2:
	var fit: Rect2 = _fit_rect()
	if fit.size.x <= 0.0 or fit.size.y <= 0.0:
		return Vector2.ZERO
	var normalized: Vector2 = (local_position - fit.position) / fit.size
	return Vector2(
		clampf(normalized.x, 0.0, 1.0) * _map_size.x,
		clampf(normalized.y, 0.0, 1.0) * _map_size.y
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			jump_requested.emit(_to_world(event.position))
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		jump_requested.emit(_to_world(event.position))
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			jump_requested.emit(_to_world(event.position))
		accept_event()
	elif event is InputEventScreenDrag:
		jump_requested.emit(_to_world(event.position))
		accept_event()
