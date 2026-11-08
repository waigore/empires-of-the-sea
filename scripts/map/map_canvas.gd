class_name MapCanvas
extends Node2D
## Static map artwork: terrain wash, ink coastline, province borders, glyphs and
## labels. Drawn once per map build, so the per-frame cost is a command replay.
## The wash is a tile-resolution image shaded by `terrain.gdshader`, and the two
## animated layers (surf, cloud shadow) are child nodes so they redraw alone.

const TILE_SIZE: float = 22.0
const CLOUD_MARGIN: float = 1400.0

## Relative height per MapModel.Terrain value; drives the hillshade.
const TERRAIN_HEIGHT: Array[float] = [0.0, 0.0, 0.20, 0.32, 0.60, 0.95, 0.26, 0.16]

## Marching-squares edge pairs per corner case (1=TL, 2=TR, 4=BR, 8=BL).
## Edge ids: 0=top, 1=right, 2=bottom, 3=left.
const MS_TABLE: Array = [
	[], [[3, 0]], [[0, 1]], [[3, 1]], [[1, 2]], [[3, 0], [1, 2]], [[0, 2]], [[3, 2]],
	[[2, 3]], [[0, 2]], [[0, 1], [2, 3]], [[1, 2]], [[3, 1]], [[0, 1]], [[3, 0]], [],
]

var model: MapModel = null
## Owning world (both regions), used to mark the sea-lane passages.
var world: WorldMap = null

var _coast: Array[PackedVector2Array] = []
var _province_borders: Array[PackedVector2Array] = []
var _sea_borders: Array[PackedVector2Array] = []
var _roads: Array[PackedVector2Array] = []
var _labels: Array[Dictionary] = []
var _glyphs: Array[Dictionary] = []
## Sea-lane rings marking each warp zone toward the other region.
var _passages: Array[Vector2] = []
var _font: Font = null
var _font_italic: Font = null
var _compass_position: Vector2 = Vector2.ZERO
var _compass_visible: bool = false
var _surf: MapSurf = null
var _cloud: ColorRect = null


func build(p_model: MapModel, p_world: WorldMap = null) -> void:
	model = p_model
	world = p_world
	_font = UiTheme.serif()
	_font_italic = UiTheme.serif_italic()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_wash()
	_build_coast()
	_build_borders()
	_build_roads()
	_build_labels()
	_build_passages()
	_build_glyphs()
	_find_compass_spot()
	_build_animated_layers()
	queue_redraw()


func map_size() -> Vector2:
	if model == null:
		return Vector2.ZERO
	return model.world_size(TILE_SIZE)


# --- build ------------------------------------------------------------------


## Two tile-resolution images: colour + coverage in one, terrain height in the
## other. Everything finer than a tile is the shader's job, which is what keeps
## the terrain grained instead of magnifying one flat texel per tile.
func _build_wash() -> void:
	var w: int = model.width
	var h: int = model.height
	var color_image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var height_image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mask := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pale: Color = Palette.terrain_color(MapModel.Terrain.SHALLOW)
	var relief := FastNoiseLite.new()
	relief.seed = 17
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.frequency = 0.09
	relief.fractal_octaves = 3
	for y in h:
		for x in w:
			var index: int = model.index_of(x, y)
			var terrain: int = model.terrain[index]
			if terrain == MapModel.Terrain.OCEAN:
				color_image.set_pixel(x, y, Color(pale.r, pale.g, pale.b, 0.0))
				height_image.set_pixel(x, y, Color(0, 0, 0, 1))
				mask.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var color: Color = Palette.terrain_color(terrain)
			if terrain == MapModel.Terrain.SHALLOW:
				color_image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.34))
				height_image.set_pixel(x, y, Color(0, 0, 0, 1))
				mask.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			color_image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
			mask.set_pixel(x, y, Color(1, 1, 1, 1))
			var owner: int = model.owner_at(x, y)
			if owner != MapModel.NO_ID:
				var tint: Color = color.lerp(FactionCatalog.color_of(owner), 0.16)
				color_image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, 1.0))
			var height: float = TERRAIN_HEIGHT[terrain]
			height += relief.get_noise_2d(float(x), float(y)) * 0.24
			height = clampf(height, 0.0, 1.0)
			height_image.set_pixel(x, y, Color(height, height, height, 1.0))

	_build_shadow(mask)

	var sprite := Sprite2D.new()
	sprite.name = "Wash"
	sprite.centered = false
	sprite.show_behind_parent = true
	sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = ImageTexture.create_from_image(color_image)
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/terrain.gdshader")
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_image))
	material.set_shader_parameter("texel", Vector2(1.0 / float(w), 1.0 / float(h)))
	material.set_shader_parameter("world_size", model.world_size(TILE_SIZE))
	sprite.material = material
	add_child(sprite)


