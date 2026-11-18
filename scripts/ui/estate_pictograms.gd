class_name EstatePictograms
extends RefCounted
## The estate's own marks (wiki: extraction-and-improvements § Improvement Naming
## — the estate's pictogram; REQ-P1-08, DR-20261119-06). One painter per works
## type: a felled log for a lumber camp, a pick for an ore mine, a fleece for a
## pasture, a horseshoe for a ranch of remounts, a cow's head for a ranch of
## beeves, a broad leaf for a plantation and a stretched hide for a fur post. The
## precious-metal mine keeps `Icon`'s own coin.
##
## Pure painting: a CanvasItem, a centre and a radius in, strokes out — no nodes,
## no state, no catalogue (REQ-P3-03). `Icon` keeps the kinds the whole shell
## shares and delegates these to this home, so neither file grows past its
## published size (REQ-P3-01).

## Every kind this module paints. `Icon.KINDS` carries them too, so a caller may
## ask either home whether a mark can be drawn.
const KINDS: Array[String] = [
	"log", "pick", "sheep", "horse", "cattle", "leaf", "pelt",
]


static func knows(kind: String) -> bool:
	return KINDS.has(kind)


## Paints `kind` on `canvas`, centred, inside `radius`; false when this module
## does not own the kind, so the caller can fall through to its own painters.
static func draw(
	canvas: CanvasItem, kind: String, center: Vector2, radius: float, tint: Color
) -> bool:
	match kind:
		"log":
			_log(canvas, center, radius, tint)
		"pick":
			_pick(canvas, center, radius, tint)
		"sheep":
			_sheep(canvas, center, radius, tint)
		"horse":
			_horse(canvas, center, radius, tint)
		"cattle":
			_cattle(canvas, center, radius, tint)
		"leaf":
			_leaf(canvas, center, radius, tint)
		"pelt":
			_pelt(canvas, center, radius, tint)
		_:
			return false
	return true


