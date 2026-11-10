class_name MapCanvas
extends Node2D
## Static map artwork: terrain wash, ink coastline, province borders, glyphs and
## labels. Drawn once per map build, so the per-frame cost is a command replay.
## The wash is a tile-resolution image shaded by `terrain.gdshader`, and the two
## animated layers (surf, cloud shadow) are child nodes so they redraw alone.
## Where names and symbols go is decided by the pure `MapCanvasPlan`.

const TILE_SIZE: float = 22.0
const CLOUD_MARGIN: float = 1400.0

## Marching-squares edge pairs per corner case (1=TL, 2=TR, 4=BR, 8=BL).
## Edge ids: 0=top, 1=right, 2=bottom, 3=left.
const MS_TABLE: Array = [
	[], [[3, 0]], [[0, 1]], [[3, 1]], [[1, 2]], [[3, 0], [1, 2]], [[0, 2]], [[3, 2]],
	[[2, 3]], [[0, 2]], [[0, 1], [2, 3]], [[1, 2]], [[3, 1]], [[0, 1]], [[3, 0]], [],
]

## Placement of names, symbols, passages and the compass for this region.
var plan := MapCanvasPlan.new()

var model: MapModel = null
## Owning world (both regions), used to mark the sea-lane passages.
var world: WorldMap = null

var _coast: Array[PackedVector2Array] = []
## The baked terrain paint (colour, height, coast field) for this map.
var relief: MapRelief = null
var _province_borders: Array[PackedVector2Array] = []
var _sea_borders: Array[PackedVector2Array] = []
var _roads: Array[PackedVector2Array] = []
var _font: Font = null
var _font_italic: Font = null
var _surf: MapSurf = null
var _cloud: ColorRect = null


func build(p_model: MapModel, p_world: WorldMap = null) -> void:
	model = p_model
	world = p_world
	_font = UiTheme.serif()
	_font_italic = UiTheme.serif_italic()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	relief = MapWash.build(self, model)
	_build_coast()
	_build_borders()
	_build_roads()
	plan.build(model, world, TILE_SIZE)
	_build_animated_layers()
	queue_redraw()


func map_size() -> Vector2:
	if model == null:
		return Vector2.ZERO
	return MapGeo.world_size(model, TILE_SIZE)


## Repaints owner tint and capital colours after a province changes hands.
func refresh_ownership() -> void:
	if model == null:
		return
	for child_name: String in ["Wash", "Shade"]:
		var child: Node = get_node_or_null(child_name)
		if child != null:
			remove_child(child)
			child.queue_free()
	relief = MapWash.build(self, model)
	plan.build(model, world, TILE_SIZE)
	queue_redraw()


# --- build ------------------------------------------------------------------


func _build_coast() -> void:
	var raw: Array[PackedVector2Array] = []
	for y in model.height:
		for x in model.width:
			var case_index: int = 0
			if model.is_land(x, y):
				case_index |= 1
			if model.is_land(x + 1, y):
				case_index |= 2
			if model.is_land(x + 1, y + 1):
				case_index |= 4
			if model.is_land(x, y + 1):
				case_index |= 8
			var pairs: Array = MS_TABLE[case_index]
			for pair: Array in pairs:
				var a: Vector2 = _edge_point(x, y, int(pair[0]))
				var b: Vector2 = _edge_point(x, y, int(pair[1]))
				raw.append(PackedVector2Array([a, b]))
	_coast = InkPaths.smooth_segments(raw, 1)


func _edge_point(x: int, y: int, edge: int) -> Vector2:
	var point: Vector2 = Vector2.ZERO
	match edge:
		0:
			point = Vector2(float(x) + 0.5, float(y))
		1:
			point = Vector2(float(x) + 1.0, float(y) + 0.5)
		2:
			point = Vector2(float(x) + 0.5, float(y) + 1.0)
		_:
			point = Vector2(float(x), float(y) + 0.5)
	# Marching squares reads tile (x, y) as the corner sample at (x, y), so its
	# contour runs through a cell that starts one half-tile up and left of the
	# square the wash actually fills. Shift it back onto the tile edge, or the
	# ink coast drifts half a tile off the land (REQ-P1-03).
	return (point + Vector2(0.5, 0.5)) * TILE_SIZE


