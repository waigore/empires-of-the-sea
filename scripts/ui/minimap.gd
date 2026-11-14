class_name Minimap
extends Control
## Parchment inset showing the whole region, the current viewport and faction
## capitals. Click or drag to jump the camera (desktop and touch).
##
## The fills stay one texel per map tile, so the inset leans on vector ink for
## definition: province hairlines, the coast and the owners' borders are drawn
## in world space on top, which keeps them crisp at any inset size (REQ-P1-03).

signal jump_requested(world_position: Vector2)

## How far a tile's terrain colour moves toward its owner's heraldic colour.
## Bolder than the main map's wash so crowns still read in a 232 px inset.
const OWNER_TINT: float = 0.62
## Fogged land keeps its shape but fades toward the page.
const FOG_WASH: float = 0.32

const INK_SHADOW := Color(0.12, 0.09, 0.06)

var model: MapModel = null
## Player view the inset honours; null draws the whole map (tooling/tests).
var visibility: VisibilityModel = null

var _texture: ImageTexture = null
var _view_rect: Rect2 = Rect2()
var _map_size: Vector2 = Vector2.ZERO
## World units per tile, so ink widths can be expressed in screen pixels.
var _tile_world: float = 22.0
var _dragging: bool = false
var _seen_revision: int = 0
## Cached ink, first in world coordinates then projected into the inset's own
## pixels so strokes are drawn at device scale with true antialiasing.
var _coast: Array[PackedVector2Array] = []
var _province_ink: Array[PackedVector2Array] = []
var _country_borders: Dictionary = {}
var _ink_coast: Array[PackedVector2Array] = []
var _ink_provinces: Array[PackedVector2Array] = []
var _ink_borders: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(_on_resized)


func _on_resized() -> void:
	_project_ink()
	queue_redraw()


## Unknown tiles stay parchment, so an uncharted region never leaks its shape.
func build(p_model: MapModel, map_size: Vector2, p_visibility: VisibilityModel = null) -> void:
	model = p_model
	_map_size = map_size
	visibility = p_visibility
	if model != null and model.width > 0:
		_tile_world = map_size.x / float(model.width)
	_seen_revision = visibility.revision if visibility != null else 0
	rebuild()


## Repaint after a conquest: ownership moved without the chart changing.
func refresh_ownership() -> void:
	if model == null:
		return
	rebuild()


## Reveals arrive after the inset is built; repaint when the view moved on. A
## chart that never baked — a mount whose paint missed the inset, or one made
## before its region existed — bakes on the next frame instead of leaving the
## frame's near-black panel showing for the whole campaign (issue #563).
func _process(_delta: float) -> void:
	if model == null:
		return
	if _texture == null:
		rebuild()
		return
	if visibility == null or visibility.revision == _seen_revision:
		return
	_seen_revision = visibility.revision
	rebuild()


func rebuild() -> void:
	if model == null:
		return
	_rebuild_texture()
	_rebuild_ink()
	_project_ink()
	queue_redraw()


func _rebuild_texture() -> void:
	var image := Image.create(model.width, model.height, false, Image.FORMAT_RGBA8)
	for y in model.height:
		for x in model.width:
			var level: int = (
				visibility.level_at(x, y) if visibility != null else VisibilityModel.Level.FULLY_VISIBLE
			)
			if level == VisibilityModel.Level.UNKNOWN:
				image.set_pixel(x, y, Palette.PAPER)
				continue
			var terrain: int = model.terrain_at(x, y)
			var color: Color = Palette.SEA_DEEP
			if terrain != MapModel.Terrain.OCEAN and terrain != MapModel.Terrain.SHALLOW:
				color = Palette.terrain_color(terrain)
				var owner: int = model.owner_at(x, y)
				if owner != MapModel.NO_ID:
					color = color.lerp(FactionCatalog.color_of(owner), OWNER_TINT)
			elif terrain == MapModel.Terrain.SHALLOW:
				# A muted shelf: the pale rim keeps the coast readable as an
				# edge instead of a glow around the landmass.
				color = Palette.SEA_PALE.lerp(Palette.SEA_MID, 0.70)
			if level == VisibilityModel.Level.FOGGED:
				color = color.lerp(Palette.PAPER, FOG_WASH)
			image.set_pixel(x, y, color)
	_texture = ImageTexture.create_from_image(image)


