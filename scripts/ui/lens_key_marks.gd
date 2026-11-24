class_name LensKeyMarks
extends RefCounted
## The small vector marks a lens key prints beside each reading: the survey dot,
## the three road strokes, the band swatch, the heraldic shield and the sea
## pennant. The key's cartouche (`LensLegend`) names the readings; this paints
## the marks, so the cartouche stays one domain (REQ-P3-01). Pure drawing, no
## nodes (REQ-P3-03).


## One swatch per survey reading. `survey` is the Explorer's own compass mark,
## the same the plates carry beside their prospectable count; a plate's badge
## reads `built/linked/held` per resource type, which the key's footer spells out.
static func dot(
	canvas: CanvasItem, center: Vector2, status: String, tint: Color
) -> void:
	if status == "survey":
		CivicGlyphs.explorer(canvas, center, 13.0, Palette.TEXT_DIM, tint)
		return
	var radius: float = 6.2
	if status == "producing":
		canvas.draw_circle(center, radius - 0.6, Color(tint.r, tint.g, tint.b, 0.22))
	canvas.draw_circle(center, 2.0, tint)
	match status:
		"disconnected":
			canvas.draw_arc(center, radius, 0, TAU, 18, tint, 1.1, true)
			canvas.draw_line(
				center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), tint, 1.3, true
			)
		_:
			canvas.draw_arc(center, radius, 0, TAU, 18, tint, 1.4, true)


## The three road strokes at key size: solid ink for a road to the crown, sleepers
## for a railroad, dashes for a road the network does not reach.
static func road(canvas: CanvasItem, start: Vector2, kind: String) -> void:
	var end: Vector2 = start + Vector2(18, 0)
	var ink: Color = Palette.GOLD_DIM
	match kind:
		"rail":
			canvas.draw_line(start, end, ink, 1.8, true)
			for i in 2:
				var x: float = start.x + 6.0 + float(i) * 8.0
				canvas.draw_line(
					Vector2(x, start.y - 3.4), Vector2(x, start.y + 3.0), ink, 1.3, true
				)
		"cut":
			for i in 3:
				var x: float = start.x + float(i) * 7.0
				canvas.draw_line(
					Vector2(x, start.y), Vector2(x + 4.0, start.y),
					Palette.TEXT_DIM, 1.5, true
				)
		_:
			canvas.draw_line(start, end, ink, 2.1, true)


## A wash band's flat swatch with its ink border: the key shows the same tint
## the lens lays on the chart.
static func swatch(canvas: CanvasItem, top_left: Vector2, tint: Color) -> void:
	var box := Rect2(top_left, Vector2(16, 16))
	canvas.draw_rect(box, Color(tint.r, tint.g, tint.b, 0.72))
	canvas.draw_rect(
		box, Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), false, 1.0
	)


## The same heraldic shield the map slips carry, at key size.
static func shield(canvas: CanvasItem, center: Vector2, tint: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-7.0, -8.0),
		center + Vector2(7.0, -8.0),
		center + Vector2(7.0, 1.0),
		center + Vector2(0.0, 9.0),
		center + Vector2(-7.0, 1.0),
	])
	canvas.draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, 0.90))
	canvas.draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[3], points[4], points[0]]),
		Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), 1.0, true
	)


## The pennant over a short mast the slips carry, at key size.
static func pennant(canvas: CanvasItem, center: Vector2, tint: Color) -> void:
	canvas.draw_line(
		center + Vector2(-5.0, -9.0), center + Vector2(-5.0, 9.0),
		Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), 1.2, true
	)
	var fly := PackedVector2Array([
		center + Vector2(-4.0, -8.0),
		center + Vector2(10.0, -3.0),
		center + Vector2(-4.0, 2.0),
	])
	canvas.draw_colored_polygon(fly, Color(tint.r, tint.g, tint.b, 0.92))