## Land drop shadow: the land mask offset a few pixels and darkened. It is
## created before the wash so it draws underneath, which lifts the coast off the
## water instead of looking pasted on.
func _build_shadow(mask: Image) -> void:
	var shade := Sprite2D.new()
	shade.name = "Shade"
	shade.centered = false
	shade.show_behind_parent = true
	shade.position = Vector2(5, 6)
	shade.scale = Vector2(TILE_SIZE, TILE_SIZE)
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.texture = ImageTexture.create_from_image(mask)
	shade.modulate = Color(0.10, 0.07, 0.03, 0.22)
	add_child(shade)


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
	_coast = InkPaths.smooth_segments(raw, 2)


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
	return point * TILE_SIZE


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
	for province: Dictionary in model.provinces:
		for path: Array in province.get("road_paths", []):
			if path.size() < 2:
				continue
			var points := PackedVector2Array()
			for tile: Vector2i in path:
				points.append(model.tile_center(tile.x, tile.y, TILE_SIZE))
			_roads.append(points)


func _build_labels() -> void:
	_labels.clear()
	for province: Dictionary in model.provinces:
		if int(province["area"]) < 26:
			continue
		_labels.append({
			"text": String(province["name"]),
			"position": Vector2(province["center"]) * TILE_SIZE,
			"size": 22,
			"kind": "province",
			"capital": bool(province["capital"]),
		})
	for zone: Dictionary in model.sea_zones:
		if int(zone["area"]) < 260:
			continue
		_labels.append({
			"text": _spaced(String(zone["name"])),
			"position": Vector2(zone["center"]) * TILE_SIZE,
			"size": 13,
			"kind": "sea",
		})


## Sea-lane markers: each warp zone gets a ring and a quiet label so the way to
## the other region is legible on a chart (wiki: map-topology).
func _build_passages() -> void:
	_passages.clear()
	if world == null:
		return
	for zone_id: int in world.warp_zones(model.region_id):
		var center: Vector2 = model.sea_zone_center(zone_id) * TILE_SIZE
		if center == Vector2.ZERO:
			continue
		_passages.append(center)
		_labels.append({
			"text": "Passage",
			"position": center + Vector2(0, 26),
			"size": 12,
			"kind": "passage",
		})