func _rebuild_ink() -> void:
	_coast.clear()
	_province_ink.clear()
	_country_borders.clear()
	if model == null:
		return
	_coast = InkPaths.smooth_segments(_coast_segments(), 2)
	_province_ink = InkPaths.smooth_segments(_province_segments(), 1)
	# CountryBorders already hides edges touching unknown ground, so an
	# uncharted crown never draws its outline on the inset.
	var raw: Dictionary = CountryBorders.build(model, _tile_world, visibility)
	var owners: Array = raw.keys()
	owners.sort()
	for owner: int in owners:
		_country_borders[owner] = InkPaths.smooth_segments(raw[owner], 2)


## Ink is cached in world units; the inset only ever draws its own pixels, so
## project once per build/resize instead of scaling the canvas (a scaled canvas
## stretches the antialiasing feather and muddies thin strokes).
func _project_ink() -> void:
	_ink_coast.clear()
	_ink_provinces.clear()
	_ink_borders.clear()
	if model == null or _map_size.x <= 0.0:
		return
	var fit: Rect2 = _fit_rect()
	var unit: float = fit.size.x / _map_size.x
	for path: PackedVector2Array in _coast:
		_ink_coast.append(_project_path(path, fit.position, unit))
	for path: PackedVector2Array in _province_ink:
		_ink_provinces.append(_project_path(path, fit.position, unit))
	var owners: Array = _country_borders.keys()
	owners.sort()
	for owner: int in owners:
		var paths: Array[PackedVector2Array] = []
		for path: PackedVector2Array in _country_borders[owner]:
			paths.append(_project_path(path, fit.position, unit))
		_ink_borders[owner] = paths


func _project_path(path: PackedVector2Array, origin: Vector2, unit: float) -> PackedVector2Array:
	var projected := PackedVector2Array()
	projected.resize(path.size())
	for index in path.size():
		projected[index] = origin + path[index] * unit
	return projected


## Land/sea edges of charted ground. Uncharted coast stays un-inked.
func _coast_segments() -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y) or not _known(x, y):
				continue
			if not model.is_land(x, y - 1):
				_edge(segments, x, y, 0)
			if not model.is_land(x + 1, y):
				_edge(segments, x, y, 1)
			if not model.is_land(x, y + 1):
				_edge(segments, x, y, 2)
			if not model.is_land(x - 1, y):
				_edge(segments, x, y, 3)
	return segments


## Land-to-land edges between two charted provinces; the coast owns the rest.
func _province_segments() -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y) or not _known(x, y):
				continue
			var province_id: int = model.province_at(x, y)
			if (
				model.is_land(x + 1, y)
				and _known(x + 1, y)
				and model.province_at(x + 1, y) != province_id
			):
				_edge(segments, x, y, 1)
			if (
				model.is_land(x, y + 1)
				and _known(x, y + 1)
				and model.province_at(x, y + 1) != province_id
			):
				_edge(segments, x, y, 2)
	return segments


## Tile edge in world units: 0 = top, 1 = right, 2 = bottom, 3 = left.
func _edge(segments: Array[PackedVector2Array], x: int, y: int, edge: int) -> void:
	var top_left := Vector2(float(x), float(y)) * _tile_world
	var size: float = _tile_world
	match edge:
		1:
			segments.append(PackedVector2Array([
				top_left + Vector2(size, 0.0), top_left + Vector2(size, size)
			]))
		2:
			segments.append(PackedVector2Array([
				top_left + Vector2(0.0, size), top_left + Vector2(size, size)
			]))
		3:
			segments.append(PackedVector2Array([top_left, top_left + Vector2(0.0, size)]))
		_:
			segments.append(PackedVector2Array([top_left, top_left + Vector2(size, 0.0)]))


