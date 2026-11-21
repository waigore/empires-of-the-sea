class_name MapMarks
extends RefCounted
## Chart seals and survey emblems: ports, capitals, towns, and the commodity
## pictograms the resource lens draws. Kept apart from `MapGlyphs` so terrain
## ink and placed seals do not share one file past the architecture line cap
## (REQ-P3-01). The wash language matches `MapGlyphs` / `MapGround`.

const INK: Color = Color(0.149, 0.118, 0.082, 0.86)
const INK_SOFT: Color = Color(0.149, 0.118, 0.082, 0.42)


## Dispatches a placed seal kind from the canvas plan (`port` / `capital` /
## `town`). Terrain kinds stay on `MapGlyphs.draw`.
static func draw(item: CanvasItem, glyph: Dictionary) -> void:
	var center: Vector2 = glyph["position"]
	var size: float = glyph["size"]
	match String(glyph["kind"]):
		"port":
			_anchor(item, center, size)
		"capital":
			_capital(item, center, size, int(glyph.get("owner", 0)))
		"town":
			_town(item, center, size)


## Resource emblem for the survey lens: the commodity a tile yields, drawn as a
## map symbol rather than a HUD pictogram so it sits in the chart's ink language.
## `tint` is the commodity ink (`Palette.RESOURCE_INK`), never the status ink:
## the ring and slash around the emblem carry the estate's status.
static func resource(
	item: CanvasItem, kind: String, center: Vector2, size: float, tint: Color
) -> void:
	match kind:
		"tree":
			MapGlyphs.tree(item, center, size, 1.0, tint)
		"coin":
			_coin_emblem(item, center, size, tint)
		"wheat":
			_wheat_emblem(item, center, size, tint)
		_:
			_ore_emblem(item, center, size, tint)


## Capital seaboards draw a port each; other coastal provinces keep the single
## generated waterfront port.
static func port_tiles(province: ProvinceState) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var ports: Dictionary = province.ports
	for zone: int in ports.keys():
		var tile: Vector2i = ports[zone]
		if not tiles.has(tile):
			tiles.append(tile)
	if not tiles.is_empty():
		return tiles
	var fallback: Vector2i = province.port_tile
	if fallback.x >= 0:
		tiles.append(fallback)
	return tiles


## A cluster of three cut stones, each with a lit facet and an ink edge.
static func _ore_emblem(item: CanvasItem, center: Vector2, size: float, tint: Color) -> void:
	var radius: float = size * 0.34
	for offset: Vector2 in [Vector2(-0.36, 0.22), Vector2(0.36, 0.22), Vector2(0, -0.30)]:
		var spot: Vector2 = center + offset * size
		var r: float = radius * (0.84 if offset.y > 0.0 else 1.0)
		var shape := PackedVector2Array([
			spot + Vector2(0, -r),
			spot + Vector2(r * 0.86, -r * 0.14),
			spot + Vector2(0, r),
			spot + Vector2(-r * 0.86, -r * 0.14),
		])
		item.draw_colored_polygon(shape, tint)
		item.draw_colored_polygon(
			PackedVector2Array([shape[0], shape[1], spot]),
			Color(0.94, 0.92, 0.86, 0.30)
		)
		item.draw_polyline(_closed(shape), INK, 1.0, true)


static func _coin_emblem(item: CanvasItem, center: Vector2, size: float, tint: Color) -> void:
	var radius: float = size * 0.42
	item.draw_circle(center, radius, tint)
	item.draw_circle(center, radius, INK, false, 1.1, true)
	item.draw_arc(center, radius * 0.62, 0, TAU, 18, Color(0.35, 0.26, 0.09, 0.5), 0.9, true)
	item.draw_circle(center + Vector2(-radius * 0.26, -radius * 0.30), radius * 0.16,
		Color(1.0, 0.96, 0.82, 0.85))


