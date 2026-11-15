class_name MapCanvas
extends Node2D
## Static map artwork: terrain wash, ink coastline, province borders, glyphs and
## labels. Drawn once per map build, so the per-frame cost is a command replay.
## The wash is a tile-resolution image shaded by `terrain.gdshader`, and the two
## animated layers (surf, cloud shadow) are child nodes so they redraw alone.
## Where names and symbols go is decided by the pure `MapCanvasPlan`.

const TILE_SIZE: float = 22.0
const CLOUD_MARGIN: float = 1400.0
## Passage water reads darker and colder than ordinary sea, so a warp zone is
## found at a glance without selecting a fleet (REQ-P1-07). Kept under the ink
## and inside the map artwork layer, so fog still fogs it like any other water.
const PASSAGE_WASH: Color = Color(0.060, 0.170, 0.400, 0.55)
const PASSAGE_EDGE: Color = Color(0.070, 0.150, 0.190, 0.72)
const PASSAGE_INK: Color = Color(0.085, 0.175, 0.215, 0.84)
const PASSAGE_HALO: Color = Color(0.945, 0.905, 0.805, 0.66)

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
## Smoothed ink boundary of the Passage water on this region.
var _passage_ink: Array[PackedVector2Array] = []
var _font: Font = null
var _font_italic: Font = null
var _surf: MapSurf = null
var _cloud: ColorRect = null


func build(p_model: MapModel, p_world: WorldMap = null) -> void:
	model = p_model
	world = p_world
	_font = UiTheme.serif()
	_font_italic = UiTheme.serif_italic()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	relief = MapWash.build(self, model)
	_build_coast()
	_build_borders()
	plan.build(model, world, TILE_SIZE)
	_build_passage_ink()
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
	_build_passage_ink()
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
	_coast = _hand_paths(InkPaths.smooth_segments(raw, 2), 0.9, 0.6)


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
	_province_borders = _hand_paths(InkPaths.smooth_segments(province_raw, 3), 1.5, 2.2)
	_sea_borders = _hand_paths(InkPaths.smooth_segments(sea_raw, 2), 1.1, 5.4)


## The Passage wash is bounded by hand-inked water, not a tile staircase: the
## zone edge is traced and smoothed like a sea border, so a warp zone reads as
## charted water rather than a UI rectangle (REQ-P1-03 / REQ-P1-07).
func _build_passage_ink() -> void:
	_passage_ink.clear()
	if plan.passage_edges.is_empty():
		return
	_passage_ink = _hand_paths(
		InkPaths.smooth_segments(plan.passage_edges, 3, 1.2), 0.9, 7.1
	)


## Hand-inked copies of the traced boundaries: the Chaikin pass rounds corners
## but leaves long runs straight, and a straight 90-degree run is what reads as
## a grid (REQ-P1-03). Each path gets its own phase so neighbouring provinces
## do not wobble in step.
func _hand_paths(
	paths: Array[PackedVector2Array], amplitude: float, salt: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for i in paths.size():
		result.append(InkPaths.hand(paths[i], amplitude, salt + float(i) * 1.9))
	return result


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

	for run: Rect2 in plan.passage_water:
		draw_rect(run, PASSAGE_WASH, true)
	for path: PackedVector2Array in _passage_ink:
		draw_polyline(path, PASSAGE_EDGE, 1.6, true)
	for path: PackedVector2Array in _sea_borders:
		draw_polyline(path, Color(0.18, 0.30, 0.33, 0.20), 1.0, true)
	for path: PackedVector2Array in _province_borders:
		draw_polyline(path, Color(0.235, 0.184, 0.129, 0.32), 1.2, true)
	for path: PackedVector2Array in _coast:
		draw_polyline(path, Color(0.72, 0.82, 0.80, 0.22), 15.0, true)
		draw_polyline(path, Color(0.90, 0.84, 0.68, 0.42), 6.5, true)
		draw_polyline(path, Color(0.24, 0.19, 0.13, 0.16), 6.5, true)
		draw_polyline(path, Color(0.16, 0.12, 0.08, 0.85), 1.8, true)

	for glyph: Dictionary in plan.glyphs:
		if not MapSymbols.stamp(self, glyph):
			MapGlyphs.draw(self, glyph)

	for point: Vector2 in plan.passages:
		_draw_passage(point)

	for label: Dictionary in plan.labels:
		_draw_label(label)

	if plan.compass_visible:
		MapGlyphs.compass(self, plan.compass_position, 74.0, _font)


## A ringed crossing mark: two opposed arrows running through the ring, over a
## pale halo so it reads on the Passage wash at any zoom (REQ-P1-07). Opposed
## arrows say "a lane through to the other world", where a single dot reads as
## a mere point of interest.
func _draw_passage(center: Vector2) -> void:
	draw_circle(center, 21.0, PASSAGE_HALO)
	draw_arc(center, 18.0, 0.0, TAU, 32, PASSAGE_INK, 2.0, true)
	_arrow(
		Vector2(center.x - 11.0, center.y - 5.5), Vector2(center.x + 11.0, center.y - 5.5)
	)
	_arrow(
		Vector2(center.x + 11.0, center.y + 5.5), Vector2(center.x - 11.0, center.y + 5.5)
	)


## A straight arrow: a shaft stroke and two head barbs.
func _arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, PASSAGE_INK, 2.0, true)
	var direction: Vector2 = (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x)
	draw_polyline(PackedVector2Array([
		to + (-direction + normal) * 5.0, to, to + (-direction - normal) * 5.0
	]), PASSAGE_INK, 2.0, true)


func _draw_label(label: Dictionary) -> void:
	var text: String = label["text"]
	var position: Vector2 = label["position"]
	if String(label["kind"]) == "passage":
		_draw_passage_label(text, position, int(label["size"]))
		return
	if bool(label.get("capital", false)):
		position += Vector2(0, 24)
	var font_size: int = label["size"]
	var width: float = 260.0
	var origin := position - Vector2(width * 0.5, 0.0)
	if String(label["kind"]) == "sea":
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


## The Passage name sits on a small paper slip under the crossing mark, so the
## way across is named on the chart rather than floating as faint italic type.
func _draw_passage_label(text: String, at: Vector2, font_size: int) -> void:
	var slip_text: String = MapGlyphs.spaced(text.to_upper())
	var width: float = _font.get_string_size(
		slip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	var ascent: float = _font.get_ascent(font_size)
	var height: float = ascent + _font.get_descent(font_size) + 4.0
	var slip := Rect2(
		Vector2(at.x - width * 0.5 - 7.0, at.y - 2.0), Vector2(width + 14.0, height)
	)
	draw_rect(slip, Color(0.900, 0.855, 0.745, 0.72), true)
	draw_rect(slip, Color(0.235, 0.184, 0.129, 0.55), false, 1.0)
	draw_string(
		_font, Vector2(slip.position.x, slip.position.y + 2.0 + ascent), slip_text,
		HORIZONTAL_ALIGNMENT_CENTER, slip.size.x, font_size, PASSAGE_INK
	)
