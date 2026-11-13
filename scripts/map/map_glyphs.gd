class_name MapGlyphs
extends RefCounted
## Ink-and-wash map symbols. Each symbol is vector art with a hard outline, so a
## tree or a peak stays readable at fit zoom instead of dissolving into a
## coloured blob the way a filled circle does (REQ-P1-03).

const INK: Color = Color(0.149, 0.118, 0.082, 0.86)
const INK_SOFT: Color = Color(0.149, 0.118, 0.082, 0.42)
const SHADOW: Color = Color(0.129, 0.102, 0.075, 0.13)


static func draw(item: CanvasItem, glyph: Dictionary) -> void:
	var center: Vector2 = glyph["position"]
	var size: float = glyph["size"]
	var flip: float = -1.0 if bool(glyph.get("flip", false)) else 1.0
	match String(glyph["kind"]):
		"mountain":
			_mountain(item, center, size, flip)
		"hill":
			_hill(item, center, size)
		"tree":
			_tree(item, center, size, flip)
		"dune":
			_dune(item, center, size)
		"reed":
			MapGround.reed(item, center, size)
		"grass":
			MapGround.grass(item, center, size)
		"scrub":
			MapGround.scrub(item, center, size, flip)
		"field":
			MapGround.field(item, center, size)
		"port":
			_anchor(item, center, size)
		"capital":
			_capital(item, center, size, int(glyph.get("owner", 0)))
		"town":
			_town(item, center, size)


## Three-quarter peak: lit left face, shaded right face, snow cap, ink ridge.
## A variant hash gives single peaks, shoulder ridges and different widths, so a
## range never reads as one stamp repeated.
static func _mountain(item: CanvasItem, center: Vector2, size: float, flip: float) -> void:
	var half: float = size * 0.5
	var foot: float = half * 0.58
	var variant: float = _hash(center.x, center.y)
	var peak: Vector2 = center + Vector2(half * 0.22 * flip, -half * (0.95 + variant * 0.25))
	var left: Vector2 = center + Vector2(-half * (1.0 + variant * 0.18), foot)
	var right: Vector2 = center + Vector2(half, foot)
	var notch: Vector2 = center + Vector2(half * 0.10, foot)
	var tone: float = 0.86 + variant * 0.26
	if variant > 0.56:
		_shoulder(item, center, half, foot, flip)
	item.draw_colored_polygon(
		PackedVector2Array([left, peak, right]), Color(0.478, 0.416, 0.333, 0.86) * tone
	)
	item.draw_colored_polygon(
		PackedVector2Array([peak, right, notch]), Color(0.298, 0.247, 0.188, 0.74) * tone
	)
	var cap_left: Vector2 = peak.lerp(left, 0.30)
	var cap_right: Vector2 = peak.lerp(right, 0.33)
	var cap_mid: Vector2 = peak.lerp(notch, 0.17)
	item.draw_colored_polygon(
		PackedVector2Array([peak, cap_left, cap_mid, cap_right]),
		Color(0.968, 0.953, 0.906, 0.92)
	)
	item.draw_polyline(PackedVector2Array([left, peak, right]), INK, 1.15, true)
	item.draw_line(peak, notch, INK_SOFT, 0.9, true)
	# Short base hachures: the scree line that anchors a peak to the ground.
	var base_ink := Color(0.235, 0.184, 0.129, 0.34)
	for i in 3:
		var t: float = 0.22 + float(i) * 0.28
		var from: Vector2 = left.lerp(peak, t)
		item.draw_line(
			from + Vector2(0, foot * 0.10), from + Vector2(-half * 0.10, foot * 0.42),
			base_ink, 0.7, true
		)


static func _shoulder(
	item: CanvasItem, center: Vector2, half: float, foot: float, flip: float
) -> void:
	var ridge: Vector2 = center + Vector2(-half * 0.78 * flip, -half * 0.62)
	var back_left: Vector2 = center + Vector2(-half * 1.30 * flip, foot)
	var back_right: Vector2 = center + Vector2(half * 0.10 * flip, foot)
	item.draw_colored_polygon(
		PackedVector2Array([back_left, ridge, back_right]), Color(0.408, 0.353, 0.278, 0.80)
	)
	item.draw_polyline(PackedVector2Array([back_left, ridge, back_right]), INK_SOFT, 0.9, true)