func _build_glyphs() -> void:
	_glyphs.clear()
	for y in model.height:
		for x in model.width:
			var terrain: int = model.terrain_at(x, y)
			if terrain == MapModel.Terrain.OCEAN or terrain == MapModel.Terrain.SHALLOW:
				continue
			var roll: float = _hash01(x * 3 + 11, y * 7 + 5)
			var kind: String = ""
			var chance: float = 0.0
			match terrain:
				MapModel.Terrain.MOUNTAINS:
					kind = "mountain"
					chance = 0.62
				MapModel.Terrain.HILLS:
					kind = "hill"
					chance = 0.34
				MapModel.Terrain.FOREST:
					kind = "tree"
					chance = 0.44
				MapModel.Terrain.DESERT:
					kind = "dune"
					chance = 0.14
				MapModel.Terrain.SWAMP:
					kind = "reed"
					chance = 0.24
				_:
					kind = "grass"
					chance = 0.07
			if roll > chance:
				continue
			var jitter := Vector2(
				(_hash01(x + 31, y + 17) - 0.5) * TILE_SIZE * 0.45,
				(_hash01(x + 71, y + 43) - 0.5) * TILE_SIZE * 0.45
			)
			var at: Vector2 = model.tile_center(x, y, TILE_SIZE) + jitter
			if _under_label(at):
				continue
			_glyphs.append({
				"kind": kind,
				"position": at,
				"size": TILE_SIZE * (0.60 + _hash01(x + 5, y + 9) * 0.30),
				"flip": _hash01(x + 13, y + 3) > 0.5,
			})
	for province: Dictionary in model.provinces:
		for port: Vector2i in _port_tiles(province):
			var anchor: Vector2 = model.tile_center(port.x, port.y, TILE_SIZE)
			anchor += _sea_offset(port) * TILE_SIZE * 0.62
			if _under_label(anchor):
				continue
			_glyphs.append({
				"kind": "port",
				"position": anchor,
				"size": TILE_SIZE * 0.8,
				"flip": false,
			})
		if bool(province["capital"]):
			var capital: Vector2i = province.get("capital_tile", CapitalChoice.NO_TILE)
			var anchor: Vector2 = Vector2(province["center"]) * TILE_SIZE
			if capital.x >= 0:
				anchor = model.tile_center(capital.x, capital.y, TILE_SIZE)
			_glyphs.append({
				"kind": "capital",
				"position": anchor,
				"size": TILE_SIZE * 1.1,
				"flip": false,
				"owner": int(province["owner"]),
			})


## A port anchor sits on the water side of its tile, clear of the coastline ink
## and of any province name.
func _sea_offset(tile: Vector2i) -> Vector2:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if model.is_sea(tile.x + offset.x, tile.y + offset.y):
			return Vector2(offset)
	return Vector2.ZERO


## Province names sit in a clearing: a scattered symbol never lands on a label,
## so the type stays readable however dense the terrain is.
func _under_label(at: Vector2) -> bool:
	for label: Dictionary in _labels:
		if String(label["kind"]) != "province":
			continue
		var anchor: Vector2 = label["position"]
		if absf(at.x - anchor.x) < 74.0 and at.y > anchor.y - 18.0 and at.y < anchor.y + 26.0:
			return true
	return false


## Capital seaboards draw a port each; other coastal provinces keep the single
## generated waterfront port.
static func _port_tiles(province: Dictionary) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var ports: Dictionary = province.get("ports", {})
	for zone: int in ports.keys():
		var tile: Vector2i = ports[zone]
		if not tiles.has(tile):
			tiles.append(tile)
	if not tiles.is_empty():
		return tiles
	var fallback: Vector2i = province["port_tile"]
	if fallback.x >= 0:
		tiles.append(fallback)
	return tiles


func _find_compass_spot() -> void:
	_compass_visible = false
	var target := Vector2(float(model.width) * 0.12, float(model.height) * 0.86)
	for radius in range(0, 24, 2):
		for angle in range(0, 360, 30):
			var offset := Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * radius
			var tile: Vector2i = model.tile_at_world(target + offset, TILE_SIZE)
			if model.is_sea(tile.x, tile.y) and model.sea_zone_at(tile.x, tile.y) != MapModel.NO_ID:
				_compass_position = model.tile_center(tile.x, tile.y, TILE_SIZE)
				_compass_visible = true
				return


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

	for glyph: Dictionary in _glyphs:
		MapGlyphs.draw(self, glyph)

	for point: Vector2 in _passages:
		_draw_passage(point)

	for label: Dictionary in _labels:
		_draw_label(label)

	if _compass_visible:
		MapGlyphs.compass(self, _compass_position, 74.0, _font)


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


func _spaced(text: String) -> String:
	var out: String = ""
	for i in text.length():
		out += text[i]
		if i < text.length() - 1:
			out += " "
	return out


func _hash01(x: int, y: int) -> float:
	var h: int = x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