static func _wheat_emblem(item: CanvasItem, center: Vector2, size: float, tint: Color) -> void:
	var stalk: Vector2 = center + Vector2(0, size * 0.46)
	var tip: Vector2 = center + Vector2(0, -size * 0.40)
	item.draw_line(stalk, tip, INK, 1.3, true)
	for i in 3:
		var y: float = tip.y + float(i) * size * 0.24
		for side: float in [-1.0, 1.0]:
			var grain := PackedVector2Array([
				Vector2(center.x, y),
				Vector2(center.x + side * size * 0.26, y - size * 0.13),
				Vector2(center.x + side * size * 0.16, y + size * 0.14),
			])
			item.draw_colored_polygon(grain, tint)
			item.draw_polyline(_closed(grain), INK, 0.9, true)


static func _anchor(item: CanvasItem, center: Vector2, size: float) -> void:
	var radius: float = size * 0.42
	item.draw_arc(
		center + Vector2(0, radius * 0.35), radius, PI * 0.15, PI * 0.85, 14, INK, 1.7, true
	)
	item.draw_line(center + Vector2(0, -radius * 0.9), center + Vector2(0, radius * 0.5), INK, 1.7)
	item.draw_line(
		center + Vector2(-radius * 0.46, -radius * 0.44),
		center + Vector2(radius * 0.46, -radius * 0.44), INK, 1.4
	)
	item.draw_circle(center + Vector2(0, -radius * 0.95), 1.9, INK)


static func _capital(item: CanvasItem, center: Vector2, size: float, owner: int) -> void:
	var color: Color = Palette.faction_color(owner)
	var radius: float = size * 0.55
	item.draw_circle(center, radius * 1.30, Color(0.965, 0.925, 0.827, 0.62))
	var star: PackedVector2Array = MapGlyphs.star_points(center, radius, 5, 0.45)
	item.draw_colored_polygon(star, color)
	item.draw_polyline(_closed(star), Color(0.157, 0.118, 0.078, 0.88), 1.1, true)


## A hamlet of gabled cottages and a church spire: the province town (wiki:
## capital-and-connectivity § Town per province). A parchment halo and ink edges
## keep it legible at fit zoom beside the capital star, which it must not rival.
static func _town(item: CanvasItem, center: Vector2, size: float) -> void:
	item.draw_circle(
		center + Vector2(0, -size * 0.08), size * 0.62, Color(0.965, 0.925, 0.827, 0.58)
	)
	var ground: Vector2 = center + Vector2(0, size * 0.40)
	item.draw_line(
		ground + Vector2(-size * 0.50, 0), ground + Vector2(size * 0.50, 0),
		INK_SOFT, 1.0, true
	)
	for house: Vector3 in [
		Vector3(-0.34, 0.24, 0.40),
		Vector3(0.30, 0.22, 0.34),
		Vector3(-0.02, 0.13, 0.72),
	]:
		var foot: Vector2 = ground + Vector2(house.x * size, -size * 0.02)
		var half: float = house.y * size
		var wall: float = house.z * size * 0.42
		var ridge: Vector2 = foot + Vector2(0, -house.z * size)
		var eave_l: Vector2 = foot + Vector2(-half, -wall)
		var eave_r: Vector2 = foot + Vector2(half, -wall)
		var left: Vector2 = foot + Vector2(-half, 0)
		var right: Vector2 = foot + Vector2(half, 0)
		item.draw_colored_polygon(
			PackedVector2Array([left, right, eave_r, eave_l]),
			Color(0.973, 0.945, 0.867, 0.95)
		)
		item.draw_colored_polygon(
			PackedVector2Array([eave_l, ridge, eave_r]),
			Color(0.404, 0.271, 0.184, 0.96)
		)
		item.draw_polyline(
			_closed(PackedVector2Array([left, eave_l, ridge, eave_r, right])),
			INK, 1.0, true
		)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if result.size() > 0:
		result.append(result[0])
	return result