static func _hill(item: CanvasItem, center: Vector2, size: float) -> void:
	var variant: float = _hash(center.x + 7.0, center.y + 3.0)
	var radius: float = size * (0.40 + variant * 0.14)
	var lift: float = 0.50 + variant * 0.24
	item.draw_colored_polygon(_dome(center, radius, lift), Color(0.443, 0.369, 0.271, 0.50))
	item.draw_polyline(_closed(_dome(center, radius, lift)), INK_SOFT, 1.0, true)
	var back: Vector2 = center + Vector2(radius * 0.78, -radius * 0.10)
	item.draw_polyline(
		_closed(_dome(back, radius * 0.58, lift * 0.9)),
		Color(0.235, 0.184, 0.129, 0.28), 0.9, true
	)
	# Two contour arcs inside the dome: the rise is drawn, not just filled.
	var contour := Color(0.259, 0.204, 0.145, 0.30)
	item.draw_arc(
		center + Vector2(0, radius * 0.16), radius * 0.62, PI * 1.12, PI * 1.88, 10,
		contour, 0.8, true
	)
	item.draw_arc(
		center + Vector2(0, radius * 0.16), radius * 0.34, PI * 1.18, PI * 1.82, 8,
		contour, 0.7, true
	)


## Broadleaf grove: shadow, trunk, a secondary crown, then the lit main crown.
## `base` is the wash the crowns are cut from: terrain hillsides pass the fixed
## timber green, the survey lens passes the commodity ink of the tile.
static func _tree(
	item: CanvasItem, center: Vector2, size: float, flip: float,
	base: Color = Color(0.271, 0.361, 0.259, 0.74)
) -> void:
	var trunk_base: Vector2 = center + Vector2(0, size * 0.46)
	var crown: Vector2 = center + Vector2(size * 0.05 * flip, -size * 0.16)
	var radius: float = size * 0.40
	item.draw_circle(trunk_base + Vector2(size * 0.12, -radius * 0.10), radius * 0.62, SHADOW)
	if size >= 11.0:
		_crown(item, crown + Vector2(-radius * 0.90 * flip, radius * 0.80), radius * 0.64, base)
	if size >= 15.0:
		_crown(item, crown + Vector2(radius * 0.86 * flip, radius * 0.62), radius * 0.52, base)
	item.draw_line(trunk_base, crown + Vector2(0, radius * 0.35), INK, 1.3, true)
	_crown(item, crown, radius, base)


## A crown is wobbled and spun from its own position hash, so a forest reads as
## separate trees rather than one stamp repeated across the province.
static func _crown(item: CanvasItem, center: Vector2, radius: float, base: Color) -> void:
	var spin: float = (_hash(center.y + 3.0, center.x + 5.0) - 0.5) * 0.9
	# Each crown is washed a little lighter or darker, so a forest never reads as
	# the same stamp repeated across the province.
	var tone: float = 0.84 + _hash(center.x + 17.0, center.y + 29.0) * 0.30
	var points := PackedVector2Array()
	var start: int = 0
	var best_dot: float = -2.0
	for i in 10:
		var angle: float = TAU * float(i) / 10.0 - PI * 0.5 + spin
		var wobble: float = 0.84 + _hash(center.x + float(i), center.y) * 0.30
		points.append(center + Vector2(cos(angle) * radius * 1.10, sin(angle) * radius) * wobble)
		var facing: float = Vector2(cos(angle), sin(angle)).dot(Vector2(-0.71, -0.71))
		if facing > best_dot:
			best_dot = facing
			start = i
	var lit := PackedVector2Array()
	for k in 6:
		lit.append(points[(start + k) % 10])
	item.draw_colored_polygon(points, _shade(base, tone))
	item.draw_colored_polygon(lit, _shade(base.lightened(0.16), tone))
	item.draw_polyline(_closed(points), Color(0.137, 0.180, 0.133, 0.72), 1.0, true)