func _build_borders() -> void:
	var province_raw: Array[PackedVector2Array] = []
	var sea_raw: Array[PackedVector2Array] = []
	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			var here: int = model.province[index]
			var right: int = model.province_at(x + 1, y)
			var below: int = model.province_at(x, y + 1)
			if here != MapModel.NO_ID and right != MapModel.NO_ID and here != right:
				province_raw.append(PackedVector2Array([
					Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
					Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
				]))
			if here != MapModel.NO_ID and below != MapModel.NO_ID and here != below:
				province_raw.append(PackedVector2Array([
					Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
					Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
				]))
			var zone: int = model.sea_zone[index]
			var zone_right: int = model.sea_zone_at(x + 1, y)
			var zone_below: int = model.sea_zone_at(x, y + 1)
			if zone != MapModel.NO_ID and zone_right != MapModel.NO_ID and zone != zone_right:
				sea_raw.append(PackedVector2Array([
					Vector2(float(x) + 1.0, float(y)) * TILE_SIZE,
					Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
				]))
			if zone != MapModel.NO_ID and zone_below != MapModel.NO_ID and zone != zone_below:
				sea_raw.append(PackedVector2Array([
					Vector2(float(x), float(y) + 1.0) * TILE_SIZE,
					Vector2(float(x) + 1.0, float(y) + 1.0) * TILE_SIZE,
				]))
	_province_borders = InkPaths.smooth_segments(province_raw, 2)
	_sea_borders = InkPaths.smooth_segments(sea_raw, 2)


## Capital roads (wiki: capital-and-connectivity § Capital Setup), drawn as one
## ink polyline per port-to-capital path.
func _build_roads() -> void:
	_roads.clear()
	for province: ProvinceState in model.provinces:
		for path: Array in province.road_paths:
			if path.size() < 2:
				continue
			var points := PackedVector2Array()
			for tile: Vector2i in path:
				points.append(MapGeo.tile_center(tile.x, tile.y, TILE_SIZE))
			_roads.append(points)


## Surf breaks along the inked coast, and one soft cloud shadow drifts over the
## whole theatre. Both are children so the static layer still draws once.
func _build_animated_layers() -> void:
	_surf = MapSurf.new()
	_surf.name = "Surf"
	add_child(_surf)
	_surf.setup(model, _coast, TILE_SIZE)

	_cloud = ColorRect.new()
	_cloud.name = "CloudShade"
	_cloud.position = Vector2(-CLOUD_MARGIN, -CLOUD_MARGIN)
	_cloud.size = map_size() + Vector2(CLOUD_MARGIN, CLOUD_MARGIN) * 2.0
	_cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/cloudshade.gdshader")
	material.set_shader_parameter("world_size", _cloud.size)
	_cloud.material = material
	add_child(_cloud)


# --- draw -------------------------------------------------------------------


func _draw() -> void:
	if model == null:
		return

	for path: PackedVector2Array in _sea_borders:
		draw_polyline(path, Color(0.18, 0.30, 0.33, 0.20), 1.0, true)
	for path: PackedVector2Array in _province_borders:
		draw_polyline(path, Color(0.235, 0.184, 0.129, 0.32), 1.2, true)
	for path: PackedVector2Array in _coast:
		draw_polyline(path, Color(0.72, 0.82, 0.80, 0.22), 15.0, true)
		draw_polyline(path, Color(0.90, 0.84, 0.68, 0.42), 6.5, true)
		draw_polyline(path, Color(0.24, 0.19, 0.13, 0.16), 6.5, true)
		draw_polyline(path, Color(0.16, 0.12, 0.08, 0.85), 1.8, true)

	for path: PackedVector2Array in _roads:
		draw_polyline(path, Color(0.30, 0.22, 0.14, 0.30), 3.6, true)
		draw_polyline(path, Color(0.26, 0.19, 0.12, 0.62), 1.6, true)

	for glyph: Dictionary in plan.glyphs:
		MapGlyphs.draw(self, glyph)

	for point: Vector2 in plan.passages:
		_draw_passage(point)

	for label: Dictionary in plan.labels:
		_draw_label(label)

	if plan.compass_visible:
		MapGlyphs.compass(self, plan.compass_position, 74.0, _font)


## Two arrows around a ring: the sign of a sea lane between regions.
func _draw_passage(center: Vector2) -> void:
	var ink := Color(0.16, 0.12, 0.08, 0.55)
	var radius: float = 13.0
	draw_arc(center, radius, 0.0, TAU, 28, ink, 1.6, true)
	draw_arc(center, radius * 0.62, PI * 0.15, PI * 0.85, 12, ink, 1.4, true)
	draw_arc(center, radius * 0.62, PI * 1.15, PI * 1.85, 12, ink, 1.4, true)
	draw_circle(center, 2.2, ink)


func _draw_label(label: Dictionary) -> void:
	var text: String = label["text"]
	var position: Vector2 = label["position"]
	if bool(label.get("capital", false)):
		position += Vector2(0, 24)
	var font_size: int = label["size"]
	var width: float = 260.0
	var origin := position - Vector2(width * 0.5, 0.0)
	if String(label["kind"]) == "sea" or String(label["kind"]) == "passage":
		draw_string_outline(
			_font_italic, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 3,
			Color(0.94, 0.90, 0.80, 0.42)
		)
		draw_string(
			_font_italic, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size,
			Color(0.10, 0.23, 0.27, 0.76)
		)
		return
	draw_string_outline(
		_font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 3,
		Color(0.97, 0.94, 0.86, 0.85)
	)
	draw_string(
		_font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size,
		Color(0.11, 0.08, 0.05, 0.96)
	)