## A felled log, end grain to the right: the lumber camp's work.
static func _log(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var body := Rect2(
		center + Vector2(-radius * 0.85, -radius * 0.34),
		Vector2(radius * 1.5, radius * 0.68)
	)
	canvas.draw_rect(body, tint)
	canvas.draw_circle(body.position, radius * 0.34, tint)
	var end: Vector2 = center + Vector2(radius * 0.65, 0)
	canvas.draw_circle(end, radius * 0.34, tint)
	canvas.draw_circle(end, radius * 0.34, Palette.INK, false, _hair(radius), true)
	canvas.draw_circle(end, radius * 0.15, Palette.INK, false, _hair(radius), true)


## A pick: the shaft upright, the head a shallow arc over it. The mine's work.
static func _pick(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	canvas.draw_line(
		center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.9),
		tint, maxf(1.0, radius * 0.16), true
	)
	canvas.draw_polyline(
		PackedVector2Array([
			center + Vector2(-radius * 0.85, -radius * 0.35),
			center + Vector2(-radius * 0.4, -radius * 0.78),
			center + Vector2(radius * 0.4, -radius * 0.78),
			center + Vector2(radius * 0.85, -radius * 0.35),
		]),
		tint, maxf(1.5, radius * 0.26), true
	)


## A fleece with its head and legs: the pasture's own beast.
static func _sheep(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var body := center + Vector2(-radius * 0.1, radius * 0.02)
	for offset: Vector2 in [Vector2(-0.36, 0.02), Vector2(0, -0.16), Vector2(0.34, 0.02)]:
		canvas.draw_circle(body + offset * radius, radius * 0.42, tint)
	# Legs below the fleece, so the shape reads as standing.
	for side: float in [-0.35, 0.2]:
		canvas.draw_line(
			body + Vector2(radius * side, radius * 0.3),
			body + Vector2(radius * side, radius * 0.86),
			Palette.INK, maxf(1.0, radius * 0.12), true
		)
	# The head, turned to the right.
	var head: Vector2 = body + Vector2(radius * 0.72, -radius * 0.08)
	canvas.draw_circle(head, radius * 0.26, Palette.INK)
	canvas.draw_line(
		head + Vector2(radius * 0.1, -radius * 0.4),
		head + Vector2(radius * 0.22, -radius * 0.16),
		Palette.INK, _hair(radius), true
	)


## A horseshoe, opening up, nails struck into it: the ranch that raises
## remounts. A head-and-neck silhouette reads as no animal at a row's 16 px; the
## shoe is unmistakable at any size.
static func _horse(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var shoe: Vector2 = center + Vector2(0, -radius * 0.08)
	var thick: float = maxf(1.5, radius * 0.24)
	canvas.draw_arc(shoe, radius * 0.6, PI * 0.06, PI * 0.94, 18, tint, thick, true)
	# The two heels, turned up, so the shoe is open at the top.
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(
			shoe + Vector2(radius * 0.6 * side, radius * 0.05),
			shoe + Vector2(radius * 0.62 * side, -radius * 0.42),
			tint, thick, true
		)
	# Three nail heads along the iron.
	for i in 3:
		var angle: float = PI * (0.3 + 0.2 * float(i))
		canvas.draw_circle(
			shoe + Vector2(cos(angle), sin(angle)) * radius * 0.6,
			maxf(1.0, radius * 0.07), Palette.INK
		)


## A cow's head, horns out and muzzle down: the ranch that raises beef.
static func _cattle(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var face := PackedVector2Array([
		center + Vector2(0, -radius * 0.62),
		center + Vector2(radius * 0.46, -radius * 0.5),
		center + Vector2(radius * 0.38, radius * 0.3),
		center + Vector2(0, radius * 0.88),
		center + Vector2(-radius * 0.38, radius * 0.3),
		center + Vector2(-radius * 0.46, -radius * 0.5),
	])
	canvas.draw_colored_polygon(face, tint)
	canvas.draw_polyline(face, Palette.INK, _hair(radius), true)
	# Horns sweeping out from the crown.
	for side: float in [-1.0, 1.0]:
		canvas.draw_polyline(
			PackedVector2Array([
				center + Vector2(radius * 0.32 * side, -radius * 0.5),
				center + Vector2(radius * 0.72 * side, -radius * 0.78),
				center + Vector2(radius * 0.86 * side, -radius * 0.5),
			]),
			Palette.INK, maxf(1.0, radius * 0.11), true
		)
	# Two eyes and the muzzle.
	for side: float in [-1.0, 1.0]:
		canvas.draw_circle(
			center + Vector2(radius * 0.18 * side, -radius * 0.2),
			radius * 0.07, Palette.INK
		)
	canvas.draw_circle(center + Vector2(0, radius * 0.5), radius * 0.13, Palette.INK)


## A broad leaf with its midrib: the plantation's crop.
static func _leaf(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius * 0.12, -radius * 0.88),
		center + Vector2(radius * 0.62, -radius * 0.2),
		center + Vector2(radius * 0.34, radius * 0.5),
		center + Vector2(-radius * 0.12, radius * 0.88),
		center + Vector2(-radius * 0.52, radius * 0.34),
		center + Vector2(-radius * 0.62, -radius * 0.28),
	])
	canvas.draw_colored_polygon(points, tint)
	canvas.draw_polyline(points, Palette.INK, _hair(radius), true)
	canvas.draw_line(
		center + Vector2(-radius * 0.12, radius * 0.88),
		center + Vector2(-radius * 0.05, -radius * 0.8),
		Palette.INK, _hair(radius), true
	)
	# Two veins off the rib, so a leaf never reads as a blob.
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(
			center + Vector2(-radius * 0.08, radius * 0.18),
			center + Vector2(-radius * 0.08 + radius * 0.42 * side, radius * 0.5),
			Palette.INK, maxf(1.0, radius * 0.08), true
		)


## A stretched hide, four legs out: the fur post's trade.
static func _pelt(canvas: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius * 0.3, -radius * 0.5),
		center + Vector2(-radius * 0.72, -radius * 0.86),
		center + Vector2(-radius * 0.78, -radius * 0.4),
		center + Vector2(-radius * 0.72, radius * 0.5),
		center + Vector2(-radius * 0.4, radius * 0.88),
		center + Vector2(radius * 0.4, radius * 0.88),
		center + Vector2(radius * 0.72, radius * 0.5),
		center + Vector2(radius * 0.78, -radius * 0.4),
		center + Vector2(radius * 0.72, -radius * 0.86),
		center + Vector2(radius * 0.3, -radius * 0.5),
	])
	canvas.draw_colored_polygon(points, tint)
	canvas.draw_polyline(points, Palette.INK, _hair(radius), true)


## The one stroke weight the markings share: an outline that survives a 16 px
## row without swallowing the fill.
static func _hair(radius: float) -> float:
	return maxf(1.0, radius * 0.1)