## The wash for one crown: the base ink run through the crown's own tone.
static func _shade(base: Color, tone: float) -> Color:
	return Color(base.r * tone, base.g * tone, base.b * tone, base.a * tone)


static func _dune(item: CanvasItem, center: Vector2, size: float) -> void:
	var width: float = size * 0.52
	item.draw_arc(
		center + Vector2(0, size * 0.16), width, PI * 1.05, PI * 1.95, 12,
		Color(0.545, 0.435, 0.278, 0.42), 1.4, true
	)
	item.draw_arc(
		center + Vector2(width * 0.55, size * 0.30), width * 0.60, PI * 1.05, PI * 1.95, 10,
		Color(0.545, 0.435, 0.278, 0.30), 1.1, true
	)


## Resource emblem for the survey lens: the commodity a tile yields, drawn as a
## map symbol rather than a HUD pictogram so it sits in the chart's ink language.
## `tint` is the commodity ink (`Palette.RESOURCE_INK`), never the status ink:
## the ring and slash around the emblem carry the estate's status.
static func resource(
	item: CanvasItem, kind: String, center: Vector2, size: float, tint: Color
) -> void:
	match kind:
		"tree":
			_tree(item, center, size, 1.0, tint)
		"coin":
			_coin_emblem(item, center, size, tint)
		"wheat":
			_wheat_emblem(item, center, size, tint)
		_:
			_ore_emblem(item, center, size, tint)


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
	var star: PackedVector2Array = star_points(center, radius, 5, 0.45)
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


## Eight-point compass rose with a four-letter ring, drawn in the atlas ink.
static func compass(item: CanvasItem, center: Vector2, radius: float, font: Font) -> void:
	var ink := Color(0.16, 0.12, 0.08, 0.42)
	item.draw_arc(center, radius, 0, TAU, 64, ink, 1.2, true)
	item.draw_arc(center, radius * 0.82, 0, TAU, 64, Color(0.16, 0.12, 0.08, 0.22), 0.8, true)
	for i in 8:
		var angle: float = TAU * float(i) / 8.0 - PI * 0.5
		var length: float = radius * (0.95 if i % 2 == 0 else 0.55)
		var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * length
		var left: Vector2 = center + Vector2(cos(angle - 0.16), sin(angle - 0.16)) * radius * 0.16
		var right: Vector2 = center + Vector2(cos(angle + 0.16), sin(angle + 0.16)) * radius * 0.16
		var fill := Color(0.16, 0.12, 0.08, 0.30) if i % 2 == 0 else Color(0.16, 0.12, 0.08, 0.16)
		item.draw_colored_polygon(PackedVector2Array([left, tip, right]), fill)
	item.draw_circle(center, radius * 0.06, ink)
	var letters: Array[String] = ["N", "E", "S", "W"]
	for i in 4:
		var angle: float = TAU * float(i) / 4.0 - PI * 0.5
		var spot: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 12.0)
		item.draw_string(
			font, spot - Vector2(8, -6), letters[i], HORIZONTAL_ALIGNMENT_CENTER, 16, 14,
			Color(0.16, 0.12, 0.08, 0.5)
		)


static func star_points(
	center: Vector2, radius: float, points: int, inner_ratio: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points * 2:
		var angle: float = TAU * float(i) / float(points * 2) - PI * 0.5
		var length: float = radius if i % 2 == 0 else radius * inner_ratio
		result.append(center + Vector2(cos(angle), sin(angle)) * length)
	return result


## Upper half-disc: the closed chord along the bottom makes it a filled hill.
static func _dome(center: Vector2, radius: float, lift: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 13:
		var angle: float = PI + PI * float(i) / 12.0
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * lift))
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if result.size() > 0:
		result.append(result[0])
	return result


static func _hash(x: float, y: float) -> float:
	var h: int = int(x * 97.0) * 374761393 + int(y * 71.0) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Integer hash in 0..1 for glyph placement. Art variation keeps `_hash`.
static func hash01(x: int, y: int) -> float:
	var h: int = x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func spaced(text: String) -> String:
	var out: String = ""
	for i in text.length():
		out += text[i]
		if i < text.length() - 1:
			out += " "
	return out


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