func _known(x: int, y: int) -> bool:
	if visibility == null:
		return true
	return visibility.level_at(x, y) != VisibilityModel.Level.UNKNOWN


func set_view_rect(rect: Rect2) -> void:
	_view_rect = rect
	queue_redraw()


func _draw() -> void:
	if _texture == null or model == null:
		return
	var fit: Rect2 = _fit_rect()
	draw_texture_rect(_texture, fit, false)
	_draw_ink()
	_draw_capitals()
	if _view_rect.size != Vector2.ZERO:
		var top_left: Vector2 = _to_local(_view_rect.position)
		var bottom_right: Vector2 = _to_local(_view_rect.end)
		var rect := Rect2(top_left, bottom_right - top_left)
		draw_rect(rect, Color(0.99, 0.93, 0.72, 0.9), false, 1.6)
		draw_rect(rect.grow(1.0), Color(0.10, 0.08, 0.05, 0.5), false, 1.0)
	_draw_frame(fit)


## Province hairlines, the coast, then each owner's ribbon: ink shadow under a
## brightened heraldic core, bolder than the terrain so borders read first.
func _draw_ink() -> void:
	# Province hairlines stay barely-there: at inset scale they are texture,
	# not information — the owners' ribbons carry the political read.
	var hairline := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.18)
	for path: PackedVector2Array in _ink_provinces:
		draw_polyline(path, hairline, 1.0, true)
	var coast := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.72)
	for path: PackedVector2Array in _ink_coast:
		draw_polyline(path, coast, 1.4, true)
	var owners: Array = _ink_borders.keys()
	owners.sort()
	for owner: int in owners:
		for path: PackedVector2Array in _ink_borders[owner]:
			draw_polyline(path, Color(INK_SHADOW.r, INK_SHADOW.g, INK_SHADOW.b, 0.55), 2.6, true)
	for owner: int in owners:
		var color: Color = FactionCatalog.color_of(owner)
		var core := Color(
			clampf(color.r * 1.18 + 0.03, 0.0, 1.0),
			clampf(color.g * 1.18 + 0.03, 0.0, 1.0),
			clampf(color.b * 1.18 + 0.03, 0.0, 1.0),
			0.98
		)
		for path: PackedVector2Array in _ink_borders[owner]:
			draw_polyline(path, core, 1.5, true)


## Capitals: heraldic dot with an ink ring and a parchment halo for lift.
func _draw_capitals() -> void:
	for province: ProvinceState in model.provinces:
		if not province.capital:
			continue
		if visibility != null and not visibility.is_province_known(province.id):
			continue
		var point: Vector2 = _to_local(Vector2(province.center) * _tile_world)
		draw_circle(point, 3.8, Color(0.99, 0.93, 0.72, 0.22))
		draw_circle(point, 2.7, Palette.faction_color(province.owner))
		draw_circle(point, 2.7, Palette.INK, false, 0.9, true)


## Double rule with gold corner ticks: the inset reads as a chart cartouche.
func _draw_frame(fit: Rect2) -> void:
	draw_rect(fit, Palette.INK_LINE, false, 1.0)
	draw_rect(fit.grow(-1.5), Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, 0.45), false, 1.0)
	var pale := Color(Palette.GOLD_PALE.r, Palette.GOLD_PALE.g, Palette.GOLD_PALE.b, 0.85)
	var arm: float = 7.0
	var corners: Array[Vector2] = [
		fit.position,
		Vector2(fit.end.x, fit.position.y),
		fit.end,
		Vector2(fit.position.x, fit.end.y),
	]
	var inward: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for index in corners.size():
		var corner: Vector2 = corners[index]
		var direction: Vector2 = inward[index]
		draw_line(corner, corner + Vector2(direction.x * arm, 0.0), pale, 1.4)
		draw_line(corner, corner + Vector2(0.0, direction.y * arm), pale, 1.4)


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